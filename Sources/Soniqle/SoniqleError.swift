/// The single error type thrown by every Soniqle entry point.
///
/// `SoniqleError` is a `struct` wrapping a non-frozen ``Code`` enum rather than being an
/// enum itself. Adding a new ``Code`` in a future release is therefore source-compatible:
/// downstream `switch` statements over ``Code`` already require `@unknown default` across
/// the module boundary. This is what makes typed `throws(SoniqleError)` safe to commit to
/// on the public API (see `ADRs/0013-error-design.md`).
public struct SoniqleError: Error, Sendable, Equatable, CustomStringConvertible {

    /// A stable, machine-readable classification of the failure.
    ///
    /// - Important: This enum is intentionally *not* frozen. Handle it with `@unknown
    ///   default` and treat unrecognised codes as a generic compilation failure.
    public enum Code: Sendable, Equatable {
        /// The `json` argument was not well-formed JSON.
        case malformedJSON
        /// A node had the wrong JSON type or an unexpected key/shape for its position.
        case unexpectedShape
        /// An operator or aggregate name outside Soniqle's closed allowlist was used.
        case unknownOperator
        /// A known operator/aggregate was given the wrong number of arguments.
        case operatorArityMismatch
        /// An identifier failed the strict syntactic allowlist (see `ADRs/0003`).
        case invalidIdentifier
        /// A `$alias.column` reference names a table alias not declared in `from`/`joins`.
        case unknownTableAlias
        /// An `@alias` reference names a `select` alias that was never declared.
        case unknownSelectAlias
        /// Two `select` items, or two tables, declared the same alias.
        case duplicateAlias
        /// A referenced table is not present in the configured ``Schema`` allowlist.
        case tableNotAllowed
        /// A referenced column is not permitted for its table by the ``Schema`` allowlist.
        case columnNotAllowed
        /// A `:name` reference in the query has no entry in `parameters`.
        case missingParameter
        /// A `parameters` entry was supplied that the query never references.
        case unusedParameter
        /// A parameter's ``SQLValue`` case is not valid for the position it is used in
        /// (e.g. a scalar where `in` needs an array, or a non-integer `limit`).
        case parameterTypeMismatch
        /// `limit`/`offset` was negative, non-integer, or above ``CompileOptions/maxLimitValue``.
        case invalidLimit
        /// The AST nests deeper than ``CompileOptions/maxDepth``.
        case depthLimitExceeded
        /// The AST contains more nodes than ``CompileOptions/maxNodeCount``.
        case nodeCountLimitExceeded
        /// The statement would bind more placeholders than the configured / dialect limit.
        case parameterCountLimitExceeded
        /// An `in` list would expand to more placeholders than ``CompileOptions/maxInListExpansion``.
        case inListTooLarge
        /// The rendered SQL would exceed ``CompileOptions/maxSQLLength``.
        case outputTooLarge
        /// A clause that must be non-empty (`from`, `select`) was empty.
        case emptyClause
        /// A syntactically valid construct that Soniqle deliberately does not support yet
        /// (arithmetic expressions, inline value lists, subqueries — see `ADRs/0004`).
        case unsupportedFeature
    }

    /// The failure classification.
    public let code: Code

    /// A human-readable description of what went wrong. Safe to log; contains no secrets
    /// beyond what the caller already put in the query.
    public let message: String

    /// A JSON-Pointer-style path to the offending node (e.g. `/where/1/2`), when the
    /// failure can be localised to a position in the source document. `nil` for failures
    /// that are not tied to a single node (e.g. ``Code/unusedParameter``).
    public let path: String?

    public init(code: Code, message: String, path: String? = nil) {
        self.code = code
        self.message = message
        self.path = path
    }

    public var description: String {
        if let path {
            "SoniqleError(\(code)) at \(path): \(message)"
        } else {
            "SoniqleError(\(code)): \(message)"
        }
    }
}
