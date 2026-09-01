# ADR 0009 — An optional schema allowlist, layered on top of syntactic validation

**Status:** Accepted · 2026-09-01

## Context

Syntactic identifier validation (ADR 0003) guarantees a reference is a well-formed,
safely-quoted name. It does not constrain *which* names. If the JSON document comes from a
partly-trusted source — a low-privilege service, a saved-query feature, a customer-authored
report — that source can still ask for `users.password_hash` or `FROM billing_secrets`.

## Decision

`Soniqle` takes an optional `schema: Schema?`. `Schema` maps a table *name* (as written in
`from`/`joins`, never the alias) to either `.any` or `.only(Set<String>)` of column names.

When a schema is present:

- every table in `from`/`joins` must be a key, else `tableNotAllowed`;
- every `$alias.column` is resolved alias → real table → column check, else
  `columnNotAllowed`;
- `alias.*` requires the table to be `.any`.

When no schema is given, syntactic validation and mandatory quoting still apply, and every
`$alias.col` must still resolve to a table declared in the query.

Providing a schema can only ever *reject more*. There is no schema setting that loosens
anything.

## Consequences

- Defense in depth: even a fully-compromised JSON source is confined to the tables and
  columns the integrator listed.
- It is opt-in, so it adds no insecure path — omitting it is exactly today's behaviour, not
  a weaker one.
- The allowlist is a static value the integrator maintains. Keeping it in sync with the
  real schema is their responsibility; a stale entry causes a false `columnNotAllowed`, not
  a safety hole.
- Column-level `.only` sets do not enumerate for `*`, by design — `SELECT alias.*` against a
  restricted table is refused rather than expanded.
