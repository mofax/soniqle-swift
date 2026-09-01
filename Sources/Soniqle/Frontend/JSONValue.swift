#if canImport(FoundationEssentials)
internal import FoundationEssentials
#else
internal import Foundation
#endif

/// A fully-decoded JSON document, with integers kept distinct from doubles.
///
/// Soniqle decodes to this intermediate rather than walking `JSONSerialization`'s `Any`
/// graph: it keeps number typing explicit (`5` is `.int(5)`, not an ambiguous `NSNumber`)
/// and it makes the frontend a pure value transformation that is trivial to test.
enum JSONValue: Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    /// Ordered object lookup. Object key order is preserved so diagnostics can report a
    /// stable path, but Soniqle's output never depends on it.
    subscript(_ key: String) -> JSONValue? {
        for pair in objectPairs ?? [] where pair.key == key { return pair.value }
        return nil
    }

    var objectPairs: [(key: String, value: JSONValue)]? {
        if case .object(let pairs) = self { return pairs }
        return nil
    }

    var arrayElements: [JSONValue]? {
        if case .array(let elements) = self { return elements }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

extension JSONValue: Decodable {
    init(from decoder: any Decoder) throws {
        // Objects and arrays first, then scalars in a most-specific-first order. `Bool`
        // must precede the integer types: JSONDecoder does not coerce 0/1 to Bool, so a
        // genuine boolean decodes here and a number falls through.
        if var unkeyed = try? decoder.unkeyedContainer() {
            var elements: [JSONValue] = []
            if let count = unkeyed.count { elements.reserveCapacity(count) }
            while !unkeyed.isAtEnd {
                elements.append(try unkeyed.decode(JSONValue.self))
            }
            self = .array(elements)
            return
        }
        if let keyed = try? decoder.container(keyedBy: DynamicKey.self) {
            var pairs: [(key: String, value: JSONValue)] = []
            for key in keyed.allKeys {
                pairs.append((key.stringValue, try keyed.decode(JSONValue.self, forKey: key)))
            }
            self = .object(pairs)
            return
        }

        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let bool = try? single.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? single.decode(Int64.self) {
            self = .int(int)
        } else if let double = try? single.decode(Double.self) {
            self = .double(double)
        } else if let string = try? single.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(
                in: single,
                debugDescription: "value is not a JSON null, bool, number, string, array or object"
            )
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
