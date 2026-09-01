# ADR 0008 — Empty `IN` list folds to a constant predicate

**Status:** Accepted · 2026-09-01

## Context

`x IN ()` is a syntax error in PostgreSQL, SQLite and MySQL. An `IN` whose array parameter
turns out to be empty at compile time is a routine situation (a filter UI with nothing
selected), not a caller mistake. The options are: reject it, or emit something valid with
the correct truth value.

## Decision

Fold it to a constant, emitting **no placeholders**:

- `x IN (:empty)`  → `(1 = 0)`   — nothing is a member of the empty set.
- `x NOT IN (:empty)` → `(1 = 1)` — everything is a non-member; this holds even when `x` is
  `NULL`, because with an empty list SQL performs no comparison and the `NOT IN` does not
  go three-valued.

`(1 = 0)` / `(1 = 1)` are used rather than `FALSE`/`TRUE` because SQLite has no boolean
literal keyword; an integer comparison is universally valid and equally constant-foldable
by the planner.

## Consequences

- A caller can pass `statuses: .array([])` and get a valid statement that returns no rows
  (or all rows, for `NOT IN`), instead of a compile error they have to special-case.
- `bindings` length depends on the runtime contents of array parameters. Callers already
  cannot assume a fixed `bindings` count when using `IN` (it is `len(array)`); the empty
  case is the `len == 0` end of that.
- The folded constant is Soniqle-generated text, not caller data — it carries no injection
  weight.
