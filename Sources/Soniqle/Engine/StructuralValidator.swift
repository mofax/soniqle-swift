/// Walks a ``SelectQuery`` and rejects it if it nests deeper than
/// ``CompileOptions/maxDepth`` or contains more than ``CompileOptions/maxNodeCount`` nodes.
///
/// This runs for *both* entry points — the JSON frontend and the direct
/// ``Soniqle/compile(_:parameters:)`` — so a hand-built AST is bounded too. The JSON parser
/// additionally guards its own recursion while decoding, so a pathological document cannot
/// exhaust the stack before it ever reaches this check.
enum StructuralValidator {

    static func validate(_ query: SelectQuery, options: CompileOptions) throws(SoniqleError) {
        let walker = Walker(options: options)
        try walker.walk(query)
    }

    private final class Walker {
        let options: CompileOptions
        var nodeCount = 0

        init(options: CompileOptions) { self.options = options }

        func bump() throws(SoniqleError) {
            nodeCount += 1
            if nodeCount > options.maxNodeCount {
                throw SoniqleError(
                    code: .nodeCountLimitExceeded,
                    message: "query contains more than \(options.maxNodeCount) nodes"
                )
            }
        }

        func checkDepth(_ depth: Int) throws(SoniqleError) {
            if depth > options.maxDepth {
                throw SoniqleError(
                    code: .depthLimitExceeded,
                    message: "query nests deeper than maxDepth (\(options.maxDepth))"
                )
            }
        }

        func walk(_ query: SelectQuery) throws(SoniqleError) {
            try bump()
            for selection in query.selections { try expression(selection.expression, depth: 1) }
            try bump() // FROM
            for join in query.joins {
                try bump()
                if let on = join.on { try predicate(on, depth: 1) }
            }
            if let wherePredicate = query.wherePredicate { try predicate(wherePredicate, depth: 1) }
            for _ in query.groupBy { try bump() }
            if let having = query.having { try predicate(having, depth: 1) }
            for term in query.orderBy {
                try bump()
                if case .column = term.key { try bump() }
            }
            if query.limit != nil { try bump() }
            if query.offset != nil { try bump() }
        }

        func expression(_ expression: Expression, depth: Int) throws(SoniqleError) {
            try checkDepth(depth)
            try bump()
            // Expressions do not nest further in v1 (no arithmetic); aggregates hold at
            // most one column, already counted by `bump()`.
        }

        func predicate(_ predicate: Predicate, depth: Int) throws(SoniqleError) {
            try checkDepth(depth)
            try bump()
            switch predicate {
            case .and(let subs), .or(let subs):
                for sub in subs { try self.predicate(sub, depth: depth + 1) }
            case .not(let inner):
                try self.predicate(inner, depth: depth + 1)
            case .compare(_, let lhs, let rhs):
                try expression(lhs, depth: depth + 1)
                try expression(rhs, depth: depth + 1)
            case .inList(let expr, _, _):
                try expression(expr, depth: depth + 1)
            case .between(let expr, let lower, let upper):
                try expression(expr, depth: depth + 1)
                try expression(lower, depth: depth + 1)
                try expression(upper, depth: depth + 1)
            case .isNull(let expr, _):
                try expression(expr, depth: depth + 1)
            case .like(let expr, _, _), .textMatch(let expr, _, _, _):
                try expression(expr, depth: depth + 1)
            }
        }
    }
}
