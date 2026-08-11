# pi_sparkles_cn_ipo

Status: **Designing** · provider/source gated · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 32](../../../trading-course/sessions/32_cn_ipo_information_contract_20260811.md).

## Reviewed first slice

Tools query a bounded mainland IPO pipeline/calendar, search exact issuer candidates, inspect one company, inspect/retrieve bounded document metadata/content, and calculate requested dilution over supplied offer facts. Identity binds issuer/organization, application/listing codes, venue/board, security/share class, sponsor/accountant/law firm and alias history.

Pipeline is append-only state events with source, publication/effective/retrieval dates and corrections—not an overwritten status. Prospectus/inquiry/registration/offer/listing documents retain original Chinese, version and attachment receipts. Offer facts preserve price/range, quantities, old/new shares, greenshoe, allocations, lockups and unknowns. Dilution formulas expose all leaves and never infer missing terms.

Pure modules own identity, state ordering, calendars and calculations; network/document effects use bounded `finance_http` and reviewed attachment contracts.

## Gates and exclusions

Requires reviewed CSRC/SSE/SZSE/BSE/CNINFO source and rights contracts. No subscription/account/order effect, allocation probability, eligibility judgment, IPO valuation, fair price, post-listing forecast, recommendation, or cross-market substitution.
