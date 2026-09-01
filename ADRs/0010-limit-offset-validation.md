# ADR 0010 — `LIMIT` / `OFFSET` validated at compile time

**Status:** Accepted · 2026-09-01

## Context

`LIMIT` and `OFFSET` are the two places SQL wants a bare integer, not an expression, and in
some dialects not even a placeholder in every position. They are also a denial-of-service
lever: `OFFSET 100000000` forces the engine to generate and discard rows; a negative or
absurd `LIMIT` is a bug that should surface early. Because `compile` receives the parameter
*values*, their bounds can be checked before any SQL is produced.

## Decision

A `LimitValue` is either `.literal(Int64)` or `.parameter(name)`.

- A literal is validated at parse time: `0 ... options.maxLimitValue`. It is emitted inline
  as decimal digits — a checked non-negative `Int64` has no other representation, so this
  introduces no injection surface.
- A parameter is resolved at compile time. It must be `SQLValue.int` (`parameterTypeMismatch`
  otherwise — a string `"10"` is rejected), then range-checked identically, then emitted as
  a normal bound placeholder.
- Out of range in either direction → `invalidLimit`.

`maxLimitValue` defaults to 1 000 000 and is tunable like the other limits (ADR 0006), with
no way to disable the check.

## Consequences

- A UI that lets a user type a page size cannot turn it into `LIMIT -1` or
  `LIMIT 9999999999` — the compile fails with a clear code before the database sees it.
- Literal `LIMIT`/`OFFSET` render without a binding, which keeps the common `LIMIT 50` case
  free of a parameter slot; parameterised paging still works via `.parameter`.
- `maxLimitValue` is a blunt instrument — it does not know your table sizes. Callers with a
  legitimate need for larger windows raise it explicitly.
