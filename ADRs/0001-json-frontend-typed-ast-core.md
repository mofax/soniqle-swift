# ADR 0001 — A JSON frontend over a typed AST core

**Status:** Accepted · 2026-09-01

## Context

The task specifies a JSON S-expression document as the input. JSON is a good *transport*:
it crosses process and language boundaries, it is easy to generate from a UI, and it is
inert data. It is a poor thing to compile *directly*: a recursive walk over
`[String: Any]` / `[Any]` interleaves three unrelated concerns — JSON shape validation,
semantic validation, and SQL rendering — in one pass that is hard to test and easy to get
subtly wrong.

## Decision

Two layers with a hard boundary between them:

1. **Frontend** (`Frontend/`): decode the bytes into a `JSONValue` (a closed enum, integers
   kept distinct from doubles), then transform that into a typed AST. This layer owns *all*
   JSON-shape concerns and produces precise `SoniqleError`s carrying a JSON-Pointer path.
2. **Core** (`AST/` + `Engine/`): a typed `SelectQuery` value and a compiler from
   `(SelectQuery, parameters)` to `CompiledStatement`. This layer never sees JSON.

`Soniqle` exposes both doors: `compile(json:parameters:)` and `compile(_:parameters:)`
taking a `SelectQuery` directly. Both run the identical semantic checks, resource limits
and rendering.

## Consequences

- Each layer is unit-testable in isolation; the golden tests pin the core, the frontend
  tests pin the parser, and they do not have to be exercised through each other.
- A second frontend (a Swift result-builder DSL, a different wire format) is additive: it
  just needs to produce a `SelectQuery`.
- The typed AST is a deliberate bottleneck. If a construct cannot be represented as a
  `SelectQuery`, no frontend can smuggle it through. This is what makes "no raw SQL" a
  structural property rather than a lint rule (see ADR 0002).
- Cost: the AST types are public API surface and must be evolved compatibly.
