# finance_openfigi

Experimental reusable OpenFIGI v3 adapter for Gleam finance applications. It
contains no Pi imports and can be used by Pi plugins, command-line programs, or
other JavaScript-target Gleam applications.

## Scope

The package provides:

- opaque anonymous or API-key access configuration;
- validated mapping jobs for ticker, FIGI, composite FIGI, ISIN, CUSIP, and
  SEDOL identifiers;
- validated search queries with optional MIC and explicit pagination cursors;
- v3 request construction with ten-second/500 KB bounds and retry-safe request
  identity;
- nullable v3 response decoding into immutable candidates and result sets;
- conservative anonymous/authenticated mapping and search rate profiles;
- a shared runtime that admits every HTTP attempt through the appropriate rate
  bucket and a one-request/100-waiter concurrency pool;
- cancellation, `Retry-After`, bounded exponential retry, and safe failures via
  `finance_http`.

The implementation uses `/v3/mapping` and `/v3/filter`. Official contracts and
terms are documented at <https://www.openfigi.com/api/documentation> and
<https://www.openfigi.com/docs/terms-of-service>.

## Functional architecture

Mapping jobs, search/pagination plans, access policy, limits, request encoding,
response decoding, and rate-state construction are pure immutable
transformations. The only mutable values are two generic runtime cells holding
the latest immutable `finance_http.rate_limit.State` values.

```text
Access + typed request plan
       -> bounded finance_http.Request with secret-labelled header
       -> shared concurrency pool
       -> endpoint-specific immutable rate transition
       -> cancellable transport/retry interpreter
       -> raw bounded response
       -> pure v3 ResultSet decoder
```

The gated sender sits below retry logic, so a retry consumes another provider
request token. Mapping and filter/search use separate buckets. Cell read/write
FFI is mechanical; it contains no provider rules.

## Authentication and secrecy

`authenticated(key)` validates and seals the key in an opaque `Access` value.
`authorize` applies it as a `Secret` `X-OPENFIGI-APIKEY` request header only at
the transport boundary. Safe request keys, typed failures, and tool results do
not include its value. Applications should obtain the key from a secret store
or environment boundary; this package never reads ambient configuration itself.

Anonymous access remains a first-class configuration. The runtime currently
uses the conservative documented profiles:

| Endpoint | Anonymous | Authenticated |
| --- | --- | --- |
| Mapping | 25 requests/minute, 5 jobs/request | 25 requests/6 seconds, 100 jobs/request |
| Filter/search | 5 requests/minute | 20 requests/minute |

Provider response headers and `Retry-After` remain authoritative for individual
failures. Dynamic reconciliation of `ratelimit-remaining` and `ratelimit-reset`
headers is a future refinement.

## Pagination and identity ceilings

Search does not hide pagination. `search.next(query, result)` returns a new
immutable query only when the provider supplied a valid cursor. Applications
choose their own page/result budgets; automatic unbounded traversal is not
offered.

OpenFIGI identifies instruments but does not provide CIK crosswalks, complete
historical ticker intervals, authoritative MIC/currency fields for every
candidate, prices, or trading entitlement. Responses do not provide an as-of
timestamp, so consumers must preserve unknown reference-data freshness.

FIGI identifiers are public-domain under the provider terms; do not assume all
returned descriptive metadata has the same redistribution status. This adapter
does not cache or persist provider responses.

## Testing and status

Tests use documented synthetic/IBM-shaped fixtures and never make live calls.
They cover access validation, secret-labelled headers, safe request identity,
endpoint-specific rate profiles, batch limits, nullable decoding, pagination,
and runtime construction. The package is Experimental and uses local path
dependencies during monorepo development.
