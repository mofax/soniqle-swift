# Soniqle

Soniqle takes a JSON S-expression describing a query, plus a typed parameter map, and
returns parameterised SQL with ordered bindings.

```swift
let soniqle = Soniqle.postgres()

let result = try soniqle.compile(
    json: json,
    parameters: [
        "active": .bool(true),
        "startDate": .date(.now),
        "statuses": .array([.string("paid"), .string("shipped")]),
        "minimumOrderCount": .int(5),
        "limit": .int(100),
    ]
)

print(result.sql)
// SELECT "u"."id", "u"."name" AS "customer_name", COUNT("o"."id") AS "order_count"
// FROM "users" AS "u"
// LEFT JOIN "orders" AS "o" ON "o"."user_id" = "u"."id"
// WHERE "u"."active" = $1 AND "o"."created_at" >= $2 AND "o"."status" IN ($3, $4)
// GROUP BY "u"."id", "u"."name"
// HAVING COUNT("o"."id") > $5
// ORDER BY "order_count" DESC
// LIMIT $6                                         (rendered as a single line)

print(result.bindings)        // [true, 2026-…, "paid", "shipped", 5, 100]
print(result.parameterNames)  // ["active", "startDate", "statuses", "statuses", "minimumOrderCount", "limit"]
```

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://example.com/soniqle-swift.git", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "Soniqle", package: "soniqle-swift")]),
]
```

Requires a Swift 6.3 toolchain. Runs on Apple platforms, Linux and the Swift Android SDK;
the only dependency is `Foundation` / `FoundationEssentials` (for `Date` and JSON).

## Security model

| Concern | How Soniqle handles it |
|---|---|
| Value injection | Values enter only as `:name` parameters → emitted as placeholders, returned in `bindings`. No AST node carries a literal into SQL. `Date` is never stringified. |
| Identifier injection | Names must match `[A-Za-z_][A-Za-z0-9_]*` (ASCII, length-bounded) via a hand-written scalar scan — no regex. Every identifier is emitted quoted. |
| Operator injection | Closed `enum` set: logical, comparison, `in`, `between`, null tests, `like` + auto-escaped `contains`/`starts-with`/`ends-with`, and five aggregates. No arbitrary calls. |
| Unknown tables/columns | Every `$alias.col` must resolve to a declared table. An optional `Schema` allowlist pins which real tables and columns are reachable. |
| Parameter drift | Every `:name` must be supplied; every supplied name must be used. Both are errors. |
| Empty `IN ()` | Folds to `(1 = 0)` / `(1 = 1)` with no placeholders. |
| `LIMIT` / `OFFSET` abuse | Must be a non-negative integer (literal or `:int` parameter), bounded by `maxLimitValue`, checked at compile time. |
| Resource exhaustion | `CompileOptions` bounds depth, node count, bound-parameter count, `IN` expansion and output size. Secure defaults; tunable; not disableable. |
| Concurrency | `Soniqle` is an immutable `Sendable` value; `compile` is a pure `nonisolated` function; output is deterministic. |

The reasoning behind each of these is in [`ADRs/`](./ADRs).

## JSON grammar

A query is a JSON object. Unknown keys are rejected.

| Key | Required | Value |
|---|---|---|
| `from` | yes | `"table"` or `["table", "alias"]` |
| `select` | yes | non-empty array of select items |
| `joins` | no | array of `[kind, table, on]` (`kind` ∈ `inner left right full`) or `["cross", table]` |
| `where` | no | a predicate |
| `groupBy` | no | array of `"$alias.column"` |
| `having` | no | a predicate |
| `orderBy` | no | array of order terms |
| `limit` / `offset` | no | non-negative integer, or `":name"` bound to an `.int` |
| `distinct` | no | `true` → `SELECT DISTINCT` |

**Tokens**

- `"$alias.column"` — a column reference. `"$alias.*"` and a bare `"*"` (select list only)
  are allowed.
- `":name"` — a parameter reference. Supply a value for it in `parameters`.
- `"@name"` — a reference to a `select` alias. Valid **only** in `orderBy`.

**Select items**

- `"$u.id"` — a column.
- `["as", <expression>, "alias"]` — an aliased expression.
- `["count", "*"]`, `["count", "$o.id"]`, `["count", ["distinct", "$o.id"]]`, `["sum", "$o.total"]`,
  `["avg" | "min" | "max", "$o.x"]` — aggregates. May be wrapped in `["as", …, "alias"]`.

**Predicates**

```
["and", P, P, …]                 ["or", P, P, …]            ["not", P]
["=", E, E]   ["!=" | "<>", E, E]   ["<", E, E]   ["<=", E, E]   [">", E, E]   [">=", E, E]
["in", E, ":arrayParam"]          ["not-in", E, ":arrayParam"]
["between", E, E, E]
["is-null", E]                   ["is-not-null", E]
["like", E, ":param"]            ["not-like", E, ":param"]        # pattern bound verbatim
["contains", E, ":param"]        ["starts-with", E, ":param"]     ["ends-with", E, ":param"]
                                                                 # value is wildcard-escaped
```

`E` is `"$alias.col"`, `":param"`, or an aggregate array.

**Order terms**: `"@alias"` or `"$a.c"`, or `[key, "asc" | "desc"]`, or
`[key, dir, "nulls-first" | "nulls-last"]`. On dialects without native `NULLS` ordering
(MySQL) the null placement is emulated with an `(expr IS NULL)` sort key.

## Dialects

`Soniqle.postgres()`, `.sqlite()`, `.mySQL()` ship built in. To target something else,
implement `SQLDialect` — it supplies only a quote-character choice, a placeholder token and
a few capability flags; all escaping and assembly stays in the engine.

```swift
struct SQLServerDialect: SQLDialect {
    let name = "SQL Server"
    let identifierQuote: IdentifierQuote = .double   // uses "..."; brackets not modelled
    func placeholder(position: Int) -> String { "@p\(position)" }
}
let soniqle = Soniqle(dialect: SQLServerDialect())
```

## Options and schema

```swift
var options = CompileOptions.secureDefault
options.maxInListExpansion = 5_000          // raise a specific limit; none can be disabled

let schema = Schema([
    "users":  ["id", "name", "active"],     // only these columns
    "orders": .any,                         // any column
])

let soniqle = Soniqle.postgres(schema: schema, options: options)
```

## Errors

Every entry point is `throws(SoniqleError)`. `SoniqleError` has a stable `.code`
(`SoniqleError.Code`), a human-readable `.message`, and an optional JSON-Pointer `.path`
(e.g. `/where/2/0`) into the source document.

```swift
do {
    let statement = try soniqle.compile(json: json, parameters: params)
} catch {
    switch error.code {
    case .missingParameter, .unusedParameter: …
    case .invalidIdentifier, .unknownTableAlias: …
    default: …            // .code is non-frozen; keep a default
    }
}
```

## Development

```
swift build
swift test
swift build -Xswiftc -warnings-as-errors      # CI
```
