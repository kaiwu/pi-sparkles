# pi_sparkles_cn_stock_watch

Status: **Designing** · read-only first slice · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 29](../../../trading-course/sessions/29_monitoring_catalyst_alert_contract_20260811.md).

## Reviewed first slice

The plugin queries exact CN disclosure events for one caller-resolved listing: announcements, performance forecasts/express reports, unlocks, pledges, suspensions, dated rule-state changes, and Stock Connect eligibility. Results retain `cn` MIC/board/share class, Chinese event labels/titles, event/publication/retrieval/effective dates, source receipts, corrections, coverage and unavailable/conflicting facts.

The first slice is on-demand and read-only. It composes CNINFO/exchange adapters without importing HK/US domains, substituting sources, or inferring identity/rules. Bounded paging and drill-down expose original-language metadata and source documents where already licensed.

Acceptance covers each event family, date semantics, corrections/duplicates, ambiguous identity, missing adapter coverage, source failure, stable receipts, and no cross-track state.

## Explicit exclusions

No continuous watchlist/polling, durable alert state, notification, event severity, policy or risk interpretation, silence-as-no-event, recommendation, or trade action.
