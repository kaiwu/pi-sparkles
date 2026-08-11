# pi_sparkles_cn_stock_margin

Status: **Designing** · exchange-information contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Return dated financing/securities-lending eligibility, balances, purchases, repayments, sales and market aggregates for an exact CN listing or venue scope. Facts retain scope, field label, exact value/unit/scale, observation/publication/retrieval dates, eligibility effective interval, source, corrections and receipts.

Financing and securities-lending legs remain distinct. Venue aggregates cannot be attributed to a listing, and balance changes do not reveal investor intent. Missing days/fields stay unavailable without interpolation.

## Explicit exclusions

No leverage/sentiment/short-interest interpretation, completeness claim, account eligibility, recommendation, or trade action.
