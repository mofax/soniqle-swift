import Testing
import Soniqle

@Suite("Injection resistance")
struct InjectionResistanceTests {

    private let soniqle = Soniqle.postgres()

    private func failureCode(_ json: String) -> SoniqleError.Code? {
        do {
            _ = try soniqle.compile(json: json, parameters: [:])
            return nil
        } catch {
            return error.code
        }
    }

    private func expectFails(
        _ json: String,
        code: SoniqleError.Code,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(failureCode(json) == code, sourceLocation: sourceLocation)
    }

    @Test("A quote character in an identifier is rejected, never emitted")
    func quoteInIdentifier() {
        expectFails(#"{"from": "users", "select": ["$u.a\"; DROP TABLE users; --"]}"#, code: .invalidIdentifier)
    }

    @Test("Semicolons, parens, spaces and dashes in identifiers are rejected")
    func punctuationInIdentifier() {
        expectFails(#"{"from": "u; DROP TABLE x", "select": ["$u.id"]}"#, code: .invalidIdentifier)
        expectFails(#"{"from": "users", "select": ["$u.id) UNION SELECT"]}"#, code: .invalidIdentifier)
        expectFails(#"{"from": "users", "select": ["$u.a b"]}"#, code: .invalidIdentifier)
        expectFails(#"{"from": "users", "select": ["$u.a-b"]}"#, code: .invalidIdentifier)
    }

    @Test("A backtick is rejected even though PostgreSQL would not treat it as a quote")
    func backtickInIdentifier() {
        expectFails("{\"from\": \"users\", \"select\": [\"$u.a`b\"]}", code: .invalidIdentifier)
    }

    @Test("Non-ASCII identifiers, including confusable homoglyphs, are rejected")
    func nonASCIIIdentifier() {
        // U+0430 CYRILLIC SMALL LETTER A looks like 'a' but is not ASCII.
        expectFails("{\"from\": \"users\", \"select\": [\"$u.\u{0430}dmin\"]}", code: .invalidIdentifier)
        expectFails(#"{"from": "users", "select": ["$u.café"]}"#, code: .invalidIdentifier)
    }

    @Test("An identifier longer than the dialect limit is rejected")
    func overlongIdentifier() {
        let long = String(repeating: "a", count: 200)
        expectFails(#"{"from": "users", "select": ["$u.\#(long)"]}"#, code: .invalidIdentifier)
    }

    @Test("A parameter marker cannot be used where an identifier is expected")
    func parameterAsIdentifier() {
        expectFails(#"{"from": ":evil", "select": ["$u.id"]}"#, code: .invalidIdentifier)
        expectFails(#"{"from": "users", "select": ["$:x.id"]}"#, code: .invalidIdentifier)
    }

    @Test("A bare string literal cannot appear where a value is expected")
    func bareLiteralRejected() {
        expectFails(#"{"from": "users", "select": ["$u.id"], "where": ["=", "$u.name", "administrator"]}"#,
                    code: .unexpectedShape)
    }

    @Test("There is no operator that injects raw SQL")
    func noRawOperator() {
        expectFails(#"{"from": "users", "select": ["$u.id"], "where": ["raw", "1=1"]}"#, code: .unknownOperator)
        expectFails(#"{"from": "users", "select": [["sql", "now()"]]}"#, code: .unknownOperator)
    }

    @Test("String parameter values are bound, never interpolated, even when they contain SQL")
    func hostileValueIsBound() throws {
        let json = #"{"from": ["users", "u"], "select": ["$u.id"], "where": ["=", "$u.name", ":name"]}"#
        let result = try soniqle.compile(json: json, parameters: [
            "name": .string("x'; DROP TABLE users; --"),
        ])
        #expect(result.sql == #"SELECT "u"."id" FROM "users" AS "u" WHERE "u"."name" = $1"#)
        #expect(result.bindings == [.string("x'; DROP TABLE users; --")])
    }
}
