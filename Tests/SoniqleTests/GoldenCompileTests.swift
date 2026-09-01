import Testing
import Soniqle

@Suite("Golden compilation of the task.md example")
struct GoldenCompileTests {

    @Test("PostgreSQL output matches the documented golden string")
    func postgres() throws {
        let result = try Soniqle.postgres().compile(json: taskExampleJSON, parameters: taskExampleParameters())

        #expect(result.sql == """
        SELECT "u"."id", "u"."name" AS "customer_name", COUNT("o"."id") AS "order_count" \
        FROM "users" AS "u" \
        LEFT JOIN "orders" AS "o" ON "o"."user_id" = "u"."id" \
        WHERE "u"."active" = $1 AND "o"."created_at" >= $2 AND "o"."status" IN ($3, $4) \
        GROUP BY "u"."id", "u"."name" \
        HAVING COUNT("o"."id") > $5 \
        ORDER BY "order_count" DESC \
        LIMIT $6
        """)

        #expect(result.bindings == [
            .bool(true), .date(fixedDate), .string("paid"), .string("shipped"), .int(5), .int(100),
        ])
        #expect(result.parameterNames == [
            "active", "startDate", "statuses", "statuses", "minimumOrderCount", "limit",
        ])
    }

    @Test("SQLite uses ? placeholders and double-quoted identifiers")
    func sqlite() throws {
        let result = try Soniqle.sqlite().compile(json: taskExampleJSON, parameters: taskExampleParameters())

        #expect(result.sql == """
        SELECT "u"."id", "u"."name" AS "customer_name", COUNT("o"."id") AS "order_count" \
        FROM "users" AS "u" \
        LEFT JOIN "orders" AS "o" ON "o"."user_id" = "u"."id" \
        WHERE "u"."active" = ? AND "o"."created_at" >= ? AND "o"."status" IN (?, ?) \
        GROUP BY "u"."id", "u"."name" \
        HAVING COUNT("o"."id") > ? \
        ORDER BY "order_count" DESC \
        LIMIT ?
        """)
        #expect(result.bindings.count == 6)
    }

    @Test("MySQL uses ? placeholders and backtick identifiers")
    func mysql() throws {
        let result = try Soniqle.mySQL().compile(json: taskExampleJSON, parameters: taskExampleParameters())

        #expect(result.sql == """
        SELECT `u`.`id`, `u`.`name` AS `customer_name`, COUNT(`o`.`id`) AS `order_count` \
        FROM `users` AS `u` \
        LEFT JOIN `orders` AS `o` ON `o`.`user_id` = `u`.`id` \
        WHERE `u`.`active` = ? AND `o`.`created_at` >= ? AND `o`.`status` IN (?, ?) \
        GROUP BY `u`.`id`, `u`.`name` \
        HAVING COUNT(`o`.`id`) > ? \
        ORDER BY `order_count` DESC \
        LIMIT ?
        """)
    }

    @Test("Compilation is deterministic across repeated runs and parameter orderings")
    func deterministic() throws {
        let soniqle = Soniqle.postgres()
        let baseline = try soniqle.compile(json: taskExampleJSON, parameters: taskExampleParameters())

        for _ in 0..<50 {
            let again = try soniqle.compile(json: taskExampleJSON, parameters: taskExampleParameters())
            #expect(again == baseline)
        }

        // A different dictionary literal ordering must not change the output.
        let reordered: [String: SQLValue] = [
            "limit": .int(100),
            "minimumOrderCount": .int(5),
            "statuses": .array([.string("paid"), .string("shipped")]),
            "startDate": .date(fixedDate),
            "active": .bool(true),
        ]
        #expect(try soniqle.compile(json: taskExampleJSON, parameters: reordered) == baseline)
    }
}
