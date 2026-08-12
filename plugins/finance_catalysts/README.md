# pi_sparkles_finance_catalysts

Status: **Tier 3 ProductUseful** · read-only canonical-receipt composition

The implemented `catalyst_timeline` tool validates a bounded,
SHA-256-bound multi-source receipt packet and produces a stable timeline while
retaining independent same-event reports, corrections/retractions, language,
rights, coverage, source failures, and separately labelled track identity.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 29](../../../trading-course/sessions/29_monitoring_catalyst_alert_contract_20260811.md).

## Reviewed first slice

The plugin builds an ordered, cross-source event timeline for one exact listing and caller-supplied date range from earnings, filing, corporate-action, news, and caller-event receipts. It retains event/source identity, event/publication/retrieval times, corrections/retractions, language, entitlement, independent legs, unknowns, and source hashes.

Timeline ordering and filtering are pure. Equal-time and conflicting events remain separate; no event is dropped or causally joined. The first slice queries existing adapters on demand and keeps no durable monitor state.

Acceptance covers cross-source ordering, independent same-event reports, corrections, late/retracted events, calendar/timezone facts, partial adapter failure, stable paging, and no causal fields.

## Explicit exclusions

No catalyst importance/impact score, causal attribution, likely price effect, absence claim, continuous polling, notification, watchlist mutation, recommendation, or trade action.
