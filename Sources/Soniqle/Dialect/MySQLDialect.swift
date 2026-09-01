/// MySQL / MariaDB in its default configuration. `?` positional placeholders, backtick
/// identifiers, a 64-character identifier limit, and **no** native `NULLS FIRST/LAST` — the
/// engine emits a portable `(expr IS NULL)` companion sort key when NULL ordering is
/// requested.
///
/// Backtick quoting is used unconditionally rather than `"` so the output does not depend
/// on the server's `ANSI_QUOTES` mode.
public struct MySQLDialect: SQLDialect {
    public let name = "MySQL"
    public let identifierQuote: IdentifierQuote = .backtick
    public let maxIdentifierLength = 64
    public let maxBindParameters = 65_535
    public let booleanRendering: BooleanRendering = .integer
    public let supportsNativeNullsOrdering = false

    public init() {}
}
