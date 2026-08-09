# finance_twelve_data

`finance_twelve_data` is an **Experimental**, Pi-independent adapter for two
read-only Twelve Data company endpoints. It uses `finance_http` for bounded,
cancellable transport and keeps the caller's API key in a secret
`Authorization` header.

## Implemented contract

The adapter supports only exact US listing requests on `XNYS`, `XNAS`, `XNGS`,
`XNCM`, or `XNMS` and always sends the requested `symbol`, `mic_code`, and
`country=US` without fallback:

| Endpoint | Response bound | Purpose | Documented API credits |
| --- | ---: | --- | ---: |
| `/profile` | 500 KB | Listing identity, description, classification, CEO, employees, and contact fields | 10 |
| `/statistics` | 1 MB | MIC-tagged shares outstanding and float shares | 50 |

The response decoders preserve employee and share-count JSON numbers as exact
source lexemes and accept documented nullable fields. Fractional or negative
counts fail decoding. Requests are serialized and never retried automatically,
so a transient failure cannot silently spend another 10 or 50 credits.

The provider responses are current snapshots. They do not provide field-level
effective dates, classification taxonomy/version, CEO appointment dates, share
measurement dates, or primary-exchange/issuer authority. Consumers must retain
those omissions and must not turn a matching MIC into exchange proof.

The profile endpoint requires a Twelve Data Grow individual or Venture business
plan or above. The statistics endpoint requires Pro individual or Venture
business or above. Access, redistribution, and entitlement remain governed by
the caller's Twelve Data subscription.

## Sources

- <https://twelvedata.com/docs#profile>
- <https://twelvedata.com/docs#statistics>
- <https://twelvedata.com/docs#errors>
- <https://support.twelvedata.com/en/articles/5615854-credits>

Tests use provider-shaped local fixtures and scripted transport only. They make
no live requests and consume no provider credits.
