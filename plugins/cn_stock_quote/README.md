# pi_sparkles_cn_stock_quote

Status: **Implemented in ProductUseful T1** · provider-adaptable source product

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md). The existing `cn_market_data` implementation is the current vendor acquisition substrate.

## T1 provider contract

Return one bounded quote for a caller-resolved SSE/SZSE/BSE listing through an
explicitly selected provider adapter. Eastmoney is the working first adapter;
Tushare Pro is the second mainstream adapter/conformance proof. Preserve `cn`
track, MIC/board/share class, provider symbol/market code, price/bid/ask/size/
volume lexemes and units, provider/exchange/retrieval times, feed/source,
entitlement/licence, receipt hash, and unavailable/conflicting states.

The plugin-facing request/result and canonical provider port do not change by
provider. Each adapter owns request planning, decoding, pacing, cancellation and
source-specific limitations, then must pass the same conformance vectors.
Eastmoney uses the shared `AGENT_CONTACT` and a fixed plugin product label;
Tushare Pro reads caller-owned `TUSHARE_TOKEN`
only from the runtime or opt-in-test environment. Credentials never enter
fixtures, results, logs or persisted state.

Identity is never inferred from a six-digit code. Vendor origin is not exchange
authority, latency is unknown unless sourced, and no fallback or currency
default occurs. An unavailable selected adapter fails explicitly; it never
silently calls another provider.

The implemented tool uses one stable dated price-snapshot schema and explicit
`provider: eastmoney | tushare` selection. It requires an exact venue, A-share
context, upstream identity-evidence reference, and `asOfDate`. Eastmoney is
labelled `vendor_quote_snapshot` and its provider Unix timestamp must resolve to
that Shanghai date. Tushare's `daily` row is deliberately labelled
`end_of_day_daily_bar_snapshot`; it is never presented as a real-time quote.
Both preserve raw prices, response content SHA-256, retrieval time, unavailable
bid/ask, and provider-specific volume/amount semantics. An empty, multiple, or
wrong-date observation fails closed.

Successful schema-validated responses are also recorded through the shared
bounded cache contract with a redacted request identity, provider rights and an
explicit expiry. Cache persistence never changes provider selection, result
semantics, or fallback behavior.

## Explicit exclusions

No real-time claim, automatic source selection, best price, stale/fresh verdict,
session/status inference, calculated limits, signal, recommendation, or trading
action. Supporting more providers is focused adapter work, not a T1 blocker or
another swing-product journey.
