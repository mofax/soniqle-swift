# ADR 0006 — Resource limits with secure defaults, tunable but not disableable

**Status:** Accepted · 2026-09-01

## Context

Injection is not the only way a hostile document does damage. A deeply nested predicate can
exhaust the stack; a select list with 10⁵ entries or an `IN` array with 10⁶ elements can
blow up memory and produce a statement the database rejects (PostgreSQL caps a message at
65 535 bind parameters) or that degrades the whole system. The compiler is often called on
input that crossed a trust boundary, so it must fail fast and cheaply on pathological
shapes.

## Decision

`CompileOptions` carries six limits, all enforced *before* rendering, while walking the
AST:

| Limit | `secureDefault` | Guards against |
|---|---|---|
| `maxDepth` | 48 | stack exhaustion via nesting |
| `maxNodeCount` | 4 096 | oversized documents |
| `maxOutputParameters` | 2 048 | bind-parameter blow-up (also clamped to `dialect.maxBindParameters`) |
| `maxInListExpansion` | 1 024 | `IN` array explosion |
| `maxSQLLength` | 1 000 000 | pathological output size |
| `maxLimitValue` | 1 000 000 | `LIMIT`/`OFFSET` abuse (ADR 0010) |

The JSON decoder (Foundation) enforces its own nesting cap, and the parser bounds its
recursion by `maxDepth` as well, so a hostile document cannot exhaust the stack *during
parsing* before `StructuralValidator` ever runs.

Callers may raise or lower any limit. There is **no sentinel that disables a check** — no
`0 means unlimited`, no `strict: false`. `CompileOptions` is limits only; it has no boolean
switches at all.

## Consequences

- A hostile document fails with a precise `SoniqleError` (`depthLimitExceeded`,
  `nodeCountLimitExceeded`, …) in time roughly linear in the truncated prefix it took to
  hit the limit.
- The defaults are generous for hand-written reporting queries and tight for machine-
  generated abuse. A caller with a legitimately large query raises the specific limit and
  owns that choice.
- Because limits cannot be turned off, "compile succeeded" always implies the output is
  within known bounds.
