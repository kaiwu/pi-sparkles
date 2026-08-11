# pi_sparkles_cn_stock_quote

Status: **Designing** · thin source slice · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md). The existing `cn_market_data` implementation is the current vendor acquisition substrate.

## Reviewed first slice

Return one bounded Eastmoney quote for a caller-resolved SSE/SZSE/BSE listing. Preserve `cn` track, MIC/board/share class, provider symbol/market code, price/bid/ask/size/volume lexemes and units, provider/exchange/retrieval times, feed/source, entitlement/licence, receipt hash, and unavailable/conflicting states.

Identity is never inferred from a six-digit code. Vendor origin is not exchange authority, latency is unknown unless sourced, and no fallback or currency default occurs. The shell composes the existing provider adapter and canonical quote observations rather than adding local HTTP/retry/cache logic.

## Explicit exclusions

No real-time claim, source selection, best price, stale/fresh verdict, session/status inference, calculated limits, signal, recommendation, or trading action.
