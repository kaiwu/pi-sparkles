# finance_http

Status: **Implementing** · version: `0.1.0` · target: JavaScript/Bun

`finance_http` is an asynchronous, provider-safe transport layer for finance
adapters. It centralizes retry, pacing, bounded concurrency, cache hooks,
redaction, cancellation, response limits, and deterministic cassette replay.
It does not understand quotes, filings, calendars, or any particular provider.

The implemented first slice is deliberately pure: safe HTTPS request identity,
explicit idempotency, validated finite retry policy, retryable-failure
classification, capped exponential delays, bounded `Retry-After`, and typed
stop reasons. Transport, cancellation, queue/rate-limit reducers, cache,
cassettes, redaction, response limits, and Bun interpreters remain 0.1 work.

## User stories

- An adapter issues a request through one policy-enforced client and receives a
  typed response or typed failure.
- Tests replay the same normalized request without live network access, sleeps,
  credentials, or nondeterministic clocks.
- Rate-limit headers and retry delays are visible to callers and never hidden
  behind unbounded retries.
- Errors and cassettes are safe to inspect because authentication material was
  removed before recording.

## Non-goals

- No provider endpoint paths, JSON decoders, credentials discovery, finance
  domain conversion, entitlement negotiation, or Pi APIs.
- No global disk cache, hidden process singleton, background refresh, or
  cross-process rate limiter in 0.1.
- No silent stale-cache fallback. A provider adapter may explicitly request and
  label cached data after a transport failure.
- No attempt to make a credential-free public API immune to provider terms or
  operational limits.

## Planned modules

| Module | Responsibility |
| --- | --- |
| `finance_http/request` | safe method, URL, headers, body, idempotency, and normalized key types |
| `finance_http/response` | bounded bytes/text, status, safe headers, timings, and cache metadata |
| `finance_http/client` | policy composition and promise-returning request execution |
| `finance_http/retry` | retry classification, backoff, jitter, attempt budget, and `Retry-After` |
| `finance_http/rate_limit` | per-origin/token-bucket state and provider header observations |
| `finance_http/cache` | injected async cache interface and explicit hit/miss/stale records |
| `finance_http/cassette` | canonical request/response format, recorder, replay transport, and redaction |
| `finance_http/error` | bounded, redacted transport/policy/status/decode-adjacent errors |

## Functional design

Only the final transport, cache, and sleep operations are effectful. Request
normalization, retry classification, backoff calculation, rate-limit state,
queue selection, cache eligibility, cassette matching, redaction, and error
construction are pure functions over immutable policy/state values.

The client workflow is modeled as a reducer from `(State, Event)` to
`#(State, List(Effect))`. Effects describe transport attempts, sleeps, cache
reads/writes, and observer notifications. The Bun interpreter executes them and
feeds typed outcomes back into the reducer. This makes attempt sequences,
budgets, cancellation races, fairness, and stale-result rejection testable by
folding values with a manual clock. Transport, clock, sleeper, jitter, and cache
remain explicit capabilities; no module-level client or rate-limit singleton is
allowed.

## Core API shape

Every real request is asynchronous:

```gleam
pub type Transport =
  fn(Request, AbortSignal) -> Promise(Result(Response, TransportError))

pub fn send(
  client: Client,
  request: Request,
  signal: AbortSignal,
) -> Promise(Result(Response, HttpError))
```

The exact public names may change during implementation, but a network, retry
sleep, or file-backed cache operation must never be exposed as a synchronous
`Result`. Cancellation propagates through queueing, sleep, transport, body
reading, cache, and cassette operations.

`Client` is constructed with explicit dependencies: transport, clock, sleeper,
random/jitter source, retry policy, concurrency policy, rate-limit policy,
cache, redactor, response limits, and user-agent. Tests replace all of them.

## Request normalization

A request has method, parsed URL, ordered multi-value headers, optional bounded
body, timeout, response-byte limit, and idempotency classification. Its
normalized key includes method, canonical origin/path, sorted non-secret query
parameters, selected representation headers, safe body hash, and an explicit
provider/entitlement namespace.

Authorization, cookies, signed parameters, timestamps/nonces, and configured
secret fields are excluded or replaced before a key or cassette is emitted.
Collisions between materially different requests are a typed error, not a
replay guess.

## Retry and rate-limit policy

- Default retryable failures are transient transport errors, `408`, `425`,
  `429`, and selected `5xx` statuses. Provider adapters may narrow the set.
- Non-idempotent requests are never retried unless the adapter supplies a
  stable idempotency key and explicitly opts in.
- `Retry-After` and supported provider reset headers override exponential
  backoff within a configured maximum delay.
- Attempts, elapsed time, total sleep, and response-body work all share finite
  budgets. Defaults never retry forever.
- Jitter is injected and deterministic in tests.
- Per-origin concurrency and rate limits are independent. Queues are bounded
  and cancellation removes waiting requests.

When a limit is exhausted, `HttpError` reports the safe origin, attempts,
observed limit state, and next retry time when known. It does not return an old
response as if it were current.

## Cache contract

The client accepts an asynchronous cache interface. Cache records carry stored
time, expiry, validators, normalized request key, safe response metadata, and
body. Modes distinguish bypass, read-through, revalidate, offline-only, and
write-disabled operation. A stale record is returned only through an explicit
result state requested by the caller; freshness is never inferred away.

Provider adapters own TTL, redistribution, and whether an endpoint may be
cached at all. `finance_http` enforces the supplied policy but does not invent
one.

## Cassette ownership

This package exclusively owns cassette formats and replay matching. A cassette
stores schema version, normalized request, redacted response, deterministic
timing/rate-limit metadata, and optional failure. Recording is opt-in. Binary
bodies are size-limited and encoded explicitly; streaming/unbounded responses
cannot be recorded.

`finance_testkit` will provide convenient cassette builders and provider
fixtures by using these types. It must not define a second `Cassette` model.
File loading/saving is promise-returning FFI and lives here if included in 0.1.

## Errors and observability

`HttpError` distinguishes invalid request, queue full, timeout, cancelled,
transport, TLS/DNS where observable, rate limited, retry exhausted, response
too large, unacceptable status, cache, cassette mismatch, and internal FFI
contract violation. Provider response bodies are truncated and redacted before
being attached. Full thrown objects, request headers, and bodies are not
retained.

An optional observer receives structured attempt/queue/cache/rate-limit events.
It cannot mutate requests or receive secrets. The library emits no logs by
default.

## Test design

- Retry matrices by method, idempotency, status, transport error, retry header,
  budget, and cancellation point.
- Frozen-clock and injected-sleeper tests with no wall-clock delay.
- Reducer-law tests proving exhausted/cancelled workflows emit no later network
  effect and duplicate/stale completion events cannot revive a request.
- Queue fairness, per-origin isolation, bounded concurrency, overflow, and
  cancellation races.
- Cache hit/miss/revalidation/stale/offline tests proving stale state stays
  visible.
- Redaction tests for headers, queries, bodies, errors, redirects, keys, and
  cassettes.
- Cassette record/replay tests for canonical matching, mismatch diagnostics,
  schema versions, body limits, and deterministic failures.
- Bun FFI contracts for fetch errors, aborts, duplicate headers, binary bodies,
  redirects, timeouts, and response limits.

No unit or contract test calls a public provider.

## Distribution and compatibility

The Hex package includes Gleam and small reviewed JavaScript FFI sources. It
contains no credentials or recorded provider data. Runtime behavior is tested
on Bun; another JavaScript runtime is unsupported until it passes the same FFI
matrix. Cassette schema and normalized-key changes are versioned independently
so old fixtures fail clearly rather than replay incorrectly.

## Acceptance criteria

- All I/O and waiting are represented by `Promise` and support cancellation.
- Retry, queue, body, and elapsed-time budgets are finite and test-covered.
- Recorded requests, errors, and cache keys contain no configured secrets.
- Rate-limit exhaustion cannot masquerade as a fresh successful response.
- One cassette type is shared by transport and testkit.
- Deterministic tests cover retry, pacing, cache, cassette, and failure paths.
- Formatting, warnings-as-errors build, unit tests, Bun FFI tests, and Hex
  tarball audit pass.

## Open decisions

- The concrete Gleam HTTP request/response dependency versus a deliberately
  smaller package-owned transport record.
- Whether 0.1 includes file-backed cache/cassette helpers or only injected
  interfaces plus Bun reference implementations.
- Fairness algorithm for concurrent origins and whether rate-limit state needs
  an optional cross-process adapter later.
- Default response-size, retry-attempt, and elapsed-time limits.
