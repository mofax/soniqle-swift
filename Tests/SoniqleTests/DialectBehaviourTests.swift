import Testing
import Soniqle

@Suite("Dialect behaviour")
struct DialectBehaviourTests {

    @Test("NULLS ordering is native on PostgreSQL/SQLite and emulated on MySQL")
    func nullsOrdering() throws {
        let json = #"""
        {"from": ["events", "e"], "select": ["$e.id"],
         "orderBy": [["$e.ranked_at", "desc", "nulls-last"]]}
        """#

        let pg = try Soniqle.postgres().compile(json: json, parameters: [:])
        #expect(pg.sql.hasSuffix(#"ORDER BY "e"."ranked_at" DESC NULLS LAST"#))

        let sqlite = try Soniqle.sqlite().compile(json: json, parameters: [:])
        #expect(sqlite.sql.hasSuffix(#"ORDER BY "e"."ranked_at" DESC NULLS LAST"#))

        let mysql = try Soniqle.mySQL().compile(json: json, parameters: [:])
        #expect(mysql.sql.hasSuffix("ORDER BY (`e`.`ranked_at` IS NULL) ASC, `e`.`ranked_at` DESC"))
    }

    @Test("Precedence parentheses are inserted only where an OR/AND boundary needs them")
    func precedenceParentheses() throws {
        let json = #"""
        {"from": "t", "select": ["$t.id"],
         "where": ["and",
            ["=", "$t.a", ":a"],
            ["or", ["=", "$t.b", ":b"], ["=", "$t.c", ":c"]]]}
        """#
        let result = try Soniqle.postgres().compile(json: json, parameters: [
            "a": .int(1), "b": .int(2), "c": .int(3),
        ])
        #expect(result.sql == #"""
        SELECT "t"."id" FROM "t" WHERE "t"."a" = $1 AND ("t"."b" = $2 OR "t"."c" = $3)
        """#)
    }

    @Test("A downstream custom dialect plugs in through the same safe path")
    func customDialect() throws {
        struct Oracleish: SQLDialect {
            let name = "Oracleish"
            let identifierQuote: IdentifierQuote = .double
            func placeholder(position: Int) -> String { ":\(position)" }
        }

        let soniqle = Soniqle(dialect: Oracleish())
        let json = #"{"from": ["people", "p"], "select": ["$p.name"], "where": ["=", "$p.id", ":id"]}"#
        let result = try soniqle.compile(json: json, parameters: ["id": .int(7)])

        #expect(result.sql == #"SELECT "p"."name" FROM "people" AS "p" WHERE "p"."id" = :1"#)
        #expect(result.bindings == [.int(7)])
        // The custom dialect inherits the default `supportsNativeNullsOrdering == false`.
        let ordered = try soniqle.compile(
            json: #"{"from": "t", "select": ["$t.id"], "orderBy": [["$t.k", "asc", "nulls-first"]]}"#,
            parameters: [:]
        )
        #expect(ordered.sql.hasSuffix(#"ORDER BY ("t"."k" IS NULL) DESC, "t"."k" ASC"#))
    }

    @Test("count(*), DISTINCT and a bare * all render")
    func aggregatesAndWildcards() throws {
        let json = #"""
        {"distinct": true, "from": ["t", "t"], "select": [["count", "*"], ["count", ["distinct", "$t.k"]]]}
        """#
        let result = try Soniqle.postgres().compile(json: json, parameters: [:])
        #expect(result.sql == #"SELECT DISTINCT COUNT(*), COUNT(DISTINCT "t"."k") FROM "t""#)
    }
}
