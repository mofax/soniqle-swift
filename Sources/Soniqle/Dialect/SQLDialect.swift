/// How a dialect delimits identifiers. The engine performs the actual escaping (doubling
/// the quote character); the dialect only chooses *which* character.
public enum IdentifierQuote: Sendable, Hashable {
    /// `"name"` — SQL-standard. PostgreSQL, SQLite.
    case double
    /// `` `name` `` — MySQL / MariaDB in its default mode.
    case backtick

    var character: Character {
        switch self {
        case .double: "\""
        case .backtick: "`"
        }
    }
}

/// How a dialect spells boolean constants that Soniqle itself emits (currently only the
/// `(1 = 0)` guard for an empty `in` list, which uses integers regardless — this exists for
/// custom dialects and future constant folding).
public enum BooleanRendering: Sendable, Hashable {
    /// `TRUE` / `FALSE`.
    case keyword
    /// `1` / `0`.
    case integer
}

/// A pluggable SQL dialect. Three implementations ship with Soniqle
/// (``PostgreSQLDialect``, ``SQLiteDialect``, ``MySQLDialect``); downstream code may add
/// its own.
///
/// ### Trust boundary
/// A dialect supplies *data*, never SQL text: a quote-character choice, capability flags,
/// and a placeholder token. All escaping and statement assembly is done by the engine, so a
/// custom dialect cannot widen an injection surface as long as it returns a genuine
/// placeholder token (`?`, `$1`, `:1`, …) and a real quote character. A dialect is
/// integrator-authored code and is trusted to that extent.
public protocol SQLDialect: Sendable {

    /// A short name, used in diagnostics only.
    var name: String { get }

    /// The identifier delimiter. **No default** — this is the one choice a dialect must
    /// make explicitly, because getting it wrong is a correctness/safety issue.
    var identifierQuote: IdentifierQuote { get }

    /// Maximum identifier length the target accepts. Identifiers longer than this are
    /// rejected at compile time. Default: 64.
    var maxIdentifierLength: Int { get }

    /// Maximum number of bind parameters a single statement may carry on this target. The
    /// effective limit is `min(this, CompileOptions.maxOutputParameters)`. Default: 65_535.
    var maxBindParameters: Int { get }

    /// How Soniqle-emitted boolean constants are spelled. Default: ``BooleanRendering/integer``.
    var booleanRendering: BooleanRendering { get }

    /// `true` if the target supports `ORDER BY … NULLS FIRST|LAST` natively. When `false`
    /// and a term requests NULL ordering, the engine emits a portable `(expr IS NULL)`
    /// companion sort key instead. Default: `false`.
    var supportsNativeNullsOrdering: Bool { get }

    /// The placeholder token for the *1-based* `position`-th bind parameter. Default: `"?"`
    /// (position ignored). PostgreSQL returns `"$\(position)"`.
    func placeholder(position: Int) -> String
}

public extension SQLDialect {
    var maxIdentifierLength: Int { 64 }
    var maxBindParameters: Int { 65_535 }
    var booleanRendering: BooleanRendering { .integer }
    var supportsNativeNullsOrdering: Bool { false }
    func placeholder(position: Int) -> String { "?" }
}
