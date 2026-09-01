/// The one place that turns a ``ValidatedIdentifier`` into SQL text. Keeping quoting here —
/// rather than in the dialect or scattered through the compiler — means there is a single
/// function to audit for identifier-injection safety.
struct SQLWriter {

    private let quoteCharacter: Character

    init(dialect: any SQLDialect) {
        self.quoteCharacter = dialect.identifierQuote.character
    }

    /// Returns `identifier` delimited by the dialect's quote character, with any embedded
    /// quote character doubled.
    ///
    /// A ``ValidatedIdentifier`` is guaranteed to match `[A-Za-z_][A-Za-z0-9_]*`, so it can
    /// never actually contain a quote character and the doubling never fires. It is kept
    /// deliberately as defense in depth: if identifier validation ever regressed, output
    /// would still be a single well-formed quoted identifier rather than a break-out.
    func quoted(_ identifier: ValidatedIdentifier) -> String {
        var result = ""
        result.reserveCapacity(identifier.raw.count + 2)
        result.append(quoteCharacter)
        for character in identifier.raw {
            if character == quoteCharacter { result.append(character) }
            result.append(character)
        }
        result.append(quoteCharacter)
        return result
    }
}
