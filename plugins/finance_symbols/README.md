# pi_sparkles_finance_symbols

Experimental F0 Pi extension for instrument identity. It registers `/symbol`,
`security_search`, `security_resolve`, and `security_identifiers`, backed by the
OpenFIGI v3 API.

## Provider decision

The first adapter uses OpenFIGI because it offers a purpose-built mapping API,
works without credentials at a lower rate limit, preserves FIGI identifiers as
public-domain data, and has a documented v3 response contract. The plugin uses
`https://api.openfigi.com/v3/filter` and `/v3/mapping`; it does not use the
retired v2 API. Official documentation and terms:

- <https://www.openfigi.com/api/documentation>
- <https://www.openfigi.com/docs/terms-of-service>

No generic fetch FFI is duplicated here. The plugin consumes
`finance_openfigi`, whose shared runtime composes `finance_http` bounds,
cancellation, safe request identity, status classification, `Retry-After`,
retry, separate mapping/search rate buckets, and a one-request concurrency
pool. Set `OPENFIGI_API_KEY` for authenticated limits; the key is sealed in an
opaque access value and applied only as a secret header. Without it the same
tools use anonymous access.

## Identity model

OpenFIGI responses decode once into immutable `Candidate` values. A candidate
keeps FIGI, composite FIGI, share-class FIGI, ticker, name, exchange code,
security type, and market sector as distinct fields. In particular, OpenFIGI's
`exchCode` is not mislabeled as an ISO 10383 MIC.

Resolution delegates to `finance_core.identifier.Resolution(a)`:

```text
[]             -> NoMatch
[candidate]    -> Unique(candidate)
[a, b, ..rest] -> Ambiguous(a, b, rest)
```

Candidates are sorted by FIGI before resolution, so results are deterministic
even if provider ordering changes. An ambiguous result is a successful,
actionable domain value—not an exception and never permission to choose the
first ticker. Callers should refine by MIC or a stronger identifier.

## Functional/effect split

`finance_openfigi` owns reusable request planning, v3 decoding, pagination, and
provider execution. The plugin's `symbols.gleam` has only deterministic
candidate ordering, labels, and ambiguity resolution. The root module decodes
Pi inputs directly into provider domain values and interprets the runtime:

```text
typed Pi input
  -> pure request plan
  -> finance_http interpreter
  -> pure response decoder and resolution
  -> structured Pi tool result
```

This makes response parsing, no-match warnings, ordering, and resolution laws
testable offline. Live network calls are excluded from unit tests.

## Interfaces

- `/symbol <ticker>` maps a ticker and displays unique/ambiguous/no-match.
- `security_search` accepts `query`, optional four-character `micCode`, and an
  optional `cursor` returned by a previous page.
- `security_resolve` accepts `idType`, `idValue`, and optional `micCode`.
- `security_identifiers` currently shares the mapping contract and exposes the
  identifiers returned by OpenFIGI.

Supported initial ID types are ticker, FIGI, composite FIGI, ISIN, CUSIP, and
SEDOL. Tool details always report provider, endpoint source, entitlement label,
and the crucial limitation `reference_data_as_of_not_supplied`. Search results
may be paginated; results expose `next` and `total`, and callers explicitly pass
the next cursor. Automatic unbounded traversal is deliberately unsupported.

## Ceilings and next increments

OpenFIGI identifies instruments; it does not supply CIKs, authoritative listing
MIC normalization for every result, historical symbol intervals, market prices,
or trading entitlement. Reference data can change and OpenFIGI does not include
an as-of timestamp in these responses. The plugin therefore must not claim
freshness it cannot prove.

Next work is CIK crosswalking through a reusable SEC adapter, historical aliases,
rate-header reconciliation, caller-selected multi-page budgets, and canonical
`finance_core.Instrument` construction only when required MIC/currency fields
are available.

Local development uses path dependencies on `pi_gleam`, `finance_core`,
`finance_http`, and `finance_openfigi`. Tested against Pi `0.83.0`. Network
access is read-only; Pi
plugins still execute with the user's full process permissions.
