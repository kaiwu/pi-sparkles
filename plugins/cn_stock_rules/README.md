# pi_sparkles_cn_stock_rules

Status: **Designing** · dated rule-information contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md) and the existing `cn_market_rules` slice.

## Reviewed first slice

Return the exact effective rule profile for a caller-proven SSE/SZSE/BSE listing, board, share/security class, status and date. The first slice projects reviewed standard CNY A-share tick, lot/quantity, odd-lot exit and ordinary price-limit facts, with source authority/reference, publication/effective interval, version, exceptions, conflicts and receipts.

Caller declarations do not verify listing/status. Unknown ST/delisting/IPO/suspension or exceptional regimes fail closed rather than falling back to the standard profile. CN rule code cannot import HK/US domains.

## Explicit exclusions

No universal China default, order-validity/compliance verdict, current-status inference, settlement/execution effect, recommendation, or claim that the bounded profile covers every regime.
