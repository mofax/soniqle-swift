/// Name resolution for a single query: which table alias maps to which real table, and
/// which `SELECT`-list aliases exist. Building the scope also enforces alias uniqueness and,
/// when a ``Schema`` is configured, that every referenced table is on the allowlist.
struct QueryScope {

    /// Table alias → real table name (`"u"` → `"users"`).
    private let aliasToTable: [String: String]

    /// The set of `SELECT`-list aliases, for resolving `@name` order keys.
    let selectAliases: Set<String>

    init(query: SelectQuery, schema: Schema?) throws(SoniqleError) {
        var aliasToTable: [String: String] = [:]

        func register(_ table: TableRef, at path: String) throws(SoniqleError) {
            if aliasToTable.updateValue(table.name.raw, forKey: table.alias.raw) != nil {
                throw SoniqleError(
                    code: .duplicateAlias,
                    message: "table alias '\(table.alias)' is declared more than once",
                    path: path
                )
            }
            if let schema, !schema.allows(table: table.name.raw) {
                throw SoniqleError(
                    code: .tableNotAllowed,
                    message: "table '\(table.name)' is not in the configured schema allowlist",
                    path: path
                )
            }
        }

        try register(query.from, at: "/from")
        for (index, join) in query.joins.enumerated() {
            try register(join.table, at: "/joins/\(index)/1")
        }

        var selectAliases: Set<String> = []
        for (index, selection) in query.selections.enumerated() {
            guard let alias = selection.alias else { continue }
            if !selectAliases.insert(alias.raw).inserted {
                throw SoniqleError(
                    code: .duplicateAlias,
                    message: "select alias '\(alias)' is declared more than once",
                    path: "/select/\(index)"
                )
            }
        }

        self.aliasToTable = aliasToTable
        self.selectAliases = selectAliases
    }

    /// The real table name bound to `alias`, or `nil` if the alias was never declared.
    func tableName(forAlias alias: String) -> String? {
        aliasToTable[alias]
    }
}
