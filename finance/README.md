# Finance libraries

This directory contains reusable Gleam libraries for finance plugins and other
applications. They do not import `pi_gleam`, export Pi extensions, or produce
artifacts under `dist/`.

The first batch was arbitrated on 2026-08-04 from
`/tmp/pi-sparkles-proposal`. All five packages are in **Implementing**: each has
a reviewed design contract, a compiling pure API slice, and deterministic unit
tests, but none claims a complete or stable `0.1` API yet.

```text
finance_core ──> finance_provenance
      │
      ├────────> finance_http ──┐
      │                         │
      ├────────> finance_table  │
      │                         v
      └────────────────> finance_testkit
```

The diagram shows dependency direction from foundation to consumer.
`finance_testkit` depends on both core and HTTP. No core package or core test
may depend on testkit.

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
