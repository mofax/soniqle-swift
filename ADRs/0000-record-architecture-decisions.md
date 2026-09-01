# ADR 0000 — Record architecture decisions

**Status:** Accepted · 2026-09-01

## Context

Soniqle is a security-critical library: its whole reason to exist is that it produces SQL
that cannot be subverted by hostile input. Decisions that shape that guarantee — what the
input language can express, where escaping happens, what the resource limits are — need to
be written down with their rationale, so that a future change can be judged against the
original intent rather than re-argued from scratch or quietly reversed.

## Decision

We keep Architecture Decision Records in `ADRs/`, one file per decision, numbered
sequentially, in the format popularised by Michael Nygard:

- **Context** — the forces at play, the constraints, what we know.
- **Decision** — what we are doing, stated plainly.
- **Consequences** — what becomes easier, what becomes harder, what we are giving up.

An ADR is immutable once accepted. To change a decision we add a new ADR that supersedes
the old one, and update the old one's status to `Superseded by ADR NNNN`.

Records use `Status: Proposed | Accepted | Superseded by ADR NNNN | Deprecated`.

## Consequences

- The "why" behind the safety model lives next to the code and survives contributor churn.
- Reviewers have a checklist: a PR that widens the input surface or moves escaping should
  cite or add an ADR.
- Small overhead per significant decision. Trivial choices do not get an ADR.
