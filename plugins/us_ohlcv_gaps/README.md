# us_ohlcv_gaps

Experimental, network-free Pi plugin for the isolated `us` track. It registers
`us_ohlcv_gap_assessment`, a strict compositor for copied `us_stock_ohlcv`
receipt fields plus exact listing and market-status evidence.

The tool requires:

- exact NYSE/XNYS or Nasdaq/XNAS identity and a namespaced instrument ID;
- a listing start/end interval and evidence reference;
- a range within the source-reviewed 2026 venue calendar;
- the exact versioned `gapAssessmentReceipt` emitted by `us_stock_ohlcv`,
  including provider plan identity, retrieval time, pagination, ordered bar
  dates, page byte lengths/request IDs/body SHA-256 values, and canonical
  receipt SHA-256; and
- an ordered `trading` or `suspended` status receipt for every absent open date
  on which the listing was effective.

The Alpaca source reference must match the canonical raw daily-bars plan. Only
complete pagination can produce an assessment. Planned closures come from the
local official calendar; pre/post-listing open dates become unavailable
history; an explicit suspension becomes a suspension; and an explicit trading
status plus complete provider coverage becomes a provider omission. Conflicts
or missing evidence reject the entire request.

The plugin performs no environment lookup and no runtime network request. It
reconstructs the canonical receipt and requires an exact SHA-256 match before
classification, so copy changes fail closed. This proves content coherence,
not provider origin: the digest is not an Alpaca signature, and listing/status
evidence remains caller supplied and not authority verified. The tool does not
change the original Alpaca batch, synthesize bars, assess adjustments, or grant
redistribution rights.

Build and test with:

```sh
bun run test:unit -- us_ohlcv_gaps
bun run build -- us_ohlcv_gaps
```
