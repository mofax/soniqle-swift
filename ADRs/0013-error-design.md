# ADR 0013 — Error design: one struct, a non-frozen code, JSON-pointer paths

**Status:** Accepted · 2026-09-01

## Context

Typed throws (`throws(SoniqleError)`) is desirable here: the failure set is well-defined,
and the signature documenting exactly what can go wrong is worth a lot for a compiler-shaped
API. The known hazard is that committing to a concrete error type on public API makes
*adding* a failure mode a source-breaking change if downstream code switches over it
exhaustively.

## Decision

The thrown type is a **struct**, not an enum:

```swift
public struct SoniqleError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Code: Sendable, Equatable { case malformedJSON, invalidIdentifier, … }
    public let code: Code
    public let message: String
    public let path: String?   // JSON Pointer, e.g. "/where/2/0"
}
```

- `Code` is a non-frozen enum. A library's enums are already non-exhaustive to other
  modules — downstream `switch` needs `@unknown default` — so **adding a `Code` in a minor
  release is source-compatible**. That is what makes `throws(SoniqleError)` safe to promise.
- `message` is human-readable and safe to log: it contains only what the caller already put
  in the query (a name, an operator), never parameter values.
- `path` locates the offending node in the source document as a JSON Pointer, populated by
  the frontend. Semantic errors found on the typed AST (unknown alias, unused parameter)
  have `path == nil` because there is no document position to point at.
- `Equatable` so tests can assert on `code` and `path` directly.

## Consequences

- Callers get a precise `catch` with no `as?` dance, and a stable `code` to branch on.
- The error contract can grow. New `Code`s are documented as additive.
- `message` strings are not part of the API contract and may be reworded; assert on `code`
  and `path`, not `message` (the tests do).
