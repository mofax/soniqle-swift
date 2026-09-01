import Testing
import Soniqle

@Suite("Resource limits and DoS mitigation")
struct ResourceLimitTests {

    private func code(
        _ json: String,
        options: CompileOptions,
        parameters: [String: SQLValue] = [:]
    ) -> SoniqleError.Code? {
        do {
            _ = try Soniqle.postgres(options: options).compile(json: json, parameters: parameters)
            return nil
        } catch {
            return error.code
        }
    }

    /// Builds `["and", P, ["and", P, ...]]` nested `levels` deep.
    private func nestedPredicate(levels: Int) -> String {
        let leaf = #"["=", "$u.id", "$u.id"]"#
        var body = leaf
        for _ in 0..<levels {
            body = #"["and", \#(leaf), \#(body)]"#
        }
        return #"{"from": "u", "select": ["$u.id"], "where": \#(body)}"#
    }

    @Test("Predicate nesting past maxDepth is rejected")
    func depthLimit() {
        let options = CompileOptions(
            maxDepth: 8, maxNodeCount: 100_000, maxOutputParameters: 10_000,
            maxInListExpansion: 10_000, maxSQLLength: 10_000_000, maxLimitValue: 1_000_000
        )
        #expect(code(nestedPredicate(levels: 4), options: options) == nil)
        #expect(code(nestedPredicate(levels: 40), options: options) == .depthLimitExceeded)
    }

    @Test("A node flood past maxNodeCount is rejected")
    func nodeCountLimit() {
        let options = CompileOptions(
            maxDepth: 10_000, maxNodeCount: 50, maxOutputParameters: 10_000,
            maxInListExpansion: 10_000, maxSQLLength: 10_000_000, maxLimitValue: 1_000_000
        )
        let manyColumns = (0..<80).map { #""$u.c\#($0)""# }.joined(separator: ", ")
        let json = #"{"from": "u", "select": [\#(manyColumns)]}"#
        #expect(code(json, options: options) == .nodeCountLimitExceeded)
    }

    @Test("An in-list larger than maxInListExpansion is rejected")
    func inListExpansionLimit() {
        let options = CompileOptions(
            maxDepth: 48, maxNodeCount: 4_096, maxOutputParameters: 10_000,
            maxInListExpansion: 16, maxSQLLength: 1_000_000, maxLimitValue: 1_000_000
        )
        let json = #"{"from": "u", "select": ["$u.id"], "where": ["in", "$u.id", ":ids"]}"#
        let big = SQLValue.array((0..<64).map { .int(Int64($0)) })
        #expect(code(json, options: options, parameters: ["ids": big]) == .inListTooLarge)
    }

    @Test("Total bound parameters past the effective cap is rejected")
    func parameterCountLimit() {
        let options = CompileOptions(
            maxDepth: 48, maxNodeCount: 100_000, maxOutputParameters: 10,
            maxInListExpansion: 10_000, maxSQLLength: 10_000_000, maxLimitValue: 1_000_000
        )
        let json = #"{"from": "u", "select": ["$u.id"], "where": ["in", "$u.id", ":ids"]}"#
        let big = SQLValue.array((0..<50).map { .int(Int64($0)) })
        #expect(code(json, options: options, parameters: ["ids": big]) == .parameterCountLimitExceeded)
    }

    @Test("Rendered SQL past maxSQLLength is rejected")
    func outputSizeLimit() {
        let options = CompileOptions(
            maxDepth: 48, maxNodeCount: 100_000, maxOutputParameters: 10_000,
            maxInListExpansion: 10_000, maxSQLLength: 64, maxLimitValue: 1_000_000
        )
        let manyColumns = (0..<40).map { #""$u.column_number_\#($0)""# }.joined(separator: ", ")
        let json = #"{"from": "u", "select": [\#(manyColumns)]}"#
        #expect(code(json, options: options) == .outputTooLarge)
    }
}
