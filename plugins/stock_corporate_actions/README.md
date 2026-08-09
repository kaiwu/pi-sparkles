# stock_corporate_actions

Experimental Pi plugin for bounded, read-only US corporate-action source facts
from Alpaca's current `GET /v1/corporate-actions` endpoint.

The plugin registers one tool, `corporate_actions`. Callers must provide exact
`track=us`, caller-declared `venue=XNYS|XNAS`, uppercase symbol, nine-character
CUSIP, inclusive Alpaca `process_date` range, unique action types, explicit
`dataQuality=complete|all`, and page/action budgets. There is no market, venue,
identity, or action-type fallback.

The implemented slice is deliberately limited to:

- cash dividends;
- stock dividends;
- forward splits;
- reverse splits; and
- name changes, including the source old/new symbol and CUSIP fields.

Every page retains its sequence, optional Alpaca request ID, response byte
length, SHA-256 body digest, exact source rows, duplicates, and pagination
token. JSON number tokens used for rates remain exact strings such as
`0.2400`; nullable or missing fields remain unknown. An empty source currency
is retained and is never silently treated as USD.

The symbol/CUSIP query is correlated against each returned row. Single-identity
actions must either match exactly or omit the field. Reverse splits and name
changes may match the requested identity on either side of the transition;
both sides remain visible. A populated transition with no exact match fails
closed. The caller's XNYS/XNAS value remains explicitly unverified because this
endpoint does not establish venue identity.

`startDate` and `endDate` filter Alpaca's processing date. They are not
announcement, publication, ex, record, payable, correction, or effective-date
claims. The plugin performs no price adjustment, entitlement calculation,
distribution interpretation, completeness inference, or economic-impact
analysis. Alpaca documents that data-provider and processing delays can defer
availability. Its `complete` policy can also return already-processed records
that still have missing fields. See the official
[Corporate actions API reference](https://docs.alpaca.markets/us/reference/corporateactions-1).

## Configuration

- `ALPACA_API_KEY_ID` (required)
- `ALPACA_API_SECRET_KEY` (required)
- `ALPACA_USER_AGENT_CONTACT` (required)
- `ALPACA_USER_AGENT_PRODUCT` (optional; defaults to
  `pi-sparkles-stock-corporate-actions/0.1`)

Credentials are secret request headers and are not emitted in results or safe
request identities. The shared Alpaca runtime enforces the exact data origin,
15-second request timeout, 5 MB response limit, rate limiting, bounded
concurrency, retries, and cancellation.

## Verification

```sh
cd plugins/stock_corporate_actions
gleam test --target javascript

cd ../..
bun run build -- stock_corporate_actions
bun test test/binding/stock_corporate_actions.test.js
bun run test:architecture
```

Tests use scripted fixtures only; they do not call Alpaca live.

Verified on 2026-08-09: 13 `finance_market_alpaca` tests, 6 plugin tests, 6
bundled boundary scenarios, artifact export, all 11 architecture checks,
installed-Pi loading, and full `bun run test` passed.
