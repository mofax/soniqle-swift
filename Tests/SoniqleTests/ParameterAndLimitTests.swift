import Testing
import Soniqle

@Suite("Parameter coverage and LIMIT/OFFSET validation")
struct ParameterAndLimitTests {

    private let soniqle = Soniqle.postgres()

    private func code(_ json: String, _ parameters: [String: SQLValue]) -> SoniqleError.Code? {
        do {
            _ = try soniqle.compile(json: json, parameters: parameters)
            return nil
        } catch {
            return error.code
        }
    }

    @Test("A referenced parameter with no supplied value fails")
    func missingParameter() {
        let json = #"{"from": "u", "select": ["$u.id"], "where": ["=", "$u.id", ":wanted"]}"#
        #expect(code(json, [:]) == .missingParameter)
    }

    @Test("A supplied parameter the query never uses fails")
    func unusedParameter() {
        let json = #"{"from": "u", "select": ["$u.id"], "where": ["=", "$u.id", ":wanted"]}"#
        #expect(code(json, ["wanted": .int(1), "extra": .int(2)]) == .unusedParameter)
    }

    @Test("in with a scalar parameter fails")
    func inWantsArray() {
        let json = #"{"from": "u", "select": ["$u.id"], "where": ["in", "$u.id", ":ids"]}"#
        #expect(code(json, ["ids": .int(1)]) == .parameterTypeMismatch)
    }

    @Test("An array parameter used as a scalar fails")
    func arrayWhereScalarExpected() {
        let json = #"{"from": "u", "select": ["$u.id"], "where": ["=", "$u.id", ":id"]}"#
        #expect(code(json, ["id": .array([.int(1)])]) == .parameterTypeMismatch)
    }

    @Test("A non-integer limit parameter fails")
    func limitMustBeInteger() {
        let json = #"{"from": "u", "select": ["$u.id"], "limit": ":n"}"#
        #expect(code(json, ["n": .string("10")]) == .parameterTypeMismatch)
    }

    @Test("A negative literal limit fails at parse time")
    func negativeLiteralLimit() {
        let json = #"{"from": "u", "select": ["$u.id"], "limit": -5}"#
        #expect(code(json, [:]) == .invalidLimit)
    }

    @Test("A negative limit parameter fails at compile time")
    func negativeParameterLimit() {
        let json = #"{"from": "u", "select": ["$u.id"], "limit": ":n"}"#
        #expect(code(json, ["n": .int(-1)]) == .invalidLimit)
    }

    @Test("A limit above maxLimitValue fails")
    func oversizedLimit() {
        let options = CompileOptions.secureDefault
        let json = #"{"from": "u", "select": ["$u.id"], "limit": ":n"}"#
        #expect(code(json, ["n": .int(options.maxLimitValue + 1)]) == .invalidLimit)
    }

    @Test("A literal limit and a parameter offset compile together")
    func limitAndOffset() throws {
        let json = #"{"from": "u", "select": ["$u.id"], "limit": 25, "offset": ":skip"}"#
        let result = try soniqle.compile(json: json, parameters: ["skip": .int(50)])
        #expect(result.sql == #"SELECT "u"."id" FROM "u" LIMIT 25 OFFSET $1"#)
        #expect(result.bindings == [.int(50)])
    }
}
