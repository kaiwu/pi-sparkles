# pi_sparkles_broker_paper_ibkr

Status: **Designing** · externally gated · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md).

## Reviewed first slice

An IBKR paper-environment order lifecycle adapter. It constructs a non-executable draft, obtains an exact gateway preview/capability receipt, requires explicit content-bound human authorization, and performs idempotent submit/cancel/replace only against the selected paper environment.

Facts include gateway session, environment, subaccount, conid/listing identity, instruction and provider encoding, fingerprint, preview timestamps, commissions/margin where returned, provider order IDs/status lexemes, lifecycle/fill events, pacing, disconnects, races, and unknown outcomes. A timeout triggers status reconciliation, not retry.

The adapter uses an isolated credential/network capability; pure protocol transitions and fingerprints contain no Pi or secrets. Acceptance covers fixtures for previews, confirmations, pacing, partial fills, cancel/fill races, disconnect/reconnect, idempotency, stale authorization, and endpoint isolation.

## Gates and exclusions

Blocked on IBKR paper access, gateway/API agreement, and security review. No live endpoint, automatic retry, hidden confirmation, inferred fill, live-readiness judgment, or trade recommendation.
