# Finance libraries

This directory contains reusable Gleam libraries for finance plugins and other
applications. They do not import `pi_gleam`, export Pi extensions, or produce
artifacts under `dist/`.

The first batch was arbitrated on 2026-08-04 from
`/tmp/pi-sparkles-proposal`. Its five packages and the subsequently graduated
`finance_math`, `finance_series`, and `finance_calendar` substrates are
**Experimental**. Their shared `0.1` foundation is complete and suitable for
developing plugins in this monorepo; public APIs and wire formats may still
change before the packages are declared stable.

```text
finance_core ──> finance_provenance
      │
      ├────────> finance_http ──┐
      │                         │
      ├────────> finance_table  │
      ├────────> finance_math   │
      ├────────> finance_series─┤
      ├────────> finance_calendar
      │                         v
      └────────────────> finance_testkit
```

The diagram shows dependency direction from foundation to consumer.
`finance_series` depends on core and math; calendar depends only on core.
`finance_testkit` depends on core and HTTP. No core package or core test may
depend on testkit.

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

Wave B Pi extensions remain proposals in `ROADMAP.md`. They should be selected
only after these packages meet their README acceptance criteria and the needed
provider adapters have their own endpoint, authentication, entitlement,
licence, pacing, and cache designs.

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
