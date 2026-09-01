/// A reference to a column, optionally qualified by a table alias.
///
/// `$u.id` parses to `ColumnRef(tableAlias: "u", column: .name("id"))`.
/// `$u.*` parses to `ColumnRef(tableAlias: "u", column: .wildcard)`.
/// A bare `*` (select-list only) parses to `ColumnRef(tableAlias: nil, column: .wildcard)`.
public struct ColumnRef: Sendable, Hashable {
    public var tableAlias: ValidatedIdentifier?
    public var column: ColumnToken

    public init(tableAlias: ValidatedIdentifier?, column: ColumnToken) {
        self.tableAlias = tableAlias
        self.column = column
    }
}

/// The column part of a ``ColumnRef``: either a validated name or the `*` wildcard.
public enum ColumnToken: Sendable, Hashable {
    case name(ValidatedIdentifier)
    case wildcard
}

/// One of Soniqle's five permitted aggregate functions. There is no general function-call
/// node — the set is closed (see `ADRs/0004`).
public enum AggregateFunction: String, Sendable, Hashable, CaseIterable {
    case count = "COUNT"
    case sum = "SUM"
    case avg = "AVG"
    case min = "MIN"
    case max = "MAX"
}

/// The argument to an aggregate: `*` (valid only for `count`) or a single column.
public enum AggregateArgument: Sendable, Hashable {
    case star
    case column(ColumnRef)
}

/// An aggregate application, e.g. `COUNT(DISTINCT "o"."id")`.
public struct Aggregate: Sendable, Hashable {
    public var function: AggregateFunction
    public var isDistinct: Bool
    public var argument: AggregateArgument

    public init(function: AggregateFunction, isDistinct: Bool, argument: AggregateArgument) {
        self.function = function
        self.isDistinct = isDistinct
        self.argument = argument
    }
}

/// A value-producing expression: a column, a bound parameter, or an aggregate.
///
/// Note what is absent: there is no literal case. A constant can only enter a statement as
/// a `:name` parameter, which is why ``parameter(_:)`` carries a *name*, not a value.
public enum Expression: Sendable, Hashable {
    /// A column reference such as `$u.id`.
    case column(ColumnRef)
    /// A reference to `parameters[name]`. The leading `:` is not part of `name`.
    case parameter(String)
    /// An aggregate application (`count`, `sum`, `avg`, `min`, `max`).
    case aggregate(Aggregate)
}
