/// A table / column / alias name that has passed Soniqle's strict syntactic allowlist.
///
/// The only way to obtain one is ``validate(_:maxLength:)``, so once a value has this type
/// the engine may treat it as safe to quote and emit. Validation is a hand-written Unicode
/// scalar scan — **no regular expression** — which sidesteps ReDoS and locale-dependent
/// character-class surprises, and keeps the rule auditable in one place (see `ADRs/0003`).
///
/// Accepted grammar: `[A-Za-z_][A-Za-z0-9_]*`, ASCII only, length `1 ... maxLength`.
/// Everything else — dots, spaces, quotes, semicolons, dashes, `$`, `@`, any non-ASCII
/// scalar including confusable homoglyphs — is rejected. Case is preserved and never
/// folded; because every identifier is emitted quoted, `"Id"` and `"id"` are distinct, by
/// design.
public struct ValidatedIdentifier: Sendable, Hashable, CustomStringConvertible {

    /// The raw, validated name (unquoted).
    public let raw: String

    public var description: String { raw }

    private init(unchecked raw: String) {
        self.raw = raw
    }

    /// Why a candidate identifier was rejected. Carried inside ``SoniqleError/message``.
    enum Rejection: Error, Sendable, Equatable {
        case empty
        case tooLong(limit: Int)
        case leadingCharacter(Character)
        case illegalCharacter(Character)

        var reason: String {
            switch self {
            case .empty:
                "identifier is empty"
            case .tooLong(let limit):
                "identifier exceeds the maximum length of \(limit)"
            case .leadingCharacter(let character):
                "identifier must start with an ASCII letter or underscore, found \(display(character))"
            case .illegalCharacter(let character):
                "identifier may contain only ASCII letters, digits and underscore, found \(display(character))"
            }
        }

        private func display(_ character: Character) -> String {
            if character == " " { return "a space" }
            return "'\(character)'"
        }
    }

    /// Validate `candidate`. Returns the identifier on success, or the specific
    /// ``Rejection`` on failure.
    static func validate(_ candidate: String, maxLength: Int) -> Result<ValidatedIdentifier, Rejection> {
        let scalars = candidate.unicodeScalars

        guard let first = scalars.first else {
            return .failure(.empty)
        }
        guard scalars.count <= maxLength else {
            return .failure(.tooLong(limit: maxLength))
        }
        guard isLeading(first) else {
            return .failure(.leadingCharacter(Character(first)))
        }
        for scalar in scalars.dropFirst() where !isContinuation(scalar) {
            return .failure(.illegalCharacter(Character(scalar)))
        }
        return .success(ValidatedIdentifier(unchecked: candidate))
    }

    /// The wildcard `*`, used only in `select` / `count(*)` / `alias.*` positions. It is
    /// deliberately not a ``ValidatedIdentifier`` (it is never quoted), but modelled here so
    /// callers reason about column tokens in one place.
    static let wildcard = "*"

    private static func isLeading(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0x5F: true // A-Z a-z _
        default: false
        }
    }

    private static func isContinuation(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0x5F, 0x30...0x39: true // A-Z a-z _ 0-9
        default: false
        }
    }
}
