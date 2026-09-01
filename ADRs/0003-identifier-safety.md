# ADR 0003 — Identifier safety: strict allowlist, no regex, mandatory quoting

**Status:** Accepted · 2026-09-01

## Context

Table, column and alias names are the one place structural text derived from input reaches
the SQL string. Two things must both hold: the text must be a single well-formed
identifier, and it must be delimited so it cannot be read as a keyword, an operator, or the
start of a new token.

A regular expression (`^[A-Za-z_][A-Za-z0-9_]*$`) is the obvious validator and the wrong
one here: regex engines carry ReDoS risk on hostile input, `\w`/`\d` semantics can be
locale- or Unicode-mode-dependent, and the rule ends up as an opaque string rather than
reviewable code.

## Decision

- `ValidatedIdentifier` is a type whose only constructor is a hand-written Unicode-scalar
  scan. Grammar: first scalar in `A–Z a–z _`, remaining scalars in `A–Z a–z 0–9 _`, total
  length `1 ... dialect.maxIdentifierLength`. ASCII only. No regex, no `Foundation`
  character sets.
- Everything else is rejected with `SoniqleError.Code.invalidIdentifier` and a specific
  reason: dots, spaces, quotes, backticks, semicolons, dashes, `$`, `@`, and every
  non-ASCII scalar including confusable homoglyphs (Cyrillic `а`, etc.).
- Every identifier is emitted **quoted**, using the dialect's quote character, with that
  character doubled inside. Because a `ValidatedIdentifier` provably cannot contain the
  quote character, the doubling never fires — it is kept as defense in depth against a
  future validation regression.
- Case is preserved and never folded. Under quoting, `"Id"` and `"id"` are distinct
  identifiers. This is surprising to some SQL users but it is the safe direction: Soniqle
  does not silently rewrite names.
- Table references are single-part. A `schema.table` form is not accepted in v1 (the `.`
  fails identifier validation); it is a candidate for a later ADR with an explicit
  two-component type.

## Consequences

- Validation is O(n) over the scalars with no backtracking, auditable in one function.
- The rejection of non-ASCII names is a real usability limitation for databases that use
  them. Accepted for v1: the safe subset is the common subset, and widening later is
  backwards-compatible.
- Quoting everything means output is verbose but unambiguous and reserved-word-proof in
  every dialect.
