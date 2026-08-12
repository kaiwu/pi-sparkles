# pi_sparkles_broker_paper_ibkr

Status: **Designing — US network path on hold** · local simulation/receipt review · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls.

## Reviewed first slice

An IBKR paper-environment receipt-review adapter plus deterministic local
simulation. It accepts a non-executable plan and imports caller-owned paper
activity or observes it through a demonstrably read-only gateway capability.
It performs no broker mutation.

Facts include gateway/import session, environment, subaccount, conid/listing
identity, non-executable instruction, fingerprint, commissions/margin where
reported, provider order IDs/status lexemes, lifecycle/fill events, pacing,
disconnects, races, duplicates and unknown outcomes.

Any later network adapter uses isolated read-only authority; pure protocol
transitions and fingerprints contain no Pi or secrets. Acceptance covers
fixtures/imports, pacing, externally reported partial fills and cancel/fill
races, disconnect/reconnect, deduplication, conflicts and endpoint isolation.

## Gates and exclusions

The US network path is on hold. Fixture/import and deterministic simulation can
proceed without it. No write-capable credential, paper/live order placement,
routing, cancellation/replacement, automatic retry, hidden confirmation,
inferred fill, live-readiness judgment, or trade recommendation.
