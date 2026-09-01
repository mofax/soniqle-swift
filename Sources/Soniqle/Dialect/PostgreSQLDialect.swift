/// PostgreSQL. Numbered placeholders (`$1`, `$2`, …), double-quoted identifiers, native
/// `NULLS FIRST/LAST`, and a 63-character identifier limit (`NAMEDATALEN - 1`).
public struct PostgreSQLDialect: SQLDialect {
    public let name = "PostgreSQL"
    public let identifierQuote: IdentifierQuote = .double
    public let maxIdentifierLength = 63
    public let maxBindParameters = 65_535
    public let booleanRendering: BooleanRendering = .keyword
    public let supportsNativeNullsOrdering = true

    public init() {}

    public func placeholder(position: Int) -> String { "$\(position)" }
}
