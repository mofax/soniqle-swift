# Architecture Decision Records

Chronological log of the decisions that shape Soniqle, especially its security model.
Format and process: [ADR 0000](./0000-record-architecture-decisions.md).

| # | Decision |
|---|---|
| [0000](./0000-record-architecture-decisions.md) | Record architecture decisions |
| [0001](./0001-json-frontend-typed-ast-core.md) | A JSON frontend over a typed AST core |
| [0002](./0002-parameters-only-no-raw-sql.md) | Values enter only as bound parameters; no raw SQL |
| [0003](./0003-identifier-safety.md) | Identifier safety: strict allowlist, no regex, mandatory quoting |
| [0004](./0004-closed-operator-set.md) | A closed operator and aggregate set |
| [0005](./0005-pluggable-dialect.md) | Pluggable dialects with engine-owned escaping |
| [0006](./0006-resource-limits.md) | Resource limits: secure defaults, tunable, not disableable |
| [0007](./0007-parameter-binding-model.md) | Positional, per-occurrence bindings with two-way coverage |
| [0008](./0008-empty-in-list.md) | Empty `IN` list folds to a constant predicate |
| [0009](./0009-optional-schema-allowlist.md) | Optional schema allowlist, layered on syntactic validation |
| [0010](./0010-limit-offset-validation.md) | `LIMIT` / `OFFSET` validated at compile time |
| [0011](./0011-deterministic-compilation.md) | Compilation is deterministic |
| [0012](./0012-swift-6.3-baseline.md) | Swift 6.3 baseline and toolchain posture |
| [0013](./0013-error-design.md) | Error design: one struct, a non-frozen code, JSON-pointer paths |
