/// Resource and strictness limits applied during compilation.
///
/// Every field has a conservative default (``secureDefault``). Callers may tune values
/// **up or down**, but note what is *not* here: there is no switch to disable identifier
/// quoting, permit raw SQL, skip parameter-coverage checks, or turn any guard off. Insecure
/// modes are absent from the type, not merely defaulted off (see `ADRs/0006`).
///
/// Limits are enforced early — while walking the AST, before rendering — so a pathological
/// document fails fast with a precise ``SoniqleError`` instead of consuming memory/CPU.
public struct CompileOptions: Sendable, Hashable {

    /// Maximum nesting depth of the AST (predicate trees, `as`/aggregate wrapping).
    /// Exceeding it throws ``SoniqleError/Code/depthLimitExceeded``.
    public var maxDepth: Int

    /// Maximum total number of AST nodes across the whole query.
    /// Exceeding it throws ``SoniqleError/Code/nodeCountLimitExceeded``.
    public var maxNodeCount: Int

    /// Upper bound on the number of placeholders the compiled statement may bind. The
    /// effective limit is `min(maxOutputParameters, dialect.maxBindParameters)`.
    /// Exceeding it throws ``SoniqleError/Code/parameterCountLimitExceeded``.
    public var maxOutputParameters: Int

    /// Maximum number of elements an `in` array parameter may expand to.
    /// Exceeding it throws ``SoniqleError/Code/inListTooLarge``.
    public var maxInListExpansion: Int

    /// Maximum length, in Unicode scalars, of the rendered SQL string.
    /// Exceeding it throws ``SoniqleError/Code/outputTooLarge``.
    public var maxSQLLength: Int

    /// Inclusive upper bound accepted for a `limit` or `offset` value (literal or
    /// parameter). Values above this, or below zero, throw ``SoniqleError/Code/invalidLimit``.
    public var maxLimitValue: Int64

    /// The conservative default profile. Used whenever `options:` is omitted.
    public static let secureDefault = CompileOptions(
        maxDepth: 48,
        maxNodeCount: 4_096,
        maxOutputParameters: 2_048,
        maxInListExpansion: 1_024,
        maxSQLLength: 1_000_000,
        maxLimitValue: 1_000_000
    )

    public init(
        maxDepth: Int,
        maxNodeCount: Int,
        maxOutputParameters: Int,
        maxInListExpansion: Int,
        maxSQLLength: Int,
        maxLimitValue: Int64
    ) {
        precondition(maxDepth > 0, "maxDepth must be positive")
        precondition(maxNodeCount > 0, "maxNodeCount must be positive")
        precondition(maxOutputParameters >= 0, "maxOutputParameters must be non-negative")
        precondition(maxInListExpansion >= 0, "maxInListExpansion must be non-negative")
        precondition(maxSQLLength > 0, "maxSQLLength must be positive")
        precondition(maxLimitValue >= 0, "maxLimitValue must be non-negative")
        self.maxDepth = maxDepth
        self.maxNodeCount = maxNodeCount
        self.maxOutputParameters = maxOutputParameters
        self.maxInListExpansion = maxInListExpansion
        self.maxSQLLength = maxSQLLength
        self.maxLimitValue = maxLimitValue
    }
}
