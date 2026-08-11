# pi_sparkles_broker_readonly_alpaca

Status: **Designing** · externally gated · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md).

## Reviewed first slice

A provider-specific, strictly read-only Alpaca adapter for account capability, account summary, positions, open/recent orders, and fills. Every observation retains provider account/order/asset identity, environment, provider status lexemes, timestamps, pagination/request receipts, entitlement, and unavailable/conflicting fields.

The adapter must use `finance_http` with bounded responses, cancellation, pacing, credential redaction, and fixture-tested decoders. Credentials remain opaque capabilities and require demonstrably read-only scope. The Pi shell can inspect and page facts but exposes no mutation operation.

Acceptance requires fixtures for all states and pagination, secret-redaction tests, read-only method/host allowlists, cancellation, partial responses, and an opt-in real-account read-only check after access is approved.

## Stop conditions and exclusions

Blocked on an Alpaca account, reviewed API agreement/rights, and a read-only key. No order draft, submit, cancel, replace, paper/live equivalence, readiness verdict, recommendation, or credential material in model-visible output.
