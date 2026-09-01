/// The six permitted binary comparison operators. `!=` in JSON is normalised to `<>`.
public enum ComparisonOperator: String, Sendable, Hashable {
    case equal = "="
    case notEqual = "<>"
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
}

/// The shape of an auto-escaped text search. Unlike raw ``Predicate/like(_:pattern:negated:)``,
/// these bind a value that the engine wraps and escapes (`% _ \` → escaped) before emitting
/// `LIKE ? ESCAPE '\'`, so caller data can never act as a wildcard.
public enum TextMatchKind: String, Sendable, Hashable {
    case contains
    case startsWith
    case endsWith
}

/// A boolean condition. This is a closed set: `and`, `or`, `not`, the six comparisons,
/// `in`, `between`, `is null`, raw `like`, and the auto-escaped text matches. No arbitrary
/// predicate/function calls (see `ADRs/0004`).
public indirect enum Predicate: Sendable, Hashable {
    /// Logical conjunction. Must have at least two operands.
    case and([Predicate])
    /// Logical disjunction. Must have at least two operands.
    case or([Predicate])
    /// Logical negation.
    case not(Predicate)
    /// `lhs <op> rhs`.
    case compare(ComparisonOperator, Expression, Expression)
    /// `expr IN (…)`. `parameter` names a `parameters` entry that must be an
    /// ``SQLValue/array(_:)``. An empty array compiles to the constant `(1 = 0)` with no
    /// placeholders (see `ADRs/0008`).
    case inList(Expression, parameter: String, negated: Bool)
    /// `expr BETWEEN lower AND upper`.
    case between(Expression, lower: Expression, upper: Expression)
    /// `expr IS [NOT] NULL`.
    case isNull(Expression, negated: Bool)
    /// `expr [NOT] LIKE :pattern`. The pattern value is bound verbatim — the caller owns
    /// any `%` / `_` in it. Prefer ``textMatch(_:parameter:kind:negated:)`` when matching
    /// literal substrings.
    case like(Expression, pattern: String, negated: Bool)
    /// `expr [NOT] LIKE <escaped> ESCAPE '\'` where the bound value is treated as a literal
    /// substring/prefix/suffix.
    case textMatch(Expression, parameter: String, kind: TextMatchKind, negated: Bool)
}
