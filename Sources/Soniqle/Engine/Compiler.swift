/// Turns a validated ``SelectQuery`` plus its parameter map into a ``CompiledStatement``.
///
/// A single left-to-right pass over the clauses in SQL text order (`SELECT`, `FROM`,
/// `JOIN`s, `WHERE`, `GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT`, `OFFSET`) builds the SQL
/// string and, in lockstep, the positional bindings. Placeholder *n* therefore corresponds
/// to the *n*-th value appended — the output is fully deterministic and the parameter
/// dictionary is only ever *looked up*, never iterated for ordering (see `ADRs/0011`).
final class Compiler {

    private let query: SelectQuery
    private let dialect: any SQLDialect
    private let schema: Schema?
    private let options: CompileOptions
    private let parameters: [String: SQLValue]
    private let writer: SQLWriter
    private let scope: QueryScope
    private let effectiveMaxParameters: Int

    /// The escape character for auto-escaped text matches. `/` is chosen because it has no
    /// special meaning inside a single-quoted string literal in any supported dialect,
    /// unlike `\` which MySQL would itself interpret (see `ADRs/0004`).
    private static let likeEscapeCharacter: Character = "/"

    private var bindings: [SQLValue] = []
    private var parameterNames: [String] = []
    private var usedParameters: Set<String> = []

    init(
        query: SelectQuery,
        dialect: any SQLDialect,
        schema: Schema?,
        options: CompileOptions,
        parameters: [String: SQLValue]
    ) throws(SoniqleError) {
        try StructuralValidator.validate(query, options: options)
        self.query = query
        self.dialect = dialect
        self.schema = schema
        self.options = options
        self.parameters = parameters
        self.writer = SQLWriter(dialect: dialect)
        self.scope = try QueryScope(query: query, schema: schema)
        self.effectiveMaxParameters = min(options.maxOutputParameters, dialect.maxBindParameters)
    }

    // MARK: Top level

    func run() throws(SoniqleError) -> CompiledStatement {
        // Append fragments straight into one buffer rather than collecting a `[String]`
        // and `joined`-ing it. Every clause is emitted in SQL text order, single-spaced;
        // the first fragment ("SELECT") seeds `sql`, each later one is prefixed with a space.
        var sql = "SELECT"
        sql.reserveCapacity(256)
        func add(_ fragment: String) {
            sql += " "
            sql += fragment
        }

        if query.isDistinct { add("DISTINCT") }
        add(try renderSelections())
        add("FROM")
        add(renderTable(query.from))
        for join in query.joins { add(try renderJoin(join)) }

        if let wherePredicate = query.wherePredicate {
            add("WHERE")
            add(try renderPredicate(wherePredicate))
        }
        if !query.groupBy.isEmpty {
            var columns: [String] = []
            columns.reserveCapacity(query.groupBy.count)
            for column in query.groupBy { columns.append(try renderColumn(column)) }
            add("GROUP BY")
            add(columns.joined(separator: ", "))
        }
        if let having = query.having {
            add("HAVING")
            add(try renderPredicate(having))
        }
        if !query.orderBy.isEmpty {
            add("ORDER BY")
            add(try renderOrderBy(query.orderBy))
        }
        if let limit = query.limit { add(try renderLimitClause(limit, keyword: "LIMIT")) }
        if let offset = query.offset { add(try renderLimitClause(offset, keyword: "OFFSET")) }

        guard sql.unicodeScalars.count <= options.maxSQLLength else {
            throw SoniqleError(
                code: .outputTooLarge,
                message: "rendered SQL exceeds maxSQLLength (\(options.maxSQLLength))"
            )
        }

        try checkForUnusedParameters()
        return CompiledStatement(sql: sql, bindings: bindings, parameterNames: parameterNames)
    }

    // MARK: SELECT / FROM / JOIN

    private func renderSelections() throws(SoniqleError) -> String {
        var rendered: [String] = []
        rendered.reserveCapacity(query.selections.count)
        for selection in query.selections {
            let expression = try renderExpression(selection.expression)
            if let alias = selection.alias {
                rendered.append("\(expression) AS \(writer.quoted(alias))")
            } else {
                rendered.append(expression)
            }
        }
        return rendered.joined(separator: ", ")
    }

    private func renderTable(_ table: TableRef) -> String {
        if table.name.raw == table.alias.raw {
            return writer.quoted(table.name)
        }
        return "\(writer.quoted(table.name)) AS \(writer.quoted(table.alias))"
    }

    private func renderJoin(_ join: Join) throws(SoniqleError) -> String {
        let table = renderTable(join.table)
        if join.kind == .cross {
            return "CROSS JOIN \(table)"
        }
        guard let on = join.on else {
            throw SoniqleError(
                code: .unexpectedShape,
                message: "\(join.kind.rawValue) requires an ON predicate"
            )
        }
        return "\(join.kind.rawValue) \(table) ON \(try renderPredicate(on))"
    }

    // MARK: Expressions

    private func renderExpression(_ expression: Expression) throws(SoniqleError) -> String {
        switch expression {
        case .column(let ref):
            return try renderColumn(ref)
        case .parameter(let name):
            let value = try lookUp(name)
            return try bind(value, name: name)
        case .aggregate(let aggregate):
            return try renderAggregate(aggregate)
        }
    }

    private func renderColumn(_ ref: ColumnRef) throws(SoniqleError) -> String {
        guard let alias = ref.tableAlias else {
            // A bare `*`, only reachable from the SELECT list.
            return "*"
        }
        guard let table = scope.tableName(forAlias: alias.raw) else {
            throw SoniqleError(
                code: .unknownTableAlias,
                message: "column reference uses undeclared table alias '\(alias)'"
            )
        }
        switch ref.column {
        case .wildcard:
            if let schema, !schema.allows(column: "*", on: table) {
                throw SoniqleError(
                    code: .columnNotAllowed,
                    message: "'\(alias).*' requires table '\(table)' to permit all columns in the schema allowlist"
                )
            }
            return "\(writer.quoted(alias)).*"
        case .name(let column):
            if let schema, !schema.allows(column: column.raw, on: table) {
                throw SoniqleError(
                    code: .columnNotAllowed,
                    message: "column '\(column)' is not permitted on table '\(table)' by the schema allowlist"
                )
            }
            return "\(writer.quoted(alias)).\(writer.quoted(column))"
        }
    }

    private func renderAggregate(_ aggregate: Aggregate) throws(SoniqleError) -> String {
        let inner: String
        switch aggregate.argument {
        case .star:
            inner = "*"
        case .column(let ref):
            inner = try renderColumn(ref)
        }
        let distinct = aggregate.isDistinct ? "DISTINCT " : ""
        return "\(aggregate.function.rawValue)(\(distinct)\(inner))"
    }

    // MARK: Predicates

    private func renderPredicate(_ predicate: Predicate) throws(SoniqleError) -> String {
        switch predicate {
        case .and(let subs):
            return try join(subs, separator: " AND ", parenthesiseWhenOr: true)
        case .or(let subs):
            return try join(subs, separator: " OR ", parenthesiseWhenOr: false)
        case .not(let inner):
            return "NOT (\(try renderPredicate(inner)))"
        case .compare(let op, let lhs, let rhs):
            return "\(try renderExpression(lhs)) \(op.rawValue) \(try renderExpression(rhs))"
        case .inList(let expr, let name, let negated):
            return try renderInList(expr, parameter: name, negated: negated)
        case .between(let expr, let lower, let upper):
            let target = try renderExpression(expr)
            let low = try renderExpression(lower)
            let high = try renderExpression(upper)
            return "\(target) BETWEEN \(low) AND \(high)"
        case .isNull(let expr, let negated):
            return "\(try renderExpression(expr)) IS \(negated ? "NOT NULL" : "NULL")"
        case .like(let expr, let name, let negated):
            return try renderRawLike(expr, parameter: name, negated: negated)
        case .textMatch(let expr, let name, let kind, let negated):
            return try renderTextMatch(expr, parameter: name, kind: kind, negated: negated)
        }
    }

    /// Renders and joins boolean operands, wrapping a nested operand in parentheses only
    /// when precedence requires it: an `OR` inside an `AND`, or an `AND` inside an `OR`.
    private func join(
        _ subs: [Predicate],
        separator: String,
        parenthesiseWhenOr: Bool
    ) throws(SoniqleError) -> String {
        var rendered: [String] = []
        rendered.reserveCapacity(subs.count)
        for sub in subs {
            let text = try renderPredicate(sub)
            let needsParens: Bool
            switch sub {
            case .or: needsParens = parenthesiseWhenOr
            case .and: needsParens = !parenthesiseWhenOr
            default: needsParens = false
            }
            rendered.append(needsParens ? "(\(text))" : text)
        }
        return rendered.joined(separator: separator)
    }

    private func renderInList(
        _ expr: Expression,
        parameter name: String,
        negated: Bool
    ) throws(SoniqleError) -> String {
        let target = try renderExpression(expr)
        let value = try lookUp(name)
        guard case .array(let elements) = value else {
            throw SoniqleError(
                code: .parameterTypeMismatch,
                message: "'in' parameter ':\(name)' must be an array value"
            )
        }
        guard elements.count <= options.maxInListExpansion else {
            throw SoniqleError(
                code: .inListTooLarge,
                message: "'in' list for ':\(name)' expands to \(elements.count) values, above maxInListExpansion (\(options.maxInListExpansion))"
            )
        }
        if elements.isEmpty {
            // An empty `IN ()` is invalid SQL; fold to a constant. `NOT IN ()` is always
            // true (even for NULL, since no comparison is performed). See `ADRs/0008`.
            return negated ? "(1 = 1)" : "(1 = 0)"
        }
        var placeholders: [String] = []
        placeholders.reserveCapacity(elements.count)
        for element in elements {
            guard element.isScalar else {
                throw SoniqleError(
                    code: .parameterTypeMismatch,
                    message: "'in' array ':\(name)' must not contain nested arrays"
                )
            }
            placeholders.append(try bind(element, name: name))
        }
        return "\(target) \(negated ? "NOT IN" : "IN") (\(placeholders.joined(separator: ", ")))"
    }

    private func renderRawLike(
        _ expr: Expression,
        parameter name: String,
        negated: Bool
    ) throws(SoniqleError) -> String {
        let target = try renderExpression(expr)
        let value = try lookUp(name)
        guard case .string = value else {
            throw SoniqleError(
                code: .parameterTypeMismatch,
                message: "'like' parameter ':\(name)' must be a string value"
            )
        }
        let placeholder = try bind(value, name: name)
        return "\(target) \(negated ? "NOT LIKE" : "LIKE") \(placeholder)"
    }

    private func renderTextMatch(
        _ expr: Expression,
        parameter name: String,
        kind: TextMatchKind,
        negated: Bool
    ) throws(SoniqleError) -> String {
        let target = try renderExpression(expr)
        let value = try lookUp(name)
        guard case .string(let raw) = value else {
            throw SoniqleError(
                code: .parameterTypeMismatch,
                message: "':\(name)' must be a string value for '\(kind.rawValue)'"
            )
        }
        let escaped = escapeLikeLiteral(raw)
        let pattern: String
        switch kind {
        case .contains: pattern = "%\(escaped)%"
        case .startsWith: pattern = "\(escaped)%"
        case .endsWith: pattern = "%\(escaped)"
        }
        let placeholder = try bind(.string(pattern), name: name)
        return "\(target) \(negated ? "NOT LIKE" : "LIKE") \(placeholder) ESCAPE '\(Self.likeEscapeCharacter)'"
    }

    private func escapeLikeLiteral(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        for character in input {
            if character == Self.likeEscapeCharacter || character == "%" || character == "_" {
                result.append(Self.likeEscapeCharacter)
            }
            result.append(character)
        }
        return result
    }

    // MARK: ORDER BY

    private func renderOrderBy(_ terms: [OrderTerm]) throws(SoniqleError) -> String {
        var rendered: [String] = []
        for term in terms {
            let key: String
            switch term.key {
            case .selectAlias(let alias):
                guard scope.selectAliases.contains(alias.raw) else {
                    throw SoniqleError(
                        code: .unknownSelectAlias,
                        message: "orderBy references select alias '@\(alias)' which is not declared in 'select'"
                    )
                }
                key = writer.quoted(alias)
            case .column(let ref):
                key = try renderColumn(ref)
            }

            guard let nulls = term.nulls else {
                rendered.append("\(key) \(term.direction.rawValue)")
                continue
            }
            if dialect.supportsNativeNullsOrdering {
                rendered.append("\(key) \(term.direction.rawValue) NULLS \(nulls.rawValue)")
            } else {
                // Portable emulation: sort on `(key IS NULL)` first. DESC puts the `1`
                // (null) rows first, ASC puts them last.
                let nullsDirection = (nulls == .first) ? "DESC" : "ASC"
                rendered.append("(\(key) IS NULL) \(nullsDirection)")
                rendered.append("\(key) \(term.direction.rawValue)")
            }
        }
        return rendered.joined(separator: ", ")
    }

    // MARK: LIMIT / OFFSET

    private func renderLimitClause(_ value: LimitValue, keyword: String) throws(SoniqleError) -> String {
        switch value {
        case .literal(let number):
            try validateLimitRange(number, keyword: keyword)
            // `number` is a checked, non-negative Int64; its decimal form is digits only.
            return "\(keyword) \(number)"
        case .parameter(let name):
            let resolved = try lookUp(name)
            guard case .int(let number) = resolved else {
                throw SoniqleError(
                    code: .parameterTypeMismatch,
                    message: "\(keyword.lowercased()) parameter ':\(name)' must be an integer value"
                )
            }
            try validateLimitRange(number, keyword: keyword)
            return "\(keyword) \(try bind(.int(number), name: name))"
        }
    }

    private func validateLimitRange(_ number: Int64, keyword: String) throws(SoniqleError) {
        guard number >= 0 else {
            throw SoniqleError(code: .invalidLimit, message: "\(keyword.lowercased()) must not be negative")
        }
        guard number <= options.maxLimitValue else {
            throw SoniqleError(
                code: .invalidLimit,
                message: "\(keyword.lowercased()) \(number) exceeds maxLimitValue (\(options.maxLimitValue))"
            )
        }
    }

    // MARK: Parameter binding

    private func lookUp(_ name: String) throws(SoniqleError) -> SQLValue {
        guard let value = parameters[name] else {
            throw SoniqleError(
                code: .missingParameter,
                message: "the query references ':\(name)' but no such parameter was supplied"
            )
        }
        usedParameters.insert(name)
        return value
    }

    /// Appends one scalar binding and returns its placeholder token.
    private func bind(_ value: SQLValue, name: String) throws(SoniqleError) -> String {
        guard value.isScalar else {
            throw SoniqleError(
                code: .parameterTypeMismatch,
                message: "parameter ':\(name)' is an array but is used where a single value is required"
            )
        }
        let position = bindings.count + 1
        guard position <= effectiveMaxParameters else {
            throw SoniqleError(
                code: .parameterCountLimitExceeded,
                message: "statement would bind more than \(effectiveMaxParameters) parameters"
            )
        }
        bindings.append(value)
        parameterNames.append(name)
        return dialect.placeholder(position: position)
    }

    private func checkForUnusedParameters() throws(SoniqleError) {
        let unused = Set(parameters.keys).subtracting(usedParameters).sorted()
        guard let first = unused.first else { return }
        let message = unused.count == 1
            ? "parameter ':\(first)' was supplied but is never referenced by the query"
            : "parameters \(unused.map { ":\($0)" }.joined(separator: ", ")) were supplied but are never referenced by the query"
        throw SoniqleError(code: .unusedParameter, message: message)
    }
}
