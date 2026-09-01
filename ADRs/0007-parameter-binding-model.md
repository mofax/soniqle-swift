# ADR 0007 — Positional, per-occurrence bindings with two-way coverage checks

**Status:** Accepted · 2026-09-01

## Context

Given `:name` references in the query and a `[String: SQLValue]` map, there are choices to
make about placeholder numbering, parameter reuse, and what counts as an error.

## Decision

- **Positional output.** `CompiledStatement.bindings` is an array in placeholder order.
  `bindings[i]` is the value for the `(i+1)`-th placeholder. This is the shape every
  parameterised-execution API wants, and it is dialect-independent (`$1..$n` for
  PostgreSQL, the i-th `?` for SQLite/MySQL).
- **Per-occurrence, not per-name.** A parameter referenced three times produces three
  placeholders and three (equal) entries in `bindings`. PostgreSQL could reuse `$1`, but
  SQLite/MySQL `?` cannot, and per-occurrence is the one model that is correct for all
  three and trivially deterministic. A dedup optimisation is a future, opt-in concern.
- **`parameterNames`** is a parallel array giving the source name of each binding. It is
  for logging and debugging; it is not needed to execute the statement.
- **Coverage is checked both ways.** Every `:name` in the query must have a supplied value
  (`missingParameter`). Every supplied value must be referenced by the query
  (`unusedParameter`) — on by default, with no flag to silence it. An unused parameter
  usually means a typo (`statuss` vs `statuses`) or a query/param mismatch, and silently
  ignoring it has hidden real bugs.

## Consequences

- Output is directly executable and its ordering is defined by the single left-to-right
  render pass (ADR 0011).
- The strict unused-parameter check occasionally annoys callers who pass a shared parameter
  bag to several queries. The documented pattern is to build the bag per query; the safety
  win is worth the friction.
- `bindings` can contain repeats; consumers must not assume distinct values.
