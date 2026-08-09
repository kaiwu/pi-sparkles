# pi_macro_fred

`pi_macro_fred` is an **Experimental** credentialed read-only Pi plugin over
`finance_fred`. It registers one tool:

- `fred_series` — retrieve exact FRED series metadata and one complete bounded
  raw level range as known on an explicit date, then expose the final source row
  and exact `latest - previous` arithmetic.

Set the caller's own key before loading the plugin:

```sh
export FRED_API_KEY=abcdefghijklmnopqrstuvwxyz123456
bun run build -- macro_fred
```

The key must follow FRED v1's documented 32-character lowercase alphanumeric
shape. It is sent only as the secret `api_key` query parameter and never appears
in tool output or stable evidence references.

## Tool semantics

The tool requires `seriesId`, inclusive `observationStart` and
`observationEnd`, exact `asOfDate`, and `maximumObservations` from 1 through
1000. It makes exactly two source requests. A range whose provider `count`
exceeds the cap is rejected rather than returned as a misleading partial range.

Every source row becomes a canonical `finance_core.Observation` envelope. The
FRED civil date maps to UTC midnight only as an ordering anchor; the result says
explicitly that it is not a provider timestamp. Source value lexemes, FRED
units, seasonal-adjustment metadata, point-in-time bounds, retrieval time,
unknown freshness/entitlement, and response-content receipts are retained.

“Latest” means the final source row in that complete requested range. The tool
does not skip a final `.` row. “Change” is an exact `finance_math` formula over
the final two adjacent source rows and is unavailable if either is non-numeric.
It is not percent change, forecast, surprise, trend, recommendation, or market
regime.

This macro source is not itself a `cn`, `hk`, or `us` market observation, so the
result uses `track: null` and never invents a fourth track. Downstream workflows
must label their own separate market legs.

See the official [series endpoint](https://fred.stlouisfed.org/docs/api/fred/series.html),
[observations endpoint](https://fred.stlouisfed.org/docs/api/fred/series_observations.html),
[realtime-period semantics](https://fred.stlouisfed.org/docs/api/fred/realtime_period.html),
and [terms](https://fred.stlouisfed.org/docs/api/terms_of_use.html).
Use of `fred_series` is subject to those FRED API terms; invoking the tool means
the user agrees to follow them and any series-specific rights.
