# finance_fred

`finance_fred` is an **Experimental**, reusable Gleam adapter for the Federal
Reserve Bank of St. Louis FRED API v1. It is not a Pi plugin and never imports
Pi.

The first slice deliberately supports only two exact read-only endpoints:

- [`fred/series`](https://fred.stlouisfed.org/docs/api/fred/series.html) for
  one series' metadata;
- [`fred/series/observations`](https://fred.stlouisfed.org/docs/api/fred/series_observations.html)
  for one bounded observation range.

Every request requires the caller's 32-character lowercase
[`api_key`](https://fred.stlouisfed.org/docs/api/api_key.html). The adapter marks
that query parameter secret and never puts it in a source reference or result.

## Contract

- `series_id`, observation bounds, point-in-time `as_of_date`, and the hard
  observation cap are explicit.
- `realtime_start` and `realtime_end` both equal `as_of_date`. FRED defines
  this realtime period as what was known on that date.
- Observations request `units=lin`, `output_type=1`, `sort_order=asc`, and no
  frequency aggregation.
- Metadata and observation envelopes must echo the exact request semantics.
- Observation dates must be canonical, strictly increasing, and inside the
  requested range. Numeric strings and the FRED missing marker `.` are retained
  verbatim.
- If FRED's `count` exceeds `maximum_observations`, decoding fails with
  `Truncated`; callers cannot mistake a bounded prefix for the complete range.
- Responses are capped at 250 KB for metadata and 2 MB for observations with a
  15-second request timeout, cancellation, retries, a two-request-per-second
  local pacing ceiling, one in-flight request, and exact host/path allowlisting.

The v1 error documentation lists `400`, `404`, `423`, `429`, and `500` and
states that rate limiting can return an error status. The local two-per-second
ceiling is deliberately conservative; it is not presented as a published v1
entitlement.

FRED can redistribute series owned by third parties. Consumers must retain the
series metadata and follow the [FRED API Terms of Use](https://fred.stlouisfed.org/docs/api/terms_of_use.html)
and any series-specific rights. This package authenticates the caller's API
request; a copied body hash is not a provider signature.

No search, ALFRED vintage comparison, transformation, frequency aggregation,
release calendar, forecasting, caching, or economic interpretation is in this
slice.

```sh
cd finance/finance_fred
gleam test
```
