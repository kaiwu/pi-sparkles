# pi_sparkles_broker_readonly_ibkr

Status: **Designing — US network path on hold** · read-only/import only · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls.

## Reviewed first slice

A strictly read-only IBKR adapter for account summary, positions, recent/open orders, fills, session state, and capability facts through one explicitly selected Client Portal or TWS/Gateway contract. Provider identifiers, subaccounts, conids, currencies, status lexemes, pacing/session times, and missing/conflicting observations remain exact.

Network effects use `finance_http` or a separately reviewed gateway capability with bounded responses, cancellation, pacing, reconnection evidence, and opaque credentials. The provider decoder is independent of Pi; the shell exposes only read operations and never treats a paper gateway as live or vice versa.

Acceptance covers fixture decoding, multiple accounts/currencies, pacing/session expiry, reconnect without hidden mutation, pagination, secret redaction, and an opt-in paper-account read-only run.

## Stop conditions and exclusions

The live IBKR network adapter is on hold while T6 uses its CN anchor. Fixture
decoding and a caller-owned activity export may prove the bounded import
contract; any later network mode requires reviewed rights and demonstrably
read-only authority. No write-capable credential, order placement/routing,
cancellation/replacement, automatic login recovery, environment relabelling,
readiness judgment, or live effect.
