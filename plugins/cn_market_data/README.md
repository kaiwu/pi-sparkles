# cn_market_data

Experimental isolated `cn` Pi plugin exposing `cn_raw_vendor_quote` and
`cn_raw_vendor_history` over the shared `finance_eastmoney` adapter. The raw
vendor names deliberately remain distinct from the ProductUseful provider-port
tools `cn_stock_quote` and `cn_stock_history`.

The tool requires an exact `sse`, `szse`, or `bse` choice and a six-digit code.
It is scoped to independently proven mainland exchange-listed/CNY identities,
including already-identified ETFs; the Eastmoney response does not prove the
security kind, share class, or currency. Quote prices retain the provider's
integer scale. History is daily, raw, and unadjusted (`fqt=0`), and preserves
exact numeric response lexemes.

Results visibly report Eastmoney as the vendor origin, direct route, provider
timestamp/retrieval time, local-analysis entitlement, unknown latency/service
level/redistribution rights, unverified volume semantics, and every limitation.
They are not exchange observations and do not silently use AKShare as origin,
though the contract follows the same endpoints used by its Eastmoney functions.

Set the shared non-secret `AGENT_CONTACT`; the plugin supplies its product
label. Normal tests never make live requests.

`cn_raw_vendor_history` emits every bounded daily OHLCV row in model-visible
tool content as well as structured result details; the count-only first line is
only a compact display summary. A known exact code needs Eastmoney caller
identity only; neither Tushare symbol search nor CNINFO is required to retrieve
the returned series.

## T1 provider-port migration

The current implementation is the Eastmoney adapter evidence, not the final
provider-selection architecture. During T1, the canonical CN quote/history
port moves behind explicit adapter selection. Eastmoney remains the first
adapter and Tushare Pro supplies the second conformance proof using caller-owned
`TUSHARE_TOKEN` from the runtime or opt-in-test environment. The plugin-facing
identity, observation, receipt, error and cancellation contract remains stable;
provider-specific fields and limitations remain visible. No credential is
bundled or persisted, and no adapter silently falls back to another provider.
