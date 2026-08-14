# cn_market_data

Experimental isolated `cn` Pi plugin exposing `cn_raw_vendor_quote` and
`cn_raw_vendor_history` over the shared `finance_eastmoney` adapter. The raw
vendor names deliberately remain distinct from the ProductUseful provider-port
tools `cn_stock_quote` and `cn_stock_history`.

The tools require an exact `sse`, `szse`, or `bse` choice, a six-digit code, and
an explicit/defaulted `instrumentKind`. Current quote is listed-security only;
reviewed benchmark and sector-index codes reject from the quote path locally
without I/O and direct users to `cn_market_overview` or `cn_sector_trends`.
Daily history accepts a reviewed benchmark only with
`instrumentKind=benchmark_index` and a pinned CSI sector only with
`instrumentKind=sector_index`; unreviewed index identities reject locally.
Eastmoney does not prove security kind, share class, currency, or index
authority. History is daily, raw, and unadjusted
(`fqt=0`) and preserves exact numeric response lexemes.

Results visibly report Eastmoney as the vendor origin, direct route, provider
timestamp/retrieval time, local-analysis entitlement, unknown latency/service
level/redistribution rights, unverified volume semantics, and every limitation.
They are not exchange observations and do not silently use AKShare as origin,
though the contract follows the same endpoints used by its Eastmoney functions.

Set the shared non-secret `AGENT_CONTACT`; the plugin supplies its product
label. Normal tests never make live requests.

`cn_raw_vendor_history` emits every bounded daily OHLCV row in model-visible
tool content as well as structured result details; the count-only first line is
only a compact display summary. Its result contains declarative evidence
boundaries rather than instructions to the model, and each receipt digest is
emitted once. Current overall-market requests belong to the batched
`cn_market_overview` acquisition route.
Broad industry-sector comparisons belong to `cn_sector_trends`; callers should
not guess 申万 or Eastmoney board codes through the single-series history tool.

## T1 provider-port migration

The current implementation is the Eastmoney adapter evidence, not the final
provider-selection architecture. During T1, the canonical CN quote/history
port moves behind explicit adapter selection. Eastmoney remains the first
adapter and Tushare Pro supplies the second conformance proof using caller-owned
`TUSHARE_TOKEN` from the runtime or opt-in-test environment. The plugin-facing
identity, observation, receipt, error and cancellation contract remains stable;
provider-specific fields and limitations remain visible. No credential is
bundled or persisted, and no adapter silently falls back to another provider.
