# finance_market_alpaca

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_market_alpaca` is a credentialed, read-only adapter for Alpaca's US
historical stock-bars, latest stock-quotes, asset-master, and current v1
corporate-actions endpoints. The bars
slice supports one exact symbol, `1Day`, ascending order, USD prices, and `raw`
adjustment only. The quote slice supports one exact symbol, USD, and an explicit
feed. The asset slice exposes provider rows for one caller-selected paper/live
environment, status filter, and exchange with `asset_class=us_equity`.

The bars and quote contracts require an explicit `iex` or `sip` feed. Bars require a symbol
`asof` date. It bounds each page to 1,000 bars, the workflow to 5,000 bars and
10 pages, responses to 5 MB, requests to 15 seconds, concurrency to two, and a
conservative 180 admissions per minute. A quote response is capped at 250 KB
and 10 seconds. An asset response is capped at 15 MB and 20,000 rows; over-budget
arrays fail rather than truncate. Pagination tokens are followed only by
the Pi shell under those caller-visible budgets. Authentication headers are
marked secret and are excluded from safe request identities and results.

The decoders capture JSON numeric tokens through the runtime's standardized
`JSON.parse` source context, preserving the exact provider lexemes for open,
high, low, close, volume, trade count, and VWAP. It validates the requested
symbol key, page bound, timestamp/date range, and non-decreasing provider order.
The quote decoder additionally retains bid/ask exchanges, conditions, tape, and
exact provider-reported sizes without asserting a size unit.
The asset decoder retains provider order, duplicates, ID, class, exchange,
symbol, name, status, capability booleans, and attributes. It does not discard a
returned row merely because its fields differ from the requested filters; both
the request and exact row remain available to the LLM.
Normal tests use fixed response strings and injected transports; they never use
live credentials or network calls.

The corporate-actions slice requires an exact symbol plus CUSIP, explicit
process-date range, data-quality policy, requested action types, and page/action
budgets. It supports only cash/stock dividends, forward/reverse splits, and
name changes. It preserves exact numeric tokens and nullable fields, rejects an
unrequested or unsupported returned action group, and does not treat `process_date` as an ex-date,
effective date, announcement time, or correction time. Alpaca warns that action
creation can be delayed; successful retrieval is not a completeness claim.

Provider decision for the initial US OHLCV slice:

- endpoint: <https://docs.alpaca.markets/us/reference/stockbars>;
- corporate-actions endpoint:
  <https://docs.alpaca.markets/us/reference/corporateactions-1>;
- asset endpoint: <https://docs.alpaca.markets/us/reference/get-v2-assets-1>;
- feed scope: IEX is exchange-specific and SIP is consolidated US-exchange
  coverage; they are never presented as equivalent;
- subscription: access, recency, and rate limits depend on the user's Alpaca
  plan and a successful response proves only that request's entitlement;
- rights: credentials confer no redistribution grant to this repository or its
  users, so outputs are for the credential holder's permitted use and retain a
  no-redistribution assumption;
- identity: the exact symbol plus required `asof` date is an Alpaca mapping key,
  not an authoritative listing/security master;
- asset scope: the asset master is an Alpaca provider catalogue, supplies no
  historical as-of query parameter, and its status/capability flags remain
  provider facts rather than eligibility, ranking, or action decisions;
- adjustment: raw only; splits, dividends, spin-offs, and combined provider
  adjustments remain later contracts.

The focused suite has 13 passing tests. This package does not import Pi, choose
a default feed or trading environment, cache data, fall back between origins,
classify absent sessions, infer a primary listing venue, rank an asset, or claim
real-time coverage.
