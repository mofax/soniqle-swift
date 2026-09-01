/// The result of a successful compilation: parameterised SQL plus the bindings to hand to
/// the database driver, in the exact order the placeholders appear.
///
/// `bindings[i]` corresponds to the *(i+1)*-th placeholder in ``sql`` (`$1`, `$2`, … for
/// PostgreSQL; the *i*-th `?` for SQLite / MySQL). ``parameterNames`` is a parallel array
/// giving the source `:name` each binding came from — useful for logging and debugging,
/// not needed to execute the statement.
///
/// Compilation is deterministic: identical `(json, parameters, Soniqle configuration)`
/// always produces a byte-identical `CompiledStatement` (see `ADRs/0011`).
public struct CompiledStatement: Sendable, Hashable {

    /// The rendered SQL. Every value is a placeholder; every identifier is quoted. Single
    /// line, single-spaced, no trailing whitespace.
    public let sql: String

    /// The values to bind, positionally. Always scalar — `in` lists are already expanded.
    public let bindings: [SQLValue]

    /// The source parameter name for each entry in ``bindings`` (same length, same order).
    /// A parameter referenced *n* times appears *n* times here.
    public let parameterNames: [String]

    public init(sql: String, bindings: [SQLValue], parameterNames: [String]) {
        self.sql = sql
        self.bindings = bindings
        self.parameterNames = parameterNames
    }
}

extension CompiledStatement: CustomStringConvertible {
    public var description: String {
        """
        CompiledStatement
          sql:      \(sql)
          bindings: [\(zip(parameterNames, bindings).map { "\($0)=\($1)" }.joined(separator: ", "))]
        """
    }
}
