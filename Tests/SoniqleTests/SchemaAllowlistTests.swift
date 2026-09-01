import Testing
import Soniqle

@Suite("Optional schema allowlist")
struct SchemaAllowlistTests {

    private let schema = Schema([
        "users": ["id", "name", "active"],
        "orders": .any,
    ])

    private func code(_ json: String, _ parameters: [String: SQLValue] = [:]) -> SoniqleError.Code? {
        do {
            _ = try Soniqle.postgres(schema: schema).compile(json: json, parameters: parameters)
            return nil
        } catch {
            return error.code
        }
    }

    @Test("A table outside the allowlist is rejected")
    func tableNotAllowed() {
        #expect(code(#"{"from": ["secrets", "s"], "select": ["$s.value"]}"#) == .tableNotAllowed)
    }

    @Test("A column outside a restricted table's list is rejected")
    func columnNotAllowed() {
        #expect(code(#"{"from": ["users", "u"], "select": ["$u.password_hash"]}"#) == .columnNotAllowed)
    }

    @Test("alias.* against a restricted table is rejected")
    func wildcardNeedsAllColumns() {
        #expect(code(#"{"from": ["users", "u"], "select": ["$u.*"]}"#) == .columnNotAllowed)
    }

    @Test("alias.* against an .any table is permitted")
    func wildcardAllowedForAnyTable() throws {
        let result = try Soniqle.postgres(schema: schema)
            .compile(json: #"{"from": ["orders", "o"], "select": ["$o.*"]}"#, parameters: [:])
        #expect(result.sql == #"SELECT "o".* FROM "orders" AS "o""#)
    }

    @Test("The allowlist maps through the alias, not the raw table name")
    func aliasIndirection() {
        // `u2` aliases `orders` (allowed); `password_hash` is fine because orders is .any.
        #expect(code(#"{"from": ["orders", "u2"], "select": ["$u2.anything"]}"#) == nil)
        // `u` aliases `users` (restricted); `email` is not listed.
        #expect(code(#"{"from": ["users", "u"], "select": ["$u.email"]}"#) == .columnNotAllowed)
    }

    @Test("A fully-permitted query compiles unchanged")
    func permittedQueryCompiles() throws {
        let json = #"""
        {"from": ["users", "u"], "select": ["$u.id", "$u.name"],
         "joins": [["inner", ["orders", "o"], ["=", "$o.user_id", "$u.id"]]],
         "where": ["=", "$u.active", ":flag"]}
        """#
        let result = try Soniqle.postgres(schema: schema).compile(json: json, parameters: ["flag": .bool(true)])
        #expect(result.sql == #"""
        SELECT "u"."id", "u"."name" FROM "users" AS "u" INNER JOIN "orders" AS "o" ON "o"."user_id" = "u"."id" WHERE "u"."active" = $1
        """#)
    }

    @Test("Without a schema, unknown-but-valid identifiers still compile and are still quoted")
    func noSchemaStillValidates() throws {
        let result = try Soniqle.postgres()
            .compile(json: #"{"from": ["whatever", "w"], "select": ["$w.anything"]}"#, parameters: [:])
        #expect(result.sql == #"SELECT "w"."anything" FROM "whatever" AS "w""#)
    }
}
