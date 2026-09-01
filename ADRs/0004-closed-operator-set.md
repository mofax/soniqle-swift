# ADR 0004 — A closed operator and aggregate set

**Status:** Accepted · 2026-09-01

## Context

A query builder's expressive power and its attack surface grow together. The safe move is
to start from the smallest set that covers the target use case (reporting-style `SELECT`s
driven by a UI) and add to it deliberately.

## Decision

The operator/function vocabulary is a set of Swift `enum`s, not an open registry. v1
contains exactly:

- **Logical:** `and`, `or`, `not`. `and`/`or` are n-ary (≥ 2 operands). Precedence
  parentheses are inserted by the compiler only at an `AND`/`OR` boundary.
- **Comparison:** `=`, `<>`, `<`, `<=`, `>`, `>=`. `!=` and `==` in JSON normalise to
  `<>`/`=`.
- **Membership:** `in` / `not-in`, right side is always an array `:parameter`.
- **Range:** `between`.
- **Null tests:** `is-null` / `is-not-null`.
- **Pattern:** `like` / `not-like` (pattern bound verbatim) and `contains` / `starts-with`
  / `ends-with` (+ `not-` forms), which bind a value the engine has wildcard-escaped and
  emit `LIKE ? ESCAPE '/'`.
- **Aggregates:** `count` (incl. `count(*)` and `count(distinct …)`), `sum`, `avg`, `min`,
  `max`. Argument is `*` (count only) or a single column.

Deliberately **deferred** (safe to add later, backwards-compatibly): arithmetic operators,
`COALESCE`/`NULLIF`, `CASE`, inline value lists for `in`, `schema.table` names, subqueries,
set operations (`UNION`), window functions, `DISTINCT ON`.

The `LIKE` escape character is `/`, not `\`. Backslash is itself an escape character inside
string literals in MySQL's default mode, so `ESCAPE '\'` is fragile across dialects; `/`
has no special meaning inside a single-quoted literal in PostgreSQL, SQLite or MySQL.

## Consequences

- The full set of shapes the compiler must handle fits on one screen and is covered by
  tests exhaustively.
- `count(where:)` on the Swift side and similar conveniences are not needed — the surface
  is small enough to switch over directly.
- Adding an operator is a code change with an ADR, not a config entry a downstream user can
  flip. That is the intended friction.
