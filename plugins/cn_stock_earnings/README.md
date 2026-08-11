# pi_sparkles_cn_stock_earnings

Status: **Implemented in ProductUseful T1** · CN event-information contract

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 30](../../../trading-course/sessions/30_filing_earnings_company_intelligence_contract_20260811.md).

## Reviewed first slice

Tools inspect 业绩预告 and 业绩快报, list exact CN result events, build an issuer-period timeline, and list relevant board-meeting dates. Event classes remain distinct: forecast, express report, periodic report, correction/revision, and meeting notification.

Facts retain exact `cn` issuer/listing identity, Chinese event type/title/text, metric/range/change basis as disclosed, report period, event/publication/retrieval/meeting dates, source document, correction ancestry, scope, unknowns and receipts. Timeline alignment never treats one event class as another or fills an absent publication date.

The CN core composes CN document/accounting types and cannot import US/HK domains. Source effects use bounded CNINFO/exchange adapters.

## Explicit exclusions

No equivalence to US guidance/releases, automatic forecast-versus-actual judgment, earnings quality/surprise/materiality interpretation, sentiment, recommendation, or trade action.

## Implemented T1 scope

`cn_stock_earnings` uses three separate Tushare Pro structured endpoints and a
required `eventClass`: `forecast`, `express_report`, or
`disclosure_schedule`. Forecast ranges and original Chinese summaries/reasons,
express-report metrics and audit flags, and planned/actual/modified disclosure
dates retain exact source lexemes. Multiple rows are preserved; no revision or
event class is silently selected, collapsed, or substituted.

These rows are vendor-structured source facts, not exchange-authenticated
documents. Periodic-report documents and board-meeting dates are not available
from the selected endpoints and are visibly outside this operation; CNINFO
announcement discovery covers documents separately. `TUSHARE_TOKEN` and the
provider's endpoint permissions are runtime dependencies, never product data.
