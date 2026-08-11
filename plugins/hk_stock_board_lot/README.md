# pi_sparkles_hk_stock_board_lot

Status: **Designing** · HK rule-source contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 33](../../../trading-course/sessions/33_hk_stock_track_completion_contract_20260811.md), Sessions 11 and 13.

## Reviewed first slice

The plugin returns per-listing HKEX board-lot observations with exact XHKG listing/share-class identity, lot quantity/unit, effective interval, source/rule reference, publication/retrieval times, entitlement, correction lineage, and known/unknown/conflicting state.

Callers may use a uniquely resolved observation as an input to `finance_risk` grid projection. The plugin never infers board lot from symbol, price, issuer or prior value, and never selects among conflicting effective facts. HK rules remain isolated from CN/US domains.

Acceptance covers effective-date boundaries, issuer share classes, changes/corrections, missing/conflicting facts, odd-lot context and canonical receipts.

## Gates and exclusions

Requires an HKEX rule/listing source and usage-rights review. No order-size recommendation, odd-lot execution claim, universal lot default, broker capability, A/H mapping, or trade action.
