# ADR 0011 — Compilation is deterministic

**Status:** Accepted · 2026-09-01

## Context

If the same input can produce two different SQL strings across runs, three things break:
prepared-statement and plan caches keyed on the SQL text stop hitting; golden tests become
flaky; and reasoning about "what did we send to the database" gets harder during incident
response.

## Decision

`(json bytes, parameters, dialect, schema, options)` → `CompiledStatement` is a pure
function with byte-identical output across runs, processes and machines.

Mechanically:

- One left-to-right pass renders clauses in fixed SQL order (`SELECT`, `FROM`, `JOIN`s,
  `WHERE`, `GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT`, `OFFSET`).
- Placeholder positions are assigned by a counter incremented in that traversal order, so
  placeholder *n* is always the *n*-th value appended to `bindings`.
- The `parameters` dictionary is only ever *looked up by key*. It is never iterated to
  drive output. The one place its keys are enumerated — the unused-parameter check — sorts
  them before building the error message.
- No wall-clock, no RNG, no environment, no `Set`/`Dictionary` iteration order on any output
  path.

A test compiles the reference query 50× plus once more with a deliberately reordered
parameter dictionary and asserts all results are equal.

## Consequences

- SQL text is a stable cache key.
- Golden tests can assert exact strings (they do).
- Any future feature that would introduce nondeterminism (parallel rendering, hash-ordered
  emission) is a violation of this ADR and needs a superseding decision.
