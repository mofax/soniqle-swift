#if canImport(FoundationEssentials)
internal import FoundationEssentials
#else
internal import Foundation
#endif

/// Transforms a decoded ``JSONValue`` document into a typed ``SelectQuery``.
///
/// The parser is strict: unknown object keys, wrong node types, bad arities and bare string
/// literals are all hard errors carrying a JSON-Pointer ``SoniqleError/path``. It also
/// bounds its own recursion by ``CompileOptions/maxDepth`` so a deeply nested document
/// fails cleanly rather than exhausting the stack.
final class JSONParser {

    private let maxIdentifierLength: Int
    private let maxDepth: Int
    /// Parameter names are validated with a fixed, generous bound independent of the SQL
    /// dialect's identifier limit.
    private static let maxParameterNameLength = 128

    init(maxIdentifierLength: Int, maxDepth: Int) {
        self.maxIdentifierLength = maxIdentifierLength
        self.maxDepth = maxDepth
    }

    // MARK: Entry point

    static func parse(
        jsonData: Data,
        maxIdentifierLength: Int,
        maxDepth: Int
    ) throws(SoniqleError) -> SelectQuery {
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: jsonData)
        } catch {
            throw SoniqleError(
                code: .malformedJSON,
                message: "input is not well-formed JSON: \(error)",
                path: nil
            )
        }
        let parser = JSONParser(maxIdentifierLength: maxIdentifierLength, maxDepth: maxDepth)
        return try parser.parseRoot(root)
    }

    // MARK: Root

    private static let allowedRootKeys: Set<String> = [
        "distinct", "select", "from", "joins", "where",
        "groupBy", "having", "orderBy", "limit", "offset",
    ]

    private func parseRoot(_ value: JSONValue) throws(SoniqleError) -> SelectQuery {
        guard let pairs = value.objectPairs else {
            throw err(.unexpectedShape, "the query must be a JSON object", "")
        }
        for pair in pairs where !Self.allowedRootKeys.contains(pair.key) {
            throw err(.unexpectedShape, "unknown top-level key '\(pair.key)'", "/\(pair.key)")
        }

        guard let fromValue = value["from"] else {
            throw err(.emptyClause, "'from' is required", "")
        }
        guard let selectValue = value["select"] else {
            throw err(.emptyClause, "'select' is required", "")
        }

        let from = try parseTableRef(fromValue, at: "/from")
        let selections = try parseSelections(selectValue, at: "/select")

        var joins: [Join] = []
        if let joinsValue = value["joins"] { joins = try parseJoins(joinsValue, at: "/joins") }

        var wherePredicate: Predicate?
        if let whereValue = value["where"] {
            wherePredicate = try parsePredicate(whereValue, at: "/where", depth: 1)
        }

        var groupBy: [ColumnRef] = []
        if let groupByValue = value["groupBy"] { groupBy = try parseGroupBy(groupByValue, at: "/groupBy") }

        var having: Predicate?
        if let havingValue = value["having"] {
            having = try parsePredicate(havingValue, at: "/having", depth: 1)
        }

        var orderBy: [OrderTerm] = []
        if let orderByValue = value["orderBy"] { orderBy = try parseOrderBy(orderByValue, at: "/orderBy") }

        var limit: LimitValue?
        if let limitValue = value["limit"] { limit = try parseLimitValue(limitValue, at: "/limit") }

        var offset: LimitValue?
        if let offsetValue = value["offset"] { offset = try parseLimitValue(offsetValue, at: "/offset") }

        let isDistinct = try parseOptionalBool(value["distinct"], at: "/distinct")

        return SelectQuery(
            isDistinct: isDistinct,
            selections: selections,
            from: from,
            joins: joins,
            wherePredicate: wherePredicate,
            groupBy: groupBy,
            having: having,
            orderBy: orderBy,
            limit: limit,
            offset: offset
        )
    }

    // MARK: from / joins

    private func parseTableRef(_ value: JSONValue, at path: String) throws(SoniqleError) -> TableRef {
        switch value {
        case .string(let name):
            let identifier = try identifier(name, at: path)
            return TableRef(name: identifier, alias: identifier)
        case .array(let elements):
            guard elements.count == 2,
                  let name = elements[0].stringValue,
                  let alias = elements[1].stringValue
            else {
                throw err(.unexpectedShape, "a table reference must be a name or [name, alias]", path)
            }
            return TableRef(
                name: try identifier(name, at: "\(path)/0"),
                alias: try identifier(alias, at: "\(path)/1")
            )
        default:
            throw err(.unexpectedShape, "a table reference must be a string or [name, alias]", path)
        }
    }

    private func parseJoins(_ value: JSONValue, at path: String) throws(SoniqleError) -> [Join] {
        guard let elements = value.arrayElements else {
            throw err(.unexpectedShape, "'joins' must be an array", path)
        }
        var joins: [Join] = []
        joins.reserveCapacity(elements.count)
        for (index, element) in elements.enumerated() {
            joins.append(try parseJoin(element, at: "\(path)/\(index)"))
        }
        return joins
    }

    private func parseJoin(_ value: JSONValue, at path: String) throws(SoniqleError) -> Join {
        guard let elements = value.arrayElements, let head = elements.first?.stringValue else {
            throw err(.unexpectedShape, "a join must be [kind, table, on] (or [\"cross\", table])", path)
        }
        let kind: JoinKind
        switch head {
        case "inner": kind = .inner
        case "left": kind = .left
        case "right": kind = .right
        case "full": kind = .full
        case "cross": kind = .cross
        default:
            throw err(.unknownOperator, "unknown join kind '\(head)'", "\(path)/0")
        }

        if kind == .cross {
            guard elements.count == 2 else {
                throw err(.operatorArityMismatch, "a cross join must be [\"cross\", table]", path)
            }
            return Join(kind: kind, table: try parseTableRef(elements[1], at: "\(path)/1"), on: nil)
        }

        guard elements.count == 3 else {
            throw err(.operatorArityMismatch, "a \(head) join must be [\"\(head)\", table, on]", path)
        }
        return Join(
            kind: kind,
            table: try parseTableRef(elements[1], at: "\(path)/1"),
            on: try parsePredicate(elements[2], at: "\(path)/2", depth: 1)
        )
    }

    // MARK: select

    private func parseSelections(_ value: JSONValue, at path: String) throws(SoniqleError) -> [Selection] {
        guard let elements = value.arrayElements else {
            throw err(.unexpectedShape, "'select' must be an array", path)
        }
        guard !elements.isEmpty else {
            throw err(.emptyClause, "'select' must not be empty", path)
        }
        var selections: [Selection] = []
        selections.reserveCapacity(elements.count)
        for (index, element) in elements.enumerated() {
            selections.append(try parseSelection(element, at: "\(path)/\(index)"))
        }
        return selections
    }

    private func parseSelection(_ value: JSONValue, at path: String) throws(SoniqleError) -> Selection {
        // `["as", <expr>, "alias"]`
        if let elements = value.arrayElements, elements.first?.stringValue == "as" {
            guard elements.count == 3, let aliasName = elements[2].stringValue else {
                throw err(.operatorArityMismatch, "'as' must be [\"as\", expression, \"alias\"]", path)
            }
            return Selection(
                expression: try parseSelectExpression(elements[1], at: "\(path)/1"),
                alias: try identifier(aliasName, at: "\(path)/2")
            )
        }
        return Selection(expression: try parseSelectExpression(value, at: path), alias: nil)
    }

    /// A select-list expression additionally permits a bare `*`.
    private func parseSelectExpression(_ value: JSONValue, at path: String) throws(SoniqleError) -> Expression {
        if value.stringValue == ColumnToken.wildcardToken {
            return .column(ColumnRef(tableAlias: nil, column: .wildcard))
        }
        return try parseExpression(value, at: path)
    }

    // MARK: expressions

    /// A value-producing expression: `$alias.col`, `:param`, or an aggregate array.
    private func parseExpression(_ value: JSONValue, at path: String) throws(SoniqleError) -> Expression {
        switch value {
        case .string(let token):
            return try parseTokenExpression(token, at: path)
        case .array:
            return .aggregate(try parseAggregate(value, at: path))
        default:
            throw err(.unexpectedShape, "expected a column reference, a :parameter, or an aggregate", path)
        }
    }

    private func parseTokenExpression(_ token: String, at path: String) throws(SoniqleError) -> Expression {
        guard let first = token.first else {
            throw err(.unexpectedShape, "empty token", path)
        }
        switch first {
        case "$":
            return .column(try parseColumnReference(token, at: path))
        case ":":
            return .parameter(try parameterName(token, at: path))
        case "@":
            throw err(.unexpectedShape, "'@alias' references are only valid inside 'orderBy'", path)
        default:
            throw err(
                .unexpectedShape,
                "bare literals are not permitted; supply a value as a :parameter (got '\(token)')",
                path
            )
        }
    }

    private func parseColumnReference(_ token: String, at path: String) throws(SoniqleError) -> ColumnRef {
        precondition(token.first == "$")
        let body = token.dropFirst()
        guard let dot = body.firstIndex(of: ".") else {
            throw err(.unexpectedShape, "a column reference must be '$alias.column' (got '\(token)')", path)
        }
        let aliasPart = String(body[body.startIndex..<dot])
        let columnPart = String(body[body.index(after: dot)...])
        guard !columnPart.contains(".") else {
            throw err(.unexpectedShape, "a column reference has exactly one '.' (got '\(token)')", path)
        }
        let alias = try identifier(aliasPart, at: path)
        if columnPart == ColumnToken.wildcardToken {
            return ColumnRef(tableAlias: alias, column: .wildcard)
        }
        return ColumnRef(tableAlias: alias, column: .name(try identifier(columnPart, at: path)))
    }

    private func parseAggregate(_ value: JSONValue, at path: String) throws(SoniqleError) -> Aggregate {
        guard let elements = value.arrayElements, let head = elements.first?.stringValue else {
            throw err(.unexpectedShape, "expected an aggregate like [\"count\", \"$t.col\"]", path)
        }
        let function: AggregateFunction
        switch head {
        case "count": function = .count
        case "sum": function = .sum
        case "avg": function = .avg
        case "min": function = .min
        case "max": function = .max
        default:
            throw err(.unknownOperator, "unknown aggregate '\(head)'", "\(path)/0")
        }
        guard elements.count == 2 else {
            throw err(.operatorArityMismatch, "'\(head)' takes exactly one argument", path)
        }

        let argValue = elements[1]
        var isDistinct = false
        var innerValue = argValue
        var innerPath = "\(path)/1"
        if let inner = argValue.arrayElements, inner.first?.stringValue == "distinct" {
            guard inner.count == 2 else {
                throw err(.operatorArityMismatch, "'distinct' takes exactly one argument", "\(path)/1")
            }
            isDistinct = true
            innerValue = inner[1]
            innerPath = "\(path)/1/1"
        }

        let argument: AggregateArgument
        if innerValue.stringValue == ColumnToken.wildcardToken {
            guard function == .count, !isDistinct else {
                throw err(.unexpectedShape, "'*' is only valid as 'count' with no 'distinct'", innerPath)
            }
            argument = .star
        } else if let token = innerValue.stringValue, token.first == "$" {
            argument = .column(try parseColumnReference(token, at: innerPath))
        } else {
            throw err(.unexpectedShape, "an aggregate argument must be '*' or a '$alias.column'", innerPath)
        }
        return Aggregate(function: function, isDistinct: isDistinct, argument: argument)
    }

    // MARK: predicates

    private func parsePredicate(_ value: JSONValue, at path: String, depth: Int) throws(SoniqleError) -> Predicate {
        guard depth <= maxDepth else {
            throw err(.depthLimitExceeded, "predicate nesting exceeds maxDepth (\(maxDepth))", path)
        }
        guard let elements = value.arrayElements, let head = elements.first?.stringValue else {
            throw err(.unexpectedShape, "a predicate must be an array beginning with an operator", path)
        }
        // A lazy slice, not a copy: `operands` is only ever read here. `elements` is a
        // whole array from `JSONValue.array`, so the slice is indexed `1 ..< elements.count`
        // — positional reads below rebase through `operands.startIndex`.
        let operands = elements.dropFirst()

        switch head {
        case "and", "or":
            guard operands.count >= 2 else {
                throw err(.operatorArityMismatch, "'\(head)' needs at least two operands", path)
            }
            var parsed: [Predicate] = []
            parsed.reserveCapacity(operands.count)
            for (index, operand) in operands.enumerated() {
                parsed.append(try parsePredicate(operand, at: "\(path)/\(index + 1)", depth: depth + 1))
            }
            return head == "and" ? .and(parsed) : .or(parsed)

        case "not":
            guard operands.count == 1 else {
                throw err(.operatorArityMismatch, "'not' takes exactly one operand", path)
            }
            return .not(try parsePredicate(operands[operands.startIndex], at: "\(path)/1", depth: depth + 1))

        case "=", "==":
            return try comparison(.equal, operands, path)
        case "!=", "<>":
            return try comparison(.notEqual, operands, path)
        case "<":
            return try comparison(.lessThan, operands, path)
        case "<=":
            return try comparison(.lessThanOrEqual, operands, path)
        case ">":
            return try comparison(.greaterThan, operands, path)
        case ">=":
            return try comparison(.greaterThanOrEqual, operands, path)

        case "in", "not-in":
            guard operands.count == 2 else {
                throw err(.operatorArityMismatch, "'\(head)' takes [expression, :parameter]", path)
            }
            let base = operands.startIndex
            if operands[base + 1].arrayElements != nil {
                throw err(
                    .unsupportedFeature,
                    "inline value lists are not supported; pass an array :parameter",
                    "\(path)/2"
                )
            }
            guard let token = operands[base + 1].stringValue, token.first == ":" else {
                throw err(.unexpectedShape, "the right side of '\(head)' must be a :parameter", "\(path)/2")
            }
            return .inList(
                try parseExpression(operands[base], at: "\(path)/1"),
                parameter: try parameterName(token, at: "\(path)/2"),
                negated: head == "not-in"
            )

        case "between":
            guard operands.count == 3 else {
                throw err(.operatorArityMismatch, "'between' takes [expression, lower, upper]", path)
            }
            let base = operands.startIndex
            return .between(
                try parseExpression(operands[base], at: "\(path)/1"),
                lower: try parseExpression(operands[base + 1], at: "\(path)/2"),
                upper: try parseExpression(operands[base + 2], at: "\(path)/3")
            )

        case "is-null", "is-not-null":
            guard operands.count == 1 else {
                throw err(.operatorArityMismatch, "'\(head)' takes exactly one operand", path)
            }
            return .isNull(try parseExpression(operands[operands.startIndex], at: "\(path)/1"), negated: head == "is-not-null")

        case "like", "not-like":
            let (expr, param) = try textOperands(operands, head: head, path: path)
            return .like(expr, pattern: param, negated: head == "not-like")

        case "contains", "not-contains":
            let (expr, param) = try textOperands(operands, head: head, path: path)
            return .textMatch(expr, parameter: param, kind: .contains, negated: head == "not-contains")
        case "starts-with", "not-starts-with":
            let (expr, param) = try textOperands(operands, head: head, path: path)
            return .textMatch(expr, parameter: param, kind: .startsWith, negated: head == "not-starts-with")
        case "ends-with", "not-ends-with":
            let (expr, param) = try textOperands(operands, head: head, path: path)
            return .textMatch(expr, parameter: param, kind: .endsWith, negated: head == "not-ends-with")

        default:
            throw err(.unknownOperator, "unknown operator '\(head)'", "\(path)/0")
        }
    }

    private func comparison(
        _ op: ComparisonOperator,
        _ operands: ArraySlice<JSONValue>,
        _ path: String
    ) throws(SoniqleError) -> Predicate {
        guard operands.count == 2 else {
            throw err(.operatorArityMismatch, "'\(op.rawValue)' takes exactly two operands", path)
        }
        let base = operands.startIndex
        return .compare(
            op,
            try parseExpression(operands[base], at: "\(path)/1"),
            try parseExpression(operands[base + 1], at: "\(path)/2")
        )
    }

    private func textOperands(
        _ operands: ArraySlice<JSONValue>,
        head: String,
        path: String
    ) throws(SoniqleError) -> (Expression, String) {
        guard operands.count == 2 else {
            throw err(.operatorArityMismatch, "'\(head)' takes [expression, :parameter]", path)
        }
        let base = operands.startIndex
        guard let token = operands[base + 1].stringValue, token.first == ":" else {
            throw err(.unexpectedShape, "the right side of '\(head)' must be a :parameter", "\(path)/2")
        }
        return (
            try parseExpression(operands[base], at: "\(path)/1"),
            try parameterName(token, at: "\(path)/2")
        )
    }

    // MARK: groupBy / orderBy

    private func parseGroupBy(_ value: JSONValue, at path: String) throws(SoniqleError) -> [ColumnRef] {
        guard let elements = value.arrayElements else {
            throw err(.unexpectedShape, "'groupBy' must be an array of column references", path)
        }
        var columns: [ColumnRef] = []
        columns.reserveCapacity(elements.count)
        for (index, element) in elements.enumerated() {
            let elementPath = "\(path)/\(index)"
            guard let token = element.stringValue, token.first == "$" else {
                throw err(.unexpectedShape, "'groupBy' entries must be '$alias.column' references", elementPath)
            }
            let column = try parseColumnReference(token, at: elementPath)
            guard case .name = column.column else {
                throw err(.unexpectedShape, "'groupBy' cannot use a '*' wildcard", elementPath)
            }
            columns.append(column)
        }
        return columns
    }

    private func parseOrderBy(_ value: JSONValue, at path: String) throws(SoniqleError) -> [OrderTerm] {
        guard let elements = value.arrayElements else {
            throw err(.unexpectedShape, "'orderBy' must be an array", path)
        }
        var terms: [OrderTerm] = []
        terms.reserveCapacity(elements.count)
        for (index, element) in elements.enumerated() {
            terms.append(try parseOrderTerm(element, at: "\(path)/\(index)"))
        }
        return terms
    }

    private func parseOrderTerm(_ value: JSONValue, at path: String) throws(SoniqleError) -> OrderTerm {
        let keyValue: JSONValue
        var direction: Direction = .ascending
        var nulls: NullsOrder?

        if let elements = value.arrayElements {
            guard (1...3).contains(elements.count) else {
                throw err(.operatorArityMismatch, "an orderBy term is [key], [key, dir] or [key, dir, nulls]", path)
            }
            keyValue = elements[0]
            if elements.count >= 2 {
                direction = try parseDirection(elements[1], at: "\(path)/1")
            }
            if elements.count == 3 {
                nulls = try parseNullsOrder(elements[2], at: "\(path)/2")
            }
        } else {
            keyValue = value
        }

        guard let token = keyValue.stringValue else {
            throw err(.unexpectedShape, "an orderBy key must be '@alias' or '$alias.column'", path)
        }
        let key: OrderKey
        switch token.first {
        case "@":
            key = .selectAlias(try identifier(String(token.dropFirst()), at: path))
        case "$":
            key = .column(try parseColumnReference(token, at: path))
        default:
            throw err(.unexpectedShape, "an orderBy key must be '@alias' or '$alias.column' (got '\(token)')", path)
        }
        return OrderTerm(key: key, direction: direction, nulls: nulls)
    }

    private func parseDirection(_ value: JSONValue, at path: String) throws(SoniqleError) -> Direction {
        switch value.stringValue?.lowercased() {
        case "asc": .ascending
        case "desc": .descending
        default:
            throw err(.unexpectedShape, "sort direction must be \"asc\" or \"desc\"", path)
        }
    }

    private func parseNullsOrder(_ value: JSONValue, at path: String) throws(SoniqleError) -> NullsOrder {
        switch value.stringValue?.lowercased() {
        case "nulls-first", "first": .first
        case "nulls-last", "last": .last
        default:
            throw err(.unexpectedShape, "nulls ordering must be \"nulls-first\" or \"nulls-last\"", path)
        }
    }

    // MARK: limit / offset / distinct

    private func parseLimitValue(_ value: JSONValue, at path: String) throws(SoniqleError) -> LimitValue {
        switch value {
        case .int(let raw):
            guard raw >= 0 else {
                throw err(.invalidLimit, "'\(path.dropFirst())' must not be negative", path)
            }
            return .literal(raw)
        case .string(let token):
            guard token.first == ":" else {
                throw err(.unexpectedShape, "a string limit/offset must be a :parameter", path)
            }
            return .parameter(try parameterName(token, at: path))
        default:
            throw err(.unexpectedShape, "limit/offset must be a non-negative integer or a :parameter", path)
        }
    }

    private func parseOptionalBool(_ value: JSONValue?, at path: String) throws(SoniqleError) -> Bool {
        switch value {
        case .none: false
        case .bool(let flag): flag
        default:
            throw err(.unexpectedShape, "'\(path.dropFirst())' must be a boolean", path)
        }
    }

    // MARK: identifier helpers

    private func identifier(_ candidate: String, at path: String) throws(SoniqleError) -> ValidatedIdentifier {
        switch ValidatedIdentifier.validate(candidate, maxLength: maxIdentifierLength) {
        case .success(let identifier):
            return identifier
        case .failure(let rejection):
            throw err(.invalidIdentifier, "invalid identifier '\(candidate)': \(rejection.reason)", path)
        }
    }

    private func parameterName(_ token: String, at path: String) throws(SoniqleError) -> String {
        precondition(token.first == ":")
        let name = String(token.dropFirst())
        switch ValidatedIdentifier.validate(name, maxLength: Self.maxParameterNameLength) {
        case .success(let identifier):
            return identifier.raw
        case .failure(let rejection):
            throw err(.invalidIdentifier, "invalid parameter name ':\(name)': \(rejection.reason)", path)
        }
    }

    private func err(_ code: SoniqleError.Code, _ message: String, _ path: String) -> SoniqleError {
        SoniqleError(code: code, message: message, path: path.isEmpty ? nil : path)
    }
}

extension ColumnToken {
    static let wildcardToken = "*"
}
