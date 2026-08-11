# pi_sparkles_hk_stock_corporate_actions

Status: **Designing** · HK source contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 33](../../../trading-course/sessions/33_hk_stock_track_completion_contract_20260811.md), with source/date laws from Sessions 11 and 20.

## Reviewed first slice

The plugin returns exact HKEX cash/stock dividends, splits/consolidations, rights issues and bonus issues for one resolved XHKG listing. Facts retain announcement/action identity, type, terms/ratio, currency, announcement/ex/record/payment/effective dates as distinct fields, entitlement conditions, source-language title/document, corrections, rights and receipts.

Identity must include exact listing/share class and may not default currency to HKD. Conflicting notices and revised timetables remain separate with lineage. A pure HK core validates dates/terms; bounded HKEX acquisition is isolated from CN/US domains.

## Gates and exclusions

Requires HKEX source/rights review. No price-series adjustment, inferred effective date, issuer-wide merge, A/H comparison, action impact, recommendation, or trading decision.
