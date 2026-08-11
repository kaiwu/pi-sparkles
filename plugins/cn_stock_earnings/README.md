# pi_sparkles_cn_stock_earnings

Status: **Designing** · CN event-information contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 30](../../../trading-course/sessions/30_filing_earnings_company_intelligence_contract_20260811.md).

## Reviewed first slice

Tools inspect 业绩预告 and 业绩快报, list exact CN result events, build an issuer-period timeline, and list relevant board-meeting dates. Event classes remain distinct: forecast, express report, periodic report, correction/revision, and meeting notification.

Facts retain exact `cn` issuer/listing identity, Chinese event type/title/text, metric/range/change basis as disclosed, report period, event/publication/retrieval/meeting dates, source document, correction ancestry, scope, unknowns and receipts. Timeline alignment never treats one event class as another or fills an absent publication date.

The CN core composes CN document/accounting types and cannot import US/HK domains. Source effects use bounded CNINFO/exchange adapters.

## Explicit exclusions

No equivalence to US guidance/releases, automatic forecast-versus-actual judgment, earnings quality/surprise/materiality interpretation, sentiment, recommendation, or trade action.
