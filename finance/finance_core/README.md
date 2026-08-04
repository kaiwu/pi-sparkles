# finance_core

Status: **Implementing** · version: `0.1.0` · target: JavaScript/Bun

`finance_core` defines the canonical, provider-neutral values shared by the
finance packages. It contains no Pi extension code, networking, storage,
provider authentication, or analytical algorithms.

The implemented first slice includes exact decimal parsing, normalization and
comparison without JavaScript `Number`; validated instants, durations, dates,
currencies, MICs, symbols and identifiers; money values; instrument/listing
records; positive timeframes; safe source references; and metadata-preserving
`Observation(a).map`. Arithmetic, canonical JSON, timezone conversion, richer
adjustment/session types, and broader law/property tests remain 0.1 work.

## User stories

- A provider adapter can return a US, China, Hong Kong, or future-market
  instrument without inventing its own symbol, exchange, money, or timestamp
  shapes.
- A plugin can distinguish a listing symbol from a permanent security identity
  and must surface ambiguous resolution rather than guess.
- Every measured value can carry source, observation time, retrieval time,
  freshness, unit, and adjustment metadata.
- Financial decimals round and serialize identically across packages without
  passing through JavaScript binary floating point.

## Non-goals

- No HTTP clients, environment variables, caches, database access, Pi APIs, or
  UI rendering.
- No security-master database or symbol-resolution provider.
- No exchange holiday dataset. Core models sessions and dates; a future
  `finance_calendar` package owns calendar rules and data.
- No FX conversion, valuation, portfolio math, technical indicators, or order
  submission.

## Planned module surface

| Module | Responsibility |
| --- | --- |
| `finance_core/decimal` | exact normalized decimal parsing, comparison, arithmetic, quantization, and string encoding |
| `finance_core/time` | validated civil dates/times, UTC instants, durations, and IANA timezone identifiers |
| `finance_core/identifier` | permanent identifiers, provider identifiers, symbols, MICs, listings, and ambiguity results |
| `finance_core/instrument` | instrument class, issuer/security identity, listing and status metadata |
| `finance_core/money` | ISO currency codes, money values, units, and currency-safe operations |
| `finance_core/market` | exchange/session, timeframe, delayed/real-time and market-status labels |
| `finance_core/adjustment` | raw, split-adjusted, dividend-adjusted, and provider-defined adjustment bases |
| `finance_core/observation` | the common source/freshness/evidence envelope for a typed value |

The root `finance_core` module may re-export only a small ergonomic subset. It
must not become a catch-all module whose changes force every consumer to
recompile.

## Functional design

Core is entirely pure. Opaque types use smart constructors; transformations
return new values; and parsing, arithmetic, normalization, comparison, and
encoding return typed results without clocks, randomness, FFI, or ambient
configuration. Policies such as rounding and unknown-identifier handling are
ordinary values passed to functions, allowing callers to compose a pipeline
without global settings.

The initial implementation should publish laws alongside examples: decimal
normalization and encode/decode are idempotent, comparison is consistent with
canonical encoding, money operations preserve currency, observation mapping
preserves metadata, and identity resolution never turns multiple candidates
into one. Tests should exercise these laws across deterministic generated
vectors, not only hand-picked cases.

## Canonical representations

### Decimal

`Decimal` is opaque and represented by a normalized signed coefficient string
plus a non-negative scale. The coefficient is not a Gleam `Int`, because the
JavaScript target cannot exactly represent every large integer. Parsing rejects
exponents, separators, empty values, excess scale, and non-finite spellings
unless a separately named parser explicitly accepts them.

The initial operation set is parse, encode, compare, add, subtract, multiply,
divide with an explicit output scale/rounding mode, and quantize. The default
rounding mode is half-even; callers must opt into another mode. Division by
zero, invalid scale, overflow limits, and inexact operations return typed
errors. No operation silently converts through `Float`.

### Time

`Instant` is an integer count of Unix milliseconds within a documented safe
range. `Date` and `TimeOfDay` are validated civil components. `Timezone` stores
an IANA identifier, not a fixed offset. An instant never silently acquires a
timezone, and a local civil time never converts to an instant without an
explicit timezone/ambiguity policy. Leap-second handling is out of scope for
0.1 and will be documented as Unix-time semantics.

### Identity

`InstrumentId` identifies a security independently of a ticker. `Listing`
contains its exchange MIC, local symbol, currency, valid interval, and status.
External identifiers are tagged by scheme (`Figi`, `Cik`, `Isin`, `Cusip`,
`Sedol`, or provider-defined), with their licence/redistribution limitations
left to provenance and adapter layers. Resolution returns zero, one, or several
candidates with evidence; a bare ticker is never accepted as globally unique.

### Money and units

`Money` combines `Decimal` with a validated uppercase ISO 4217 code. Unknown or
non-ISO settlement units use an explicit `Unit`, not a fabricated currency.
Adding or comparing money with different currencies is an error. FX conversion
requires an external observed rate and is not part of core.

### Observation envelope

The planned `Observation(a)` contains:

- `value: a`;
- `as_of` and `retrieved_at` UTC instants;
- source kind and a minimal `SourceRef` containing provider and safe reference;
- `evidence_id: Option(String)` for a richer provenance record;
- freshness state (`Fresh`, `Stale`, `UnknownFreshness`) and optional maximum
  age used for the decision;
- quality states for missing, estimated, restated, revised, and delayed data;
- unit/currency and adjustment/session labels where applicable.

`SourceRef` deliberately lives in core. `finance_provenance` enriches it with
licence, hashing, assumptions, and manifests; core never imports provenance.
Adapters must not put credentials, signed query strings, or private account IDs
in a source reference.

## Invariants and error policy

- Constructors validate at the boundary and return typed errors; records with
  invalid MICs, currency codes, dates, scales, or negative durations cannot be
  constructed through the public API.
- Missing, zero, and unavailable are distinct.
- Raw and adjusted prices are distinct and identify the adjustment basis.
- Delayed and real-time are explicit entitlements, not inferred from age alone.
- JSON encoders are canonical and versioned. Decoders reject unknown enum
  values only where forward compatibility would be unsafe; otherwise they
  preserve an `Other(String)` form.
- Public errors contain safe fields and never carry an arbitrary provider body.

## Dependencies and boundaries

`finance_core` depends only on Gleam standard libraries. In particular it does
not depend on `finance_provenance` or `finance_testkit`. Provider adapters,
plugins, and higher-level libraries depend inward on core. JavaScript FFI is
allowed only where the JavaScript target cannot meet exactness or timezone
requirements, and each function requires a boundary contract test.

## Test design

- Table-driven decimal parsing, normalization, arithmetic, half-even rounding,
  large-coefficient, and serialization vectors.
- Property tests for ordering, encode/decode round trips, and arithmetic
  identities within declared bounds.
- Functor-style observation mapping tests proving values change while source,
  freshness, adjustment, and evidence metadata remain unchanged.
- Identity fixtures covering duplicate tickers, share classes, historical
  symbols, ADR/local listings, and US/China/Hong Kong MICs.
- Time fixtures covering daylight-saving gaps/folds, UTC boundaries, invalid
  civil values, and midday-break session labels.
- Observation fixtures covering stale, delayed, missing, restated, raw, and
  adjusted data.

Core tests use local deterministic values. They must not import
`finance_testkit`, call a provider, or contain licensed market datasets.

## Distribution and compatibility

The package is source-only on Hex and targets Gleam `>= 1.18.0` on JavaScript.
It has no `pi_gleam` dependency. Before its first release, path dependencies
must be absent, exported tarball contents audited, and public JSON fixtures
versioned. Breaking a canonical representation requires a major version once
stable; adding a preserved `Other` case or new constructor follows the normal
Gleam compatibility policy.

## Acceptance criteria

- Decimal operations never lose precision through JavaScript `Number`.
- At least US, mainland China, and Hong Kong listings fit without market-specific
  escape hatches.
- Ambiguous symbols remain ambiguous in tests.
- Observation JSON round-trips all provenance and freshness labels.
- No finance-package dependency cycle exists.
- Formatting, warnings-as-errors build, unit tests, and Hex tarball audit pass.

## Open decisions

- Maximum coefficient digits and scale for denial-of-service resistance.
- Whether timezone conversion belongs in 0.1 or waits for
  `finance_calendar`.
- Exact canonical JSON field names and version marker.
- Which identifier checksum validations are safe to enforce without rejecting
  legitimate provider-specific values.
