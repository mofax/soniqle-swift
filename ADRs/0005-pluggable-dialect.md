# ADR 0005 — Pluggable dialects with engine-owned escaping

**Status:** Accepted · 2026-09-01

## Context

Three dialects ship (PostgreSQL, SQLite, MySQL) and downstream users need to add their own
(Oracle, SQL Server, a proprietary engine). The risk in an extension point on a
security-critical library is that a third-party implementation becomes a way to bypass the
safety model — e.g. a `quote(_:)` method that forgets to quote.

## Decision

`SQLDialect` supplies **data, not SQL**:

- `identifierQuote: IdentifierQuote` — a two-case enum (`.double` / `.backtick`). The engine
  does the delimiting and escaping; the dialect only picks the character.
- `placeholder(position:) -> String` — the bind-parameter token (`?`, `$1`, `:1`, …). This
  is the one free-form string a dialect returns, and it only ever lands in a placeholder
  position, never adjacent to caller data.
- capability data: `maxIdentifierLength`, `maxBindParameters`, `booleanRendering`,
  `supportsNativeNullsOrdering`.

Everything with security weight — identifier validation and quoting, predicate assembly,
`IN` expansion, `LIKE` escaping, `LIMIT` range checks, the resource limits — is in the
engine and runs regardless of dialect.

Default implementations are provided for every member except `identifierQuote`, so a
minimal custom dialect is a handful of lines.

## Consequences

- The trust boundary is explicit and small: Soniqle's guarantees hold for any dialect that
  returns a genuine placeholder token and a real quote character. A dialect is
  integrator-authored code, not attacker input; we trust it that far and no further.
- A custom dialect cannot introduce an injection surface by omission, because it has no
  code path that emits an identifier or a value.
- Dialect differences that are *not* pure data — MySQL's lack of `NULLS FIRST/LAST` — are
  handled by the engine keying off a capability flag (ADR: emulation via `(expr IS NULL)`),
  not by handing rendering to the dialect.
