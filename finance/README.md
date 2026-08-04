# Finance libraries

This directory contains reusable Gleam libraries for finance plugins and other
applications. They do not import `pi_gleam`, export Pi extensions, or produce
artifacts under `dist/`.

The first batch was arbitrated on 2026-08-04 from
`/tmp/pi-sparkles-proposal`. Its five packages and the subsequently graduated
`finance_math`, `finance_series`, and `finance_calendar` substrates are
**Experimental**. `finance_openfigi` and `finance_sec` are provider adapters
built above them. Their shared `0.1` layer is suitable for developing plugins in this
monorepo; public APIs and wire formats may still change before stability.

```text
finance_core ─┬─> finance_provenance
              ├─> finance_http ─┬─> finance_openfigi
              │                 ├─> finance_sec
              │                 └─> finance_testkit
              ├─> finance_table
              ├─> finance_math ────> finance_series
              ├────────────────────> finance_series
              └─> finance_calendar ─> finance_sec
```

The diagram shows dependency direction from foundation to consumer.
`finance_series` depends on core and math; calendar depends only on core.
`finance_testkit` depends on core and HTTP. `finance_openfigi` and `finance_sec`
remain reusable outside Pi and share the HTTP policies rather than implementing
plugin-local fetch stacks. The SEC adapter also owns lossless XBRL source-number
decoding and composes calendar arithmetic for explicit statement-period shapes,
so every consumer sees the same exact facts and period rules. No core package or core
test may depend on testkit or a provider adapter.

## Functional architecture

All packages follow the repository's `FUNCTIONAL_DESIGN.md` standard. This is a
release gate, not a stylistic preference:

- domain values are immutable and created through validating constructors;
- parsing, normalization, finance rules, calculations, rendering, retry
  decisions, cache policy, and workflow transitions are pure functions;
- expected failure is an exhaustive `Result`, not a throw or sentinel value;
- clocks, randomness, HTTP, storage, hashing FFI, and file access are explicit
  capabilities interpreted at package boundaries;
- stateful policies expose pure reducers from previous state plus event to next
  state plus effects;
- deterministic production interpreters and scripted test interpreters obey the
  same contracts;
- tests cover laws, round trips, idempotence, invariants, and event sequences in
  addition to individual examples.

An effectful package such as `finance_http` is not exempt: network execution is
the shell, while request normalization, retry classification, delay choice,
rate-limit evolution, cache decisions, cassette matching, and error redaction
remain pure and independently testable.

The F0 Pi extensions and the
`sec_edgar`/`sec_xbrl`/`stock_fundamentals` F1 slices are now Experimental.
The SEC foundation also supplies pure exact-period filing resolution, strict
source-retaining Q4 subtraction, and comparable direct-fact trend validation;
provider I/O and Pi rendering remain outside those derivation laws.
`stock_fundamentals` composes those proven candidates with local `finance_math`
formula trees for free cash flow, net margin, and diluted EPS, retaining every
input instead of embedding arithmetic in its effect shell. Its growth and TTM
compositions additionally validate explicit calendar gaps, exact direct-quarter
continuity, and an annual-shaped complete TTM window. The complementary TTM
bridge retains and validates annual, current-YTD, and prior-YTD sources.
Mixed-quarter TTM uses an explicit direct/derived sum type and expands derived
Q4 observations into their direct annual and YTD formula leaves.
Named multi-input metrics may select each SEC accession independently, then
apply the pure same-period and same-filing proof before formula evaluation.
Later plugins should be selected
only after their provider adapters have endpoint, authentication, entitlement,
licence, pacing, pagination, and cache designs comparable to
`finance_openfigi` and `finance_sec`.

## Completed 0.1 foundation

The base supports provider-neutral exact values and observation envelopes;
safe cancellable HTTP with retry, rate, queue, cache, and cassette policies;
arbitrary exact formula trees plus bounded approximate analytics; ordered,
missing-aware and as-of-aligned series with exact returns, OHLCV, paths, and
portfolio attribution; market sessions, business days, day counts, joint
calendars, and coupon schedules; canonical evidence manifests with bounded
verification; unit-aware bounded Markdown/CSV/JSON tables; and deterministic
synthetic/conformance test tools.

“Foundation complete” does not mean “every named financial model is built in.”
Provider adapters, accounting taxonomy mappings, authoritative calendar data,
curve construction, optimizers, option models, order execution, and live data
entitlements remain separate packages or plugin work. The generic primitives
are deliberately sufficient for those layers without putting provider or
business policy into the foundations.
