# finance_news

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Experimental Pi plugin for bounded, read-only US vendor-news metadata from
Alpaca's current `GET /v1beta1/news` endpoint. Alpaca states that the historical
feed currently comes directly from Benzinga and dates back to 2015.

The plugin registers one tool, `finance_news`. Callers must provide exact
`track=us`, caller-declared `venue=XNYS|XNAS`, one uppercase Alpaca symbol, an
inclusive RFC3339 UTC interval no wider than 31 days, and page/article budgets.
There is no track, venue, provider, symbol, or time fallback.

The first slice returns metadata only:

- Alpaca article ID;
- exact headline and author;
- exact `created_at` and `updated_at` lexemes;
- canonical article URL;
- every provider-associated symbol and the exact `source=benzinga` value;
- whether summary/content/image material existed, without returning that
  material; and
- page sequence, optional request ID, byte length, SHA-256 body digest, and
  pagination token.

Requests explicitly send `include_content=false`, `exclude_contentless=false`,
and `sort=asc`. Returned records must retain the queried symbol association and
ascending `updated_at`; source drift from `benzinga`, malformed time, unknown
response fields, repeated pagination tokens, and budget violations fail closed.
Repeated article IDs are preserved rather than silently deduplicated.

`created_at` and `updated_at` are provider article timestamps. An update time is
not correction or revision lineage. Alpaca documents inclusive `start`/`end`
bounds and sorting by updated date, but the reference does not explicitly name
the interval filter axis, so the plugin does not invent one. A provider symbol
association does not establish issuer, listing, MIC, asset class, or venue
identity. A headline is not an issuer notice, scheduled event, verified fact,
or model-inferred catalyst.

The tool performs no article-body or summary redistribution, deduplication,
clustering, sentiment, impact scoring, event verification, catalyst
classification, absence inference, recommendation, or next-action selection.
Alpaca's terms limit ordinary content use to personal, noncommercial use and
require express prior written consent for redistribution; callers remain
responsible for their actual account agreement and intended use.

Official evidence:

- [News API reference](https://docs.alpaca.markets/us/reference/news-3)
- [Historical news source and coverage](https://docs.alpaca.markets/us/docs/historical-news-data)
- [Alpaca terms and conditions](https://files.alpaca.markets/disclosures/alpaca_terms_and_conditions.pdf)

## Configuration

- `ALPACA_API_KEY_ID` (required)
- `ALPACA_API_SECRET_KEY` (required)
- `AGENT_CONTACT` (required shared non-secret operator identity)

The plugin supplies its fixed outbound product label.

Credentials remain secret request headers. The shared Alpaca runtime enforces
the exact origin and path, 15-second request timeout, 2 MB response limit,
rate limiting, bounded concurrency, retries, and cancellation.

## Verification

```sh
cd plugins/finance_news
gleam test --target javascript

cd ../..
bun run build -- finance_news
bun test test/binding/finance_news.test.js
bun run test:architecture
bun run test:artifacts
bun run test:pi -- finance_news
bun run test
```

Verified on 2026-08-09: 17 adapter tests, 4 pure plugin tests, 6 bundled
boundary scenarios, architecture, artifact, installed-Pi, and full repository
regression gates pass. Tests use scripted fixtures only and never call Alpaca
live.
