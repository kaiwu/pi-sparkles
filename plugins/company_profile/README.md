# company_profile

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

`company_profile` is an **Experimental**, read-only US source plugin. It
registers one tool, `company_profile`, over the current Twelve Data `/profile`
and `/statistics` endpoints.

The caller supplies one uppercase symbol and one exact MIC. The first slice is
limited to `XNYS`, `XNAS`, and the Nasdaq segment MICs `XNGS`, `XNCM`, and
`XNMS`. The plugin sends both values to both provider requests, validates the
profile before spending the statistics endpoint's higher API-credit cost, then
requires symbol, MIC, name, and exchange to agree across both responses. It
never falls back to another listing or rewrites a segment MIC into `XNAS`.

Returned raw facts include:

- provider listing name, exchange, MIC, security type, description, sector,
  industry, employee count, website, contact fields, and CEO;
- exact source lexemes for shares outstanding and float shares;
- a canonical `us` track context and two canonical observation envelopes;
- response byte lengths, SHA-256 content bindings, and available Twelve Data
  API-credit headers.

Twelve Data supplies current snapshots rather than field-level effective dates.
The result therefore states that classification taxonomy/version, description
effective date, CEO appointment date, and share measurement date are unknown.
Its provider identity match is not exchange or issuer authority proof. It makes
no quality rating, peer selection, dossier sufficiency decision, or investment
judgment.

## Configuration

Set `TWELVE_DATA_API_KEY` to the caller's own credential. Current Twelve Data
documentation prices `/profile` at 10 API credits and requires Grow individual
or Venture business access or above. `/statistics` costs 50 credits and requires
Pro individual or Venture business access or above. Requests are serialized and
are not automatically retried.

All tests use local provider-shaped fixtures. The normal test suite makes no
live requests and consumes no Twelve Data credits.
