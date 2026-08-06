# finance_market_alpaca

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_market_alpaca` is a credentialed, read-only adapter for Alpaca's US
historical stock-bars and latest stock-quotes endpoints. The bars slice supports
one exact symbol, `1Day`, ascending order, USD prices, and `raw` adjustment
only. The quote slice supports one exact symbol, USD, and an explicit feed.

Both request contracts require an explicit `iex` or `sip` feed. Bars require a symbol
`asof` date. It bounds each page to 1,000 bars, the workflow to 5,000 bars and
10 pages, responses to 5 MB, requests to 15 seconds, concurrency to two, and a
conservative 180 admissions per minute. A quote response is capped at 250 KB
and 10 seconds. Pagination tokens are followed only by
the Pi shell under those caller-visible budgets. Authentication headers are
marked secret and are excluded from safe request identities and results.

The decoders capture JSON numeric tokens through the runtime's standardized
`JSON.parse` source context, preserving the exact provider lexemes for open,
high, low, close, volume, trade count, and VWAP. It validates the requested
symbol key, page bound, timestamp/date range, and non-decreasing provider order.
The quote decoder additionally retains bid/ask exchanges, conditions, tape, and
exact provider-reported sizes without asserting a size unit.
Normal tests use fixed response strings and injected transports; they never use
live credentials or network calls.

Provider decision for the initial US OHLCV slice:

- endpoint: <https://docs.alpaca.markets/us/reference/stockbars>;
- feed scope: IEX is exchange-specific and SIP is consolidated US-exchange
  coverage; they are never presented as equivalent;
- subscription: access, recency, and rate limits depend on the user's Alpaca
  plan and a successful response proves only that request's entitlement;
- rights: credentials confer no redistribution grant to this repository or its
  users, so outputs are for the credential holder's permitted use and retain a
  no-redistribution assumption;
- identity: the exact symbol plus required `asof` date is an Alpaca mapping key,
  not an authoritative listing/security master;
- adjustment: raw only; splits, dividends, spin-offs, and combined provider
  adjustments remain later contracts.

This package does not import Pi, choose a default feed, cache data, fall back
between feeds, classify absent sessions, infer a primary listing venue, or
claim real-time coverage.
