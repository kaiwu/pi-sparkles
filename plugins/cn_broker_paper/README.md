# pi_sparkles_cn_broker_paper

Status: **Designing** · provider choice unresolved · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md).

## Reviewed first slice

The plugin supports either a named deterministic CN simulation or one explicitly selected broker-hosted paper environment; the modes remain different types and receipts. Inputs must carry exact `cn` listing/MIC/board/share class, desired instruction, dated rule/capability receipts, session/calendar state, lot/tick/limit/settlement facts, and source observations.

Deterministic mode mechanically applies only supplied versioned rules and named fill models. Broker-hosted mode uses the Session 25 draft/preview/human-authorization/idempotent-submission lifecycle, preserves provider status lexemes and races, and reconciles unknown results without blind retry.

The CN domain cannot import HK/US market rules. Acceptance covers T+1, lot grids, price-limit and suspension unknowns, rule conflicts, partial fills, stale authorizations, environment isolation, and no secret leakage.

## Gates and exclusions

Deterministic work can proceed with reviewed rule receipts. Hosted effects require a named CN broker, paper capability, provider rights, and security review. No live mutation, hard-coded universal CN rules, provider fallback, readiness verdict, or recommendation.
