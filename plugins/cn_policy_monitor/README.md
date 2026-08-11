# pi_sparkles_cn_policy_monitor

Status: **Designing** · source access unresolved · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 29](../../../trading-course/sessions/29_monitoring_catalyst_alert_contract_20260811.md).

## Reviewed first slice

The first slice queries policy-document metadata from an explicitly selected CSRC or mainland exchange source. It returns publisher/authority role, original Chinese title, document/type/number, publication and stated effective dates, jurisdiction/market scope, status/correction lineage, source URL/receipt, retrieval time, rights, coverage, and unknowns.

Identity, date ordering and metadata decoding are pure. A future adapter must be bounded, cancellable, fixture-tested, source-specific and use `finance_http`. Sources are never merged as equivalent authorities. Translation, when later requested, is a labelled derivative retaining original spans.

Acceptance covers publisher/type/date decoding, corrections, unavailable effective dates, source coverage, original language, malformed responses, budgets and rights facts.

## Gates and exclusions

Blocked on source access and terms review. No policy interpretation/advice, affected-company inference, importance/impact score, continuous polling, full-text or translation in the first slice, notification, recommendation, or trade action.
