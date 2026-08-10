# stock_quote

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`stock_quote` is the provider-neutral Pi boundary for inspecting one exact
best-bid-and-ask observation on the `cn`, `hk`, or `us` track. It accepts facts
already produced by a caller or provider adapter and constructs the canonical
`finance_core.Observation(finance_quote.Quote)` without making a network
request.

The `stock_quote` tool requires:

- one explicit track and first-slice listing MIC (`XSHG`, `XSHE`, or `XBSE` for
  `cn`; `XHKG` for `hk`; `XNYS` or `XNAS` for `us`);
- exact listing ID and provider symbol;
- exact source lexemes for bid/ask prices and sizes, provider timestamp,
  as-of/retrieval instants, currency, exchange/condition/tape codes, and the
  provider's unverified size unit;
- exact provider, feed, source kind/reference, declared entitlement and licence;
  and
- one caller-supplied SHA-256 source receipt.

The result retains the raw and normalized decimal forms. Explicit delayed,
real-time, end-of-day, or unknown entitlement survives in the canonical
observation, and its source receipt becomes the observation evidence ID.
Entitlement, licence, listing identity, and receipt binding remain declared and
unverified; a matching hash is not origin authentication or a redistribution
grant. Source URLs are structurally redacted before they are returned.

Freshness, latency, session, listing authority, provider size semantics, and
locked/crossed interpretation remain unknown. The first slice deliberately has
one observation and performs no conflict reconciliation. It also performs no
provider selection, fallback, fetching, caching, persistence, quote merging,
spread calculation, signal, ranking, recommendation, or trade action.

Provider acquisition remains in track/provider-specific adapters such as
`us_quote`; those adapters may feed this tool only by explicitly preserving
their own entitlement, licence, source, and receipt facts.
