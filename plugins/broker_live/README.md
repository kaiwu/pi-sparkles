# pi_sparkles_broker_live

Status: **Designing** · high-risk external stops remain · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md).

## Reviewed first slice

One provider-specific live order mutation behind the complete Session 25 protocol: non-executable draft, exact capability/rule comparison, provider preview, content-bound human authorization with expiry, idempotent submission, and explicit lifecycle reconciliation. Submit, cancel, and replace are distinct effects; replace never assumes cancel succeeded.

The authorization binds account, live environment, instrument, side, type, quantity, prices, time-in-force, provider encoding, preview, rule versions, and order fingerprint. Any change invalidates it. Results retain provider IDs/statuses, acknowledgements, fills, partial fills, rejection, timeout/disconnect ambiguity, cancel/fill races, and audit events. Unknown submission status is queried and surfaced—never automatically retried.

Credentials are opaque, least-privilege capabilities unavailable to pure/domain modules and model context. Provider adapters are isolated; there is no generic cross-broker live fallback.

## Hard gates and exclusions

No implementation or live acceptance until a named provider agreement/capability, entitlement, security review, jurisdiction/account rules, incident plan, prolonged paper evidence, and exact per-order human authorization exist. No unattended/algorithmic trading, LLM authorization, hidden retry, rollback claim, size escalation, readiness verdict, legal advice, or recommendation.
