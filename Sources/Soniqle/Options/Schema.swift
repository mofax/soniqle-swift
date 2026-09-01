/// An optional allowlist of the tables and columns a query may reference.
///
/// This is defense in depth layered on top of syntactic identifier validation. When a
/// `Soniqle` is built without a schema, identifiers are still validated and quoted, and
/// every `$alias.column` must still resolve to a table declared in `from`/`joins` — the
/// schema additionally pins *which* real tables and columns are reachable, so a compromised
/// or over-permissive JSON source cannot pivot to `secrets` or `users.password_hash`.
///
/// Providing a schema never *loosens* anything; it can only reject more (see `ADRs/0009`).
public struct Schema: Sendable, Hashable {

    /// What a table entry permits.
    public enum Columns: Sendable, Hashable {
        /// Any syntactically valid column on this table is allowed, including `alias.*`.
        case any
        /// Only these exact column names are allowed. `alias.*` is rejected for such a
        /// table because the full column set is not enumerated here.
        case only(Set<String>)
    }

    /// Table name → permitted columns. The *name* is what appears in `from`/`joins`
    /// (`["users", "u"]` → `users`), never the alias.
    public let tables: [String: Columns]

    public init(tables: [String: Columns]) {
        self.tables = tables
    }

    /// Convenience builder: `Schema(["users": ["id", "name", "active"], "orders": .any])`.
    public init(_ tables: [String: Columns]) {
        self.tables = tables
    }

    /// `true` when `table` is present in the allowlist.
    func allows(table: String) -> Bool {
        tables[table] != nil
    }

    /// `true` when `column` is readable on `table` per the allowlist. `column == "*"`
    /// requires the table to be ``Columns/any``.
    func allows(column: String, on table: String) -> Bool {
        switch tables[table] {
        case .none: false
        case .some(.any): true
        case .some(.only(let names)): column != "*" && names.contains(column)
        }
    }
}

extension Schema.Columns: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: String...) {
        self = .only(Set(elements))
    }
}
