# pi_sparkles_cn_stock_connect

Status: **Designing** · CN-side source contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Return mainland-side Stock Connect listing eligibility, buy-only/sell-only/ineligible/unknown state, effective dates, calendars and published quota facts for exact SSE/SZSE listing identities. Preserve program/direction, source authority, publication/retrieval times, changes/corrections, coverage and receipts.

The CN leg remains independent of `pi_hk_stock_connect`; no shared mutable state or cross-track relabelling occurs. Eligibility cannot be inferred from index membership, ticker or historical state, and broker/account permission is separate.

## Explicit exclusions

No order eligibility guarantee, quota forecast, preferred market/share class, A/H comparison, recommendation, or execution.
