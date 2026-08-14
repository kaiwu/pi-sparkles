# pi_sparkles_cn_broker_readonly

Status: **Designing — T6 CN-specific read-only leg** · provider-specific choice unresolved · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls.

## Reviewed first slice

A broker-specific read-only view of mainland accounts, cash/settlement, positions, orders, fills, capabilities, and entitlements. It must retain the exact broker, account, `cn` listing/MIC/board/share-class identity, native currency, T+1/settlement observations, provider status codes, timestamps, and unknown/conflicting facts; it may not infer identity or rules from a six-digit code.

The eventual adapter is isolated from HK/US brokers and uses bounded, cancellable, redacted transport. Pure decoding and normalized observation construction remain outside Pi. No generic lowest-common-denominator broker schema may erase CN-specific fields.

Acceptance starts with provider fixtures for multi-account/currency, settlement and order states, pacing, partial data, and secret redaction; any live read-only lane is opt-in.

## Stop conditions and exclusions

Blocked until one CN broker or caller-owned export contract, authentication/import method, entitlement, and usage rights are reviewed. No write-capable credential, order placement, routing, order cancellation/replacement, paper/live mutation, universal broker support, inferred legal status, or trading judgment.
