# us_ohlcv_gaps

Experimental, network-free Pi plugin for the isolated `us` track. It registers
`us_ohlcv_gap_assessment`, a strict compositor for copied `us_stock_ohlcv`
receipt fields plus exact listing and market-status evidence.

The tool requires:

- exact NYSE/XNYS or Nasdaq/XNAS identity and a namespaced instrument ID;
- a listing start/end interval and evidence reference;
- a range within the source-reviewed 2026 venue calendar;
- the exact Alpaca symbol, IEX/SIP feed, identity-as-of date, source reference,
  request IDs, pagination state, and ordered bar session dates; and
- an ordered `trading` or `suspended` status receipt for every absent open date
  on which the listing was effective.

The Alpaca source reference must match the canonical raw daily-bars plan. Only
complete pagination can produce an assessment. Planned closures come from the
local official calendar; pre/post-listing open dates become unavailable
history; an explicit suspension becomes a suspension; and an explicit trading
status plus complete provider coverage becomes a provider omission. Conflicts
or missing evidence reject the entire request.

The plugin performs no environment lookup and no runtime network request.
Copied receipt integrity, listing evidence, and status evidence are not
cryptographically or authority verified, and the result says so. The tool does
not change the original Alpaca batch, synthesize bars, assess adjustments, or
grant redistribution rights.

Build and test with:

```sh
bun run test:unit -- us_ohlcv_gaps
bun run build -- us_ohlcv_gaps
```
