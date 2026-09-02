#if canImport(FoundationEssentials)
internal import FoundationEssentials
#else
internal import Foundation
#endif

///
/// ```swift
/// let soniqle = Soniqle.postgres()
/// let result = try soniqle.compile(
///     json: json,
///     parameters: [
///         "active": .bool(true),
///         "startDate": .date(.now),
///         "statuses": .array([.string("paid"), .string("shipped")]),
///         "minimumOrderCount": .int(5),
///         "limit": .int(100),
///     ]
/// )
/// print(result.sql)       // SELECT "u"."id", … WHERE "u"."active" = $1 … LIMIT $6
/// print(result.bindings)  // [true, date(…), "paid", "shipped", 5, 100]
/// ```
public struct Soniqle: Sendable {

    /// The dialect all output is rendered for. Bound at construction, never guessed.
    public let dialect: any SQLDialect

    /// An optional table/column allowlist enforced on top of syntactic validation.
    public let schema: Schema?

    /// Resource and strictness limits. Defaults to ``CompileOptions/secureDefault``.
    public let options: CompileOptions

    public init(
        dialect: any SQLDialect,
        schema: Schema? = nil,
        options: CompileOptions = .secureDefault
    ) {
        self.dialect = dialect
        self.schema = schema
        self.options = options
    }

    /// A compiler targeting PostgreSQL (`$1` placeholders, `"`-quoted identifiers).
    public static func postgres(
        schema: Schema? = nil,
        options: CompileOptions = .secureDefault
    ) -> Soniqle {
        Soniqle(dialect: PostgreSQLDialect(), schema: schema, options: options)
    }

    /// A compiler targeting SQLite (`?` placeholders, `"`-quoted identifiers).
    public static func sqlite(
        schema: Schema? = nil,
        options: CompileOptions = .secureDefault
    ) -> Soniqle {
        Soniqle(dialect: SQLiteDialect(), schema: schema, options: options)
    }

    /// A compiler targeting MySQL / MariaDB (`?` placeholders, `` ` ``-quoted identifiers,
    /// emulated `NULLS FIRST/LAST`).
    public static func mySQL(
        schema: Schema? = nil,
        options: CompileOptions = .secureDefault
    ) -> Soniqle {
        Soniqle(dialect: MySQLDialect(), schema: schema, options: options)
    }

    // MARK: Compilation

    /// Compile a JSON query document.
    ///
    /// - Parameters:
    ///   - json: The S-expression query document (see the package README for the grammar).
    ///   - parameters: A value for every `:name` the document references. Supplying a name
    ///     the query does not use is an error (``SoniqleError/Code/unusedParameter``).
    /// - Returns: Parameterised SQL and positional bindings.
    /// - Throws: ``SoniqleError`` describing the first problem found.
    public func compile(
        json: String,
        parameters: [String: SQLValue]
    ) throws(SoniqleError) -> CompiledStatement {
        try compile(jsonData: Data(json.utf8), parameters: parameters)
    }

    /// Compile a JSON query document supplied as raw UTF-8 bytes.
    public func compile(
        json: some Sequence<UInt8>,
        parameters: [String: SQLValue]
    ) throws(SoniqleError) -> CompiledStatement {
        try compile(jsonData: Data(json), parameters: parameters)
    }

    /// Shared decode + compile path. The input is materialised into `Data` exactly once
    /// (the form `JSONDecoder` requires); no intermediate `[UInt8]` copy.
    private func compile(
        jsonData: Data,
        parameters: [String: SQLValue]
    ) throws(SoniqleError) -> CompiledStatement {
        let query = try JSONParser.parse(
            jsonData: jsonData,
            maxIdentifierLength: dialect.maxIdentifierLength,
            maxDepth: options.maxDepth
        )
        return try compile(query, parameters: parameters)
    }

    /// Compile a query built directly as a typed ``SelectQuery``, bypassing the JSON
    /// frontend. The same semantic checks, resource limits and safety guarantees apply.
    public func compile(
        _ query: SelectQuery,
        parameters: [String: SQLValue]
    ) throws(SoniqleError) -> CompiledStatement {
        let compiler = try Compiler(
            query: query,
            dialect: dialect,
            schema: schema,
            options: options,
            parameters: parameters
        )
        return try compiler.run()
    }
}
