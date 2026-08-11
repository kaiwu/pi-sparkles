# pi_sparkles_finance_alerts

Status: **Designing** · durable local predicate contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 29](../../../trading-course/sessions/29_monitoring_catalyst_alert_contract_20260811.md).

## Reviewed first slice

The plugin stores versioned caller-authored monitor definitions and evaluates their predicates over caller-supplied observation batches. It records `MatchFound`, `NoMatch`, `CannotEvaluate`, conflict, deduplication and cooldown facts in an append-only local journal. Proposed operations define/amend/disable a monitor, evaluate a batch, inspect state/events, and export/import bounded receipts.

Definitions bind scope, exact predicate AST, temporal policy, deduplication key, cooldown, budgets, entitlement, version and correction lineage. Pure evaluation is total; durable state uses `finance_journal`, supports fork/resume/replay, redaction, retention/compaction receipts, and idempotent event identities.

Acceptance covers every predicate state, duplicates, cooldown, late/corrected observations, restart/replay, concurrent writers, privacy/redaction, and content hashes.

## Explicit exclusions

No scheduler, source polling, external notification in the first slice, inferred urgency, silence-as-all-clear, monitor sufficiency, recommendation, or automatic trading response. Notification requires a separately authorized destination effect.
