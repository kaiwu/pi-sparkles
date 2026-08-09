# portfolio

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`portfolio` is the narrow rank-19 implementation authorized by
[Course Session 21](../../trading-course/sessions/21_cg_portfolio_import_inspection_contract_20260809.md).
It imports caller-supplied local CSV or JSON, validates and preserves exact
snapshot/position facts, reconciles values per currency, and exposes bounded
session-local inspection. It is not a broker adapter or a portfolio-review
engine.

The plugin registers three read-only tools:

- `portfolio_import` reads one exact regular file under explicit byte, row,
  column, field, and JSON-depth budgets. It returns a compact summary and keeps
  the immutable decoded snapshot only in a bounded in-memory store owned by the
  current plugin instance.
- `portfolio_summary` returns the same compact projection by exact
  `snapshotId` without reading the file again.
- `portfolio_positions` pages retained source rows and supports exact optional
  position/source-row ID, track, currency, security-type, identity-resolution,
  unsupported, conflict, and decode-failure filters.

The in-memory store exists only to reconcile Session 21's required
`snapshot_id` drill-down with its prohibition on durable storage. It is capped
at eight immutable snapshots, is serialized through sequential tool execution,
and does not survive extension reload or Pi restart. Reimporting the same ID and
same content hash is idempotent; the same ID with different content fails
closed. No Pi state, database, journal, or local output file is written.

## Canonical import formats

Both formats preserve exact source lexemes. Numeric portfolio fields must be
strings; the declared decimal convention is applied only when producing a
typed exact-decimal fact. Original text is retained in every field result.

JSON is one object:

```json
{
  "snapshot": {
    "snapshot_id": "snap-001",
    "source_kind": "ImportedFile",
    "base_currency": "USD",
    "source_as_of": "2026-08-08T20:00:00Z",
    "entitlement": "caller_private_local_use",
    "source_declared_total": "1250.00",
    "source_total_currency": "USD"
  },
  "positions": [
    {
      "position_id": "P1",
      "track": "us",
      "listing_id": "caller-listing-1",
      "mic": "XNAS",
      "source_symbol": "AAPL",
      "security_type": "CommonStock",
      "direction": "Long",
      "quantity": "10",
      "quantity_unit": "shares",
      "current_mark": "125.00",
      "mark_time": "2026-08-08T20:00:00Z",
      "market_value": "1250.00",
      "position_currency": "USD",
      "source_row_id": "row-1"
    }
  ]
}
```

CSV uses one header row and repeats snapshot fields on every data row. Required
snapshot columns are `snapshot_id`, `source_kind`, `base_currency`,
`source_as_of`, and `entitlement`. Repeated snapshot values must agree exactly.
Position fields follow Session 21's names. Unknown columns/keys and their
values are retained under `extraColumns`; explicit null, blank, unavailable,
absent, and decode-failure states remain distinct.

CSV supports caller-declared comma, tab, or semicolon delimiters, RFC-style
quoted fields and escaped quotes, UTF-8, ISO-8601 date lexemes, and three exact
decimal conventions: plain dot decimal, comma-grouped dot decimal, and
space-grouped comma decimal. Formula-looking text is never evaluated; it is
flagged and retained. ASCII control characters other than the selected tab
delimiter and record separators fail closed. JSON unknown values are retained
as bounded structured values, but known exact numeric fields still require
strings.

## Snapshot and row laws

- `snapshot_id`, `source_kind`, `base_currency`, `entitlement`, import time,
  raw-file SHA-256, and unauthenticated-import status are always visible.
- Account identifiers are retained internally but returned only when the
  import explicitly sets `accountVisibility=review_visible`. Paths, personal
  names, addresses, and tax identifiers are never returned or logged.
- A ticker never selects a track, MIC, listing, share class, provider, or
  currency. Identity is resolved only when exact source facts prove the
  required track and source symbol/listing scope.
- Cash, liabilities, accruals, pending transfers, unsettled trades, shorts,
  derivatives, and unknown types remain rows. Shorts, derivatives, and unknown
  types are visibly unsupported by first-slice risk calculations.
- Exact duplicate `position_id` rows collapse with `duplicateCount`; differing
  rows sharing an ID are all retained and marked conflicting. Multiple lots,
  issuer listings, ADRs, and currencies are never automatically aggregated.
- Source-reported value/P&L fields stay provider or caller facts. Independent
  market value is calculated only from known exact quantity and mark facts in
  one position currency with a known mark time. No realized P&L is derived.
- Subtotals are per currency. Foreign-currency legs are never converted or
  folded into the base currency without later explicit FX evidence. A source
  total is compared only when a complete same-currency calculated leg exists;
  delta and caller-selected tolerance are facts, not correctness verdicts.
- Empty, unsupported, unresolved, malformed, stale, conflicting, duplicate,
  and truncated states remain visible. No row is silently dropped.

## Effect and safety boundary

The only filesystem effect is a generic bounded regular-file read. Symbolic
links and non-regular files are rejected. Decoding is strict UTF-8 and
cancellable; no archive, XLSX, SQL, formula, macro, network, broker, write, or
execution effect exists. The source path is redacted from results and failures.
A SHA-256 hash binds returned facts to the bytes read but authenticates neither
the broker nor the facts.

Caller budgets may not exceed 10 MB, 10,000 rows, 100 columns, 4,096 UTF-8
bytes per field, or JSON nesting depth 10. Row-limit truncation returns the
retained prefix and next source-row offset. A byte-limited CSV read returns
only complete records from the retained prefix and reports truncation; a JSON
document that cannot be fully read is rejected rather than fabricated.

## Explicit exclusions

The first slice performs no durable storage, snapshot comparison, automatic
aggregation, tax-lot accounting, FX conversion, short/derivative risk model,
broker authentication, diversification/concentration/correlation analysis,
stress/VaR/CVaR, attribution, optimization, rebalancing, recommendation,
authorization, trade mutation, evidence-sufficiency verdict, or next-action
choice. Those remain behind Session 21's named depth triggers and `CG-LIVE`
where applicable.

## Verification

Eight pure tests cover CSV quoting/control/budgets, JSON shape/depth,
information states, identity, duplicate/conflict, multi-currency,
reconciliation, session transitions, and pagination. Seven bundled scenarios
cover the exact tool surface, regular-file reads, strict UTF-8, symlinks,
cancellation, byte-prefix CSV truncation, privacy, idempotence, session-local
lookup, and no writes. Warnings-as-errors, architecture, artifact export,
installed-Pi smoke, and the full repository regression pass on 2026-08-09.
