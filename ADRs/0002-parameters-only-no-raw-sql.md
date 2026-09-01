# ADR 0002 — Values enter only as bound parameters; no raw SQL anywhere

**Status:** Accepted · 2026-09-01

## Context

SQL injection is the failure this library exists to prevent. Almost every real-world
injection traces back to one of two escape hatches in a query builder: a "raw fragment"
node, or a code path that formats a *value* into SQL text (with or without hand-rolled
escaping). The brief is explicit: strict secure defaults, and insecure options should not
even be present.

## Decision

- There is **no raw-SQL node** in the AST and no API that accepts a SQL string fragment.
- There is **no literal case** in `Expression`. A constant can only appear as
  `Expression.parameter(name)`, which carries a *name*, not a value. `LIMIT`/`OFFSET` are
  the sole place an integer literal is accepted, and only after range-checking (ADR 0010).
- Every value flows: `parameters[name]` → a dialect placeholder token in the SQL string →
  the same `SQLValue`, unchanged, in `CompiledStatement.bindings`. `Date` is handed to the
  driver as `Date`; Soniqle never converts it to text.
- There is **no option** to disable this. `CompileOptions` contains limits, not switches.

## Consequences

- The SQL string is a function only of the query *structure* and the dialect. It never
  contains caller data. An attacker who fully controls both the JSON and every parameter
  value still cannot alter the statement's structure.
- `bindings` is safe to hand to any parameterised-execution API (`PDO`-style, PostgreSQL
  extended query protocol, SQLite `sqlite3_bind_*`, etc.).
- Things Soniqle cannot express — a computed column like `price * 1.2`, `COALESCE`, a
  vendor function, `CASE` — are out of scope for v1 by construction. ADR 0004 records which
  of these are deferred vs. permanently excluded.
- Users who genuinely need a raw fragment must not get it from Soniqle; they compose it in
  their own layer, where the responsibility is visible.
