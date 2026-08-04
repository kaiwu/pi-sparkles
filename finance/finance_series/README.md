# finance_series

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_series` is the temporal substrate for finance metrics. It validates
ordered timestamped data, preserves missing observations, aligns independent
timelines with exact or bounded backward-looking joins, builds rolling windows,
delegates resampling buckets to an injected calendar rule, aggregates exact
OHLCV bars, calculates exact decimal returns and chain-linked paths, preserves
observation provenance, and runs aligned portfolio and factor analytics through
`finance_math`.

The package is pure. It contains no Pi, HTTP, filesystem, clock, randomness, or
JavaScript FFI. `finance_core` and `finance_math` are local path dependencies in
this monorepo; they do not need to be published to Hex during development.

## Why this package exists

A covariance function over two bare lists cannot prove that their observations
refer to the same dates. A rolling metric cannot decide whether a missing day
is a market holiday, an unavailable provider response, or a genuinely absent
fact. `finance_series` makes those decisions visible before mathematical
functions receive comparable values.

It therefore treats the following as policy rather than convenience behavior:

- strict timestamp ordering and duplicate rejection;
- exact timeline versus intersection alignment;
- preserve, drop, forward-fill, or reject missing values;
- full-only versus partial rolling windows;
- caller-supplied calendar/timezone buckets for resampling; and
- requiring every portfolio constituent versus explicitly renormalizing the
  available weights.

## Modules

| Module | Responsibility |
| --- | --- |
| `finance_series/series` | immutable ordered `Series`, `Point`, `Datum`, validation, mapping, and missing policies |
| `finance_series/alignment` | deterministic inner/left/right/full merge joins |
| `finance_series/window` | full or partial rolling windows and pure transformations |
| `finance_series/resample` | adjacent bucket grouping through an injected bucket-start function |
| `finance_series/returns` | exact decimal simple returns with explicit precision and missing propagation |
| `finance_series/analytics` | aligned pairs, spreads, beta, correlation, tracking error, and information ratio |
| `finance_series/path` | cumulative wealth/return and drawdown paths with explicit gap invalidation policy |
| `finance_series/portfolio` | fixed/dynamic weighting, return aggregation, and component contribution attribution |

## Ordered series

`series.new` accepts `Point(at, Datum(value))` values only in strictly increasing
timestamp order. Duplicate and decreasing timestamps are typed errors. Empty
series are valid so filtering and inner joins remain total. Construction never
sorts silently because sorting could hide a provider pagination or timestamp
decoder defect.

`Datum(value)` is either `Present(value)` or
`Missing(finance_core.observation.MissingReason)`. Missing values are not zero,
`None`, or NaN. `resolve_missing` requires one named policy:

- `Preserve` leaves the series unchanged;
- `Drop` removes missing timestamps;
- `ForwardFill` copies only a previously observed value and preserves leading
  missing points; and
- `Reject` fails at the first missing point without modifying the series.

Forward filling is a mechanical operation, not an entitlement or freshness
claim. Callers must record it as a metric assumption and must not use it where
provider or accounting semantics prohibit carrying values forward.

## Alignment

`alignment.align` performs a linear immutable merge over two validated series.
`Inner`, `Left`, `Right`, and `Full` have conventional join semantics, but the
result retains `Option(Datum(a))` on each side so an absent timestamp remains
different from a timestamp carrying an explicit missing datum.

Analytical helpers add a second, stricter vocabulary:

- `ExactTimeline` rejects the first timestamp present on only one side; and
- `Intersection` deliberately calculates over shared timestamps.

Within the selected timeline, `RejectMissing` fails and `DropMissing` explicitly
performs complete-case deletion. Beta, correlation, active return, tracking
error, and information ratio cannot accidentally zip unrelated list positions.

## Windows and resampling

`window.windows` returns immutable point windows. `FullOnly` emits only windows
with the requested sample count; `IncludePartial` exposes the shorter warm-up
history. `window.rolling` receives a pure transform and timestamps each result
at its window end. A fallible calculation can return `Result` as its mapped
value and sequence failures later.

`resample.resample` does not contain UTC-day, exchange-session, month-end, or
holiday guesses. The caller injects `fn(Instant) -> Instant` that maps a point
to a bucket start. Adjacent equal buckets are aggregated; backward bucket output
is rejected. The local `finance_calendar` package now supplies pure session and
business-date rules; an adapter still must combine them with a maintained IANA
timezone resolver before producing an instant bucket. Synthetic tests can inject
tiny deterministic buckets directly.

## Returns and analytics

`returns.simple` computes `(current / previous) - 1` using exact `Decimal`, an
explicit result scale, and an explicit rounding mode. The first observation has
no return and is omitted. Missing data propagates across adjacent returns; the
algorithm never skips over a gap to manufacture a multi-period return. A zero
previous value is a typed failure.

Statistical analytics use `Float` only after timeline and missing-data policies
have produced comparable values. They delegate estimator behavior to
`finance_math`. Annualization frequency remains an argument rather than being
inferred from timestamps.

`path.wealth_index` and `path.cumulative_return` chain approximate returns. A
missing period must either `SkipMissingReturn`—emitting a gap but retaining the
last known level—or `InvalidateAfterMissing`, which keeps every later path value
missing. `path.drawdown` applies the same policy to its running peak. Returns
below -100%, non-positive initial wealth, and non-positive drawdown levels are
typed failures.

## Portfolio aggregation

`portfolio.weighted_returns` validates non-empty unique component identities,
a positive weight tolerance, and net weights summing to one within that
tolerance. Long/short weights are supported.

The output uses the union of component timestamps:

- `RequireAll` emits `Missing(Unavailable)` if any component is absent or
  missing; and
- `RenormalizeAvailable` is an explicit opt-in that divides by net available
  weight, remaining missing when that weight is effectively zero.

These are fixed-weight arithmetic returns. Rebalancing schedules, transaction
costs, holdings, cash flows, leverage constraints, taxes, and corporate actions
belong to higher-level portfolio workflows.

`dynamic_attribution` accepts a weight series and return series per component.
It validates net weights at every observation in strict mode and returns both
the total series and component `weight * return` contribution series. Explicit
renormalization divides available weights and preserves missing contribution
points for unavailable constituents; it never hides which component was absent.

## Functional composition

The package’s functions transform immutable values and return typed results.
Provider adapters decode observations into `Series`; calendar functions supply
buckets; alignment produces comparable samples; `finance_math` calculates the
metric; and provenance records the source observations and declared policies.

```text
provider observations
        │
        v
 validated Series ──> missing policy ──> alignment/window/resample
                                                │
                                                v
                                          finance_math
                                                │
                                                v
                                  metric + assumptions + evidence
```

This separation keeps financial interpretation outside generic containers and
makes every sequence reproducible in tests.

## Acceptance criteria

- Duplicate or decreasing timestamps never enter a `Series`.
- Missing observations remain explicit under every transformation.
- Joins preserve the distinction between an absent timestamp and missing data.
- Exact and intersection analytics cannot be confused accidentally.
- Rolling warm-up and resampling bucket behavior are caller-visible policies.
- Decimal returns never pass provider values through binary floating point.
- Portfolio renormalization never occurs unless explicitly requested.
- Path gaps either resume or invalidate through an explicit policy, and dynamic
  component contributions reconcile to each total return.
- Pure tests cover ordering, missing policies, joins, windows, resampling,
  returns, aligned analytics, and portfolio gaps.
- Formatting and warnings-as-errors builds pass.

## Post-foundation expansion

- calendar-backed daily/weekly/monthly/session resampling helpers;
- calendar-specific stock-versus-flow convenience aggregators;
- log returns alongside exact-decimal chain linking and the approximate path;
- expanding/anchored windows and duration-based windows;
- transaction-aware holdings, turnover, rebalance events, Brinson attribution,
  and geometric contribution linking;
- time-aligned multi-factor regression adapters and residual series; and
- additional reusable law/property suites.

## Non-goals

- No market holiday database, timezone conversion, provider decoder, cache,
  storage, dataframe, chart, or Pi interface.
- No implicit interpolation, backfill, corporate-action adjustment, frequency
  inference, survivorship correction, or look-ahead data selection.
- No assertion that two aligned values have compatible currencies, units,
  entitlements, accounting bases, or release vintages; adapters must validate
  those domain constraints before calculation.
