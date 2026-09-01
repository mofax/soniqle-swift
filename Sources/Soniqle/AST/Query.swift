/// A table with the alias it is bound to for the duration of the query. When the source
/// gives only a name, ``alias`` equals ``name``.
public struct TableRef: Sendable, Hashable {
    public var name: ValidatedIdentifier
    public var alias: ValidatedIdentifier

    public init(name: ValidatedIdentifier, alias: ValidatedIdentifier) {
        self.name = name
        self.alias = alias
    }
}

/// The permitted join flavours. `cross` is the only one without an `ON` predicate.
public enum JoinKind: String, Sendable, Hashable {
    case inner = "INNER JOIN"
    case left = "LEFT JOIN"
    case right = "RIGHT JOIN"
    case full = "FULL JOIN"
    case cross = "CROSS JOIN"
}

/// One join clause.
public struct Join: Sendable, Hashable {
    public var kind: JoinKind
    public var table: TableRef
    /// Required for every kind except ``JoinKind/cross``, where it must be `nil`.
    public var on: Predicate?

    public init(kind: JoinKind, table: TableRef, on: Predicate?) {
        self.kind = kind
        self.table = table
        self.on = on
    }
}

/// One entry in the `SELECT` list: an expression and an optional output alias.
public struct Selection: Sendable, Hashable {
    public var expression: Expression
    public var alias: ValidatedIdentifier?

    public init(expression: Expression, alias: ValidatedIdentifier?) {
        self.expression = expression
        self.alias = alias
    }
}

/// The sort key of an ``OrderTerm``.
public enum OrderKey: Sendable, Hashable {
    /// `@name` — a reference to a `SELECT`-list alias. Permitted only in `orderBy` for
    /// portability across the built-in dialects (see `ADRs/0004`).
    case selectAlias(ValidatedIdentifier)
    /// `$alias.column` — an ordinary column reference.
    case column(ColumnRef)
}

public enum Direction: String, Sendable, Hashable {
    case ascending = "ASC"
    case descending = "DESC"
}

public enum NullsOrder: String, Sendable, Hashable {
    case first = "FIRST"
    case last = "LAST"
}

/// One `ORDER BY` term.
public struct OrderTerm: Sendable, Hashable {
    public var key: OrderKey
    public var direction: Direction
    /// `nil` leaves NULL ordering to the database default. When set, dialects without
    /// native `NULLS FIRST/LAST` get a portable `(expr IS NULL)` emulation term.
    public var nulls: NullsOrder?

    public init(key: OrderKey, direction: Direction, nulls: NullsOrder?) {
        self.key = key
        self.direction = direction
        self.nulls = nulls
    }
}

/// A `LIMIT` / `OFFSET` value: an inline non-negative integer, or a parameter reference
/// that must resolve to a non-negative ``SQLValue/int(_:)``.
public enum LimitValue: Sendable, Hashable {
    case literal(Int64)
    case parameter(String)
}

/// The typed model of a `SELECT` statement — Soniqle's compilation core. The JSON frontend
/// produces one of these; ``Soniqle/compile(_:parameters:)`` also accepts one directly.
///
/// The type cannot represent a raw SQL fragment, an inline literal value, a set operation,
/// a subquery, or a window function. That is the point: the surface is small enough to
/// audit in full.
public struct SelectQuery: Sendable, Hashable {
    public var isDistinct: Bool
    public var selections: [Selection]
    public var from: TableRef
    public var joins: [Join]
    public var wherePredicate: Predicate?
    public var groupBy: [ColumnRef]
    public var having: Predicate?
    public var orderBy: [OrderTerm]
    public var limit: LimitValue?
    public var offset: LimitValue?

    public init(
        isDistinct: Bool = false,
        selections: [Selection],
        from: TableRef,
        joins: [Join] = [],
        wherePredicate: Predicate? = nil,
        groupBy: [ColumnRef] = [],
        having: Predicate? = nil,
        orderBy: [OrderTerm] = [],
        limit: LimitValue? = nil,
        offset: LimitValue? = nil
    ) {
        self.isDistinct = isDistinct
        self.selections = selections
        self.from = from
        self.joins = joins
        self.wherePredicate = wherePredicate
        self.groupBy = groupBy
        self.having = having
        self.orderBy = orderBy
        self.limit = limit
        self.offset = offset
    }
}
