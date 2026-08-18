# us_quote

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`us_quote` registers `us_stock_quote`, a credentialed read-only tool for one
latest Alpaca US stock best bid and ask. The caller must provide an exact
uppercase symbol and choose `iex` or `sip`; the plugin never selects or falls
back between feeds.

Required environment variables:

- `ALPACA_API_KEY_ID`
- `ALPACA_API_SECRET_KEY`
- `AGENT_CONTACT` (shared non-secret operator identity)

The plugin supplies its fixed outbound product label.

The tool preserves exact provider JSON tokens for bid/ask prices and sizes,
along with provider time, exchange codes, condition codes, tape, selected feed,
request ID, and source reference. When Alpaca reports a blank exchange with
zero price and size for one currently unavailable side, the result keeps that
provider sentinel separately and returns `null` for the absent side; it never
presents the zero as a tradable quote. Blank exchanges with non-zero facts fail
closed. The tool reports size units as
`provider_reported_unverified`, freshness and latency as unknown, and grants no
redistribution right. IEX is not consolidated SIP coverage; SIP availability
and recency depend on the credential holder's subscription.

Provider references:

- <https://docs.alpaca.markets/us/reference/stocklatestquotes-1>
- <https://docs.alpaca.markets/us/docs/real-time-stock-pricing-data>
- <https://docs.alpaca.markets/us/docs/market-data-faq>

Normal tests use fixtures and mocked fetch only. The plugin does not resolve
company names, prove listing identity, infer session state, calculate spreads,
normalize provider size semantics, cache results, or claim real-time coverage.
