#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// A typed SQL value.
///
/// `SQLValue` is the *only* channel through which caller data reaches a compiled statement.
/// There is no API that splices a value into SQL text: every value supplied to
/// ``Soniqle/compile(json:parameters:)`` is emitted as a dialect placeholder and returned,
/// unchanged, in ``CompiledStatement/bindings``. `Date` in particular is handed to the
/// database driver as-is and is never stringified by Soniqle.
///
/// ### Input vs. output
/// - As **input** (a `parameters` entry) a value may be a scalar or ``array(_:)``. An
///   ``array(_:)`` is only meaningful as the right-hand side of an `in` predicate.
/// - As **output** (a ``CompiledStatement/bindings`` element) a value is always a scalar:
///   `in` lists are expanded to individual placeholders before binding, so ``array(_:)``
///   never appears in `bindings`.
public enum SQLValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case date(Date)
    case array([SQLValue])

    /// `true` for every case except ``array(_:)``. Bindings are required to be scalar.
    public var isScalar: Bool {
        if case .array = self { return false }
        return true
    }
}

extension SQLValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null: "null"
        case .bool(let value): value ? "true" : "false"
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .string(let value): "\"\(value)\""
        case .date(let value): "date(\(value.timeIntervalSince1970))"
        case .array(let values): "[\(values.map(\.description).joined(separator: ", "))]"
        }
    }
}
