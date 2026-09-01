/// SQLite. `?` positional placeholders, double-quoted identifiers, native `NULLS
/// FIRST/LAST` (3.30.0+). `maxBindParameters` reflects the modern compile-time default of
/// `SQLITE_MAX_VARIABLE_NUMBER` (32_766); lower it via ``CompileOptions`` if your build
/// differs.
public struct SQLiteDialect: SQLDialect {
    public let name = "SQLite"
    public let identifierQuote: IdentifierQuote = .double
    public let maxIdentifierLength = 2_000
    public let maxBindParameters = 32_766
    public let booleanRendering: BooleanRendering = .integer
    public let supportsNativeNullsOrdering = true

    public init() {}
}
