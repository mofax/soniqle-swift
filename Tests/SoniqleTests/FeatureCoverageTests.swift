import Testing
import Soniqle

@Suite("Predicate and clause coverage")
struct FeatureCoverageTests {

    private let soniqle = Soniqle.postgres()

    @Test("Empty IN folds to a constant with no bindings")
    func emptyInList() throws {
        let json = #"{"from": "t", "select": ["$t.id"], "where": ["in", "$t.id", ":ids"]}"#
        let inResult = try soniqle.compile(json: json, parameters: ["ids": .array([])])
        #expect(inResult.sql == #"SELECT "t"."id" FROM "t" WHERE (1 = 0)"#)
        #expect(inResult.bindings.isEmpty)

        let notInJSON = #"{"from": "t", "select": ["$t.id"], "where": ["not-in", "$t.id", ":ids"]}"#
        let notInResult = try soniqle.compile(json: notInJSON, parameters: ["ids": .array([])])
        #expect(notInResult.sql == #"SELECT "t"."id" FROM "t" WHERE (1 = 1)"#)
        #expect(notInResult.bindings.isEmpty)
    }

    @Test("between, is-null and not render as expected")
    func rangeAndNullAndNot() throws {
        let json = #"""
        {"from": "t", "select": ["$t.id"],
         "where": ["and",
            ["between", "$t.score", ":lo", ":hi"],
            ["is-not-null", "$t.email"],
            ["not", ["=", "$t.flag", ":f"]]]}
        """#
        let result = try soniqle.compile(json: json, parameters: [
            "lo": .int(0), "hi": .int(100), "f": .bool(false),
        ])
        #expect(result.sql == #"""
        SELECT "t"."id" FROM "t" WHERE "t"."score" BETWEEN $1 AND $2 AND "t"."email" IS NOT NULL AND NOT ("t"."flag" = $3)
        """#)
    }

    @Test("Raw like binds the pattern verbatim")
    func rawLike() throws {
        let json = #"{"from": "t", "select": ["$t.id"], "where": ["like", "$t.name", ":p"]}"#
        let result = try soniqle.compile(json: json, parameters: ["p": .string("a%_z")])
        #expect(result.sql == #"SELECT "t"."id" FROM "t" WHERE "t"."name" LIKE $1"#)
        #expect(result.bindings == [.string("a%_z")])
    }

    @Test("contains escapes wildcards in the bound value and adds ESCAPE")
    func autoEscapedContains() throws {
        let json = #"{"from": "t", "select": ["$t.id"], "where": ["contains", "$t.name", ":q"]}"#
        let result = try soniqle.compile(json: json, parameters: ["q": .string("50% off_now/then")])
        #expect(result.sql == #"SELECT "t"."id" FROM "t" WHERE "t"."name" LIKE $1 ESCAPE '/'"#)
        #expect(result.bindings == [.string("%50/% off/_now//then%")])
    }

    @Test("starts-with and ends-with anchor on one side")
    func anchoredTextMatch() throws {
        let starts = try soniqle.compile(
            json: #"{"from": "t", "select": ["$t.id"], "where": ["starts-with", "$t.sku", ":p"]}"#,
            parameters: ["p": .string("AB-")]
        )
        #expect(starts.bindings == [.string("AB-%")])

        let ends = try soniqle.compile(
            json: #"{"from": "t", "select": ["$t.id"], "where": ["ends-with", "$t.sku", ":p"]}"#,
            parameters: ["p": .string("-Z")]
        )
        #expect(ends.bindings == [.string("%-Z")])
    }

    @Test("cross join has no ON clause")
    func crossJoin() throws {
        let json = #"{"from": ["a", "a"], "select": ["$a.id"], "joins": [["cross", ["b", "b"]]]}"#
        let result = try soniqle.compile(json: json, parameters: [:])
        #expect(result.sql == #"SELECT "a"."id" FROM "a" CROSS JOIN "b""#)
    }

    @Test("A single-name table reference omits the AS alias")
    func bareTableName() throws {
        let result = try soniqle.compile(json: #"{"from": "widgets", "select": ["$widgets.id"]}"#, parameters: [:])
        #expect(result.sql == #"SELECT "widgets"."id" FROM "widgets""#)
    }

    @Test("Unknown table alias in a column reference fails")
    func unknownAlias() {
        do {
            _ = try soniqle.compile(json: #"{"from": ["a", "a"], "select": ["$z.id"]}"#, parameters: [:])
            Issue.record("expected failure")
        } catch {
            #expect(error.code == .unknownTableAlias)
        }
    }

    @Test("@alias in orderBy must match a declared select alias")
    func unknownSelectAlias() {
        do {
            _ = try soniqle.compile(
                json: #"{"from": "t", "select": ["$t.id"], "orderBy": ["@missing"]}"#,
                parameters: [:]
            )
            Issue.record("expected failure")
        } catch {
            #expect(error.code == .unknownSelectAlias)
        }
    }

    @Test("@alias is not accepted outside orderBy")
    func aliasReferenceScoping() {
        do {
            _ = try soniqle.compile(
                json: #"{"from": "t", "select": [["as", "$t.x", "y"]], "where": ["=", "@y", ":v"]}"#,
                parameters: ["v": .int(1)]
            )
            Issue.record("expected failure")
        } catch {
            #expect(error.code == .unexpectedShape)
        }
    }

    @Test("Duplicate select alias fails")
    func duplicateSelectAlias() {
        do {
            _ = try soniqle.compile(
                json: #"{"from": "t", "select": [["as", "$t.a", "x"], ["as", "$t.b", "x"]]}"#,
                parameters: [:]
            )
            Issue.record("expected failure")
        } catch {
            #expect(error.code == .duplicateAlias)
        }
    }

    @Test("Unknown top-level keys are rejected")
    func strictRootKeys() {
        do {
            _ = try soniqle.compile(json: #"{"from": "t", "select": ["$t.id"], "sneaky": 1}"#, parameters: [:])
            Issue.record("expected failure")
        } catch {
            #expect(error.code == .unexpectedShape)
            #expect(error.path == "/sneaky")
        }
    }

    @Test("Malformed JSON is reported as such")
    func malformedJSON() {
        do {
            _ = try soniqle.compile(json: "{ not json", parameters: [:])
            Issue.record("expected failure")
        } catch {
            #expect(error.code == .malformedJSON)
        }
    }

    @Test("Inline value lists in IN are explicitly unsupported, not silently allowed")
    func inlineListRejected() {
        do {
            _ = try soniqle.compile(
                json: #"{"from": "t", "select": ["$t.id"], "where": ["in", "$t.id", [1, 2, 3]]}"#,
                parameters: [:]
            )
            Issue.record("expected failure")
        } catch {
            #expect(error.code == .unsupportedFeature)
        }
    }

    @Test("Error diagnostics carry a JSON pointer path")
    func errorPath() {
        do {
            _ = try soniqle.compile(
                json: #"{"from": "t", "select": ["$t.id"], "where": ["and", ["=", "$t.a", ":a"], ["bogus", "$t.b"]]}"#,
                parameters: ["a": .int(1)]
            )
            Issue.record("expected failure")
        } catch {
            #expect(error.code == .unknownOperator)
            #expect(error.path == "/where/2/0")
        }
    }
}
