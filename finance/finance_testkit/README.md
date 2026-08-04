# finance_testkit

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_testkit` supplies deterministic clocks, seeded synthetic finance data,
cassette helpers, decoder-conformance harnesses, and reusable edge-case
fixtures. It helps provider adapters and Pi plugins test bad data and failure
paths without live APIs. It is test infrastructure, not a production market
data source.

The implemented base includes an immutable manual clock, ordered generic
success/failure scripts with typed exhaustion, and a repeatable Park-Miller seed
with explicit range generation. A generic scenario fold captures every state
and emitted effect. The pure scripted HTTP model consumes typed
`Response`/`TransportError` outcomes and captures only redacted stable request
keys; its original value remains unchanged. The cassette helper builds and
strictly replays complete immutable request/outcome sequences using the single
`finance_http` cassette format. The base also includes versioned synthetic
quote/OHLC generators, decoder-conformance matrices, redaction law checks, and
validated fixture governance metadata. File helpers, latency/body pause
simulation, and larger reviewed fixture catalogs are optional extensions.

## User stories

- An adapter test freezes time, scripts transport responses, and asserts retry,
  freshness, decoding, and redaction behavior without sleeping or networking.
- Every provider decoder is checked against the same missing/null/wrong-type,
  precision, timestamp, pagination, and unknown-enum cases.
- A plugin test obtains obvious synthetic quotes, bars, splits, dividends, and
  ambiguous symbols with stable seeded output.
- Cassette mismatches explain the safe normalized-request difference without
  revealing credentials.

## Non-goals

- No production cache, HTTP implementation, provider client, Pi runtime fake,
  benchmark corpus, personal database snapshot, or licensed historical dataset.
- No guarantee that synthetic prices have realistic predictive or statistical
  properties.
- No duplicate core types and no second cassette format.
- No dependency from `finance_core` or its tests back to testkit.

## Dependencies

`finance_testkit` depends on `finance_core` and `finance_http`. It consumes
`finance_http/cassette` request, response, and replay types rather than defining
its own `Cassette`. It may later offer optional helpers for provenance/table
consumers only if doing so does not introduce dependency cycles; package splits
are preferred over cyclic convenience imports.

## Functional design

Generators, shrinkable scenario descriptions, cassette builders, request
matchers, redaction assertions, and decoder-conformance matrices are pure and
seeded explicitly. A generator is a value transformation from seed plus
configuration to output plus next seed; it never reads global randomness.

Manual clocks, scripted transports, stores, and file helpers are interpreters
for explicit capabilities. Test scenarios describe ordered events/effects as
data and can be folded through downstream reducers. This lets one scenario run
against a pure model, a fake interpreter, and—where appropriate—a Bun boundary
contract without changing expected domain results.

## Module surface

| Module | Responsibility |
| --- | --- |
| `finance_testkit/clock` | frozen/manual clock, scripted sleeper, deadline and cancellation assertions |
| `finance_testkit/transport` | pure scripted typed outcomes and redacted request capture; async/latency adapters later |
| `finance_testkit/cassette` | builders and assertions over `finance_http/cassette` |
| `finance_testkit/generator` | seeded synthetic instruments, observations, quotes, bars, and actions |
| `finance_testkit/fixture` | required provenance/licence/retrieval metadata for reviewed fixtures |
| `finance_testkit/decoder` | provider-decoder conformance matrix and failure assertions |
| `finance_testkit/redaction` | reusable mandatory secret corpus and leak assertions |

## Time and transport control

A manual clock starts at a caller-supplied core `Instant` and advances only when
the test requests it. The scripted sleeper records requested delays and resolves
when the test advances time. Timeout, retry, and cancellation tests therefore
contain no wall-clock wait.

The scripted transport currently advances as a pure immutable transition. Each
send consumes one typed success/failure, records `request.safe_key`, and returns
typed `Exhausted` when an unexpected call occurs. Tests can fold this directly
through reducers and add `promise.resolve` only in their outer interpreter.
Future adapters will add virtual latency and pause points at headers/body;
production code must continue to use the real asynchronous transport.

## Cassette helpers

Testkit constructs and compares the versioned cassette records owned by
`finance_http`. Matching uses the transport's normalized request key. Builders
require secrets to be declared separately from safe request data and run the
mandatory redaction corpus before a cassette can be serialized.

If file helpers are included, `load` and `save` return
`Promise(Result(...))`; Bun file access is not represented as synchronous pure
Gleam. Checked-in cassettes must be minimal, reviewed, licence-permitted, and
free of credentials, account IDs, signed URLs, private paths, and unnecessary
provider content.

## Synthetic data

Generators use an explicit seed and stable algorithm version. Outputs carry a
provider/source marker such as `SYNTHETIC_TEST_DATA` and identifiers that cannot
be confused with common production symbols. Initial scenarios include:

- ambiguous symbol/listing and share-class resolution;
- delayed, stale, missing, estimated, revised, and restated observations;
- raw and adjusted bars around splits and dividends;
- suspension gaps, zero volume, negative prices where an instrument permits
  them, large decimals, currency/unit mismatch, and timezone boundaries;
- pagination, duplicate rows, out-of-order results, partial provider responses,
  and schema evolution.

Synthetic values are deterministic but not authoritative. They must never be
used to answer a user’s finance question.

## Calendar and corporate-action fixtures

Algorithmic toy calendars may be generated for state-machine tests. Real
exchange holiday/early-close fixtures must come from an authoritative source
whose licence permits inclusion and must record source, retrieval date, covered
market, and covered date range. They are fixed reviewable fixtures, not
pseudo-random generated “truth.”

Split/dividend fixtures use invented instruments unless a small real event is
necessary for a provider contract and redistribution is permitted. Expected
adjustment results state their formula and rounding policy.

## Decoder conformance

The harness accepts a provider decoder and named valid/invalid payloads. The
common matrix covers missing versus null, wrong scalar/container types, unknown
fields, new enum values, exact decimal strings, unsafe JSON numbers, timestamps
and offsets, duplicate keys where observable, empty pages, pagination loops,
partial errors, and provider error envelopes.

A decoder must return typed failure with a safe field path; it cannot throw,
coerce missing to zero, ignore unit/currency changes, or accept an unsafe
numeric value as exact.

## Data governance and security

- No fixture may be imported from a personal PostgreSQL database, broker
  account, private workspace, or production log.
- A future import tool must default to generating a structural schema/summary,
  not copying rows, and requires explicit licence and privacy review.
- Mandatory leak assertions cover common API keys, bearer/basic credentials,
  cookies, account IDs, signed queries, home paths, and configured provider
  secrets.
- Failure messages are bounded and use redacted diffs.

## Test design

Testkit tests itself with golden seeded outputs, frozen-clock schedules,
cancellation races, scripted call counts, cassette round trips/mismatches,
redaction leak corpora, decoder-harness pass/fail examples, and fixture metadata
validation. A fresh process must produce byte-identical output for the same
seed and algorithm version.

Downstream packages still own assertions for their behavior. Testkit offers
inputs and harnesses, not provider-specific expected business rules.

Testkit will provide reusable law harnesses for round trips, normalization
idempotence, stable seeded generation, state invariants, and deterministic
effect traces. A law harness never hides which generated inputs failed.

## Distribution and compatibility

The Hex package contains source and small permitted fixtures only. Seeded
generator algorithm changes require a version label so golden outputs do not
silently drift. Cassette compatibility follows `finance_http` schema versions.
The package targets Bun where filesystem FFI is used; pure builders remain
portable across Gleam JavaScript runtimes.

## Acceptance criteria

- Frozen retry/cancellation tests run with zero real sleeps and network calls.
- Seeded outputs are byte-stable and unmistakably synthetic.
- Cassette helpers use the single `finance_http` format and reject secret leaks.
- Decoder conformance catches precision loss, missing/null confusion, unsafe
  coercion, and unknown provider values.
- Every real-world fixture has licence/source/date metadata.
- No core-to-testkit dependency or personal data enters the package.
- Formatting, warnings-as-errors build, unit tests, FFI tests, and Hex tarball
  audit pass.

## Post-foundation decisions

- Whether file cassette helpers belong here or in `finance_http` with only
  builders in testkit.
- Minimum authoritative calendar fixture set that is useful and redistributable.
- Whether provider-decoder conformance should be a separate package once the
  adapter catalog grows.
