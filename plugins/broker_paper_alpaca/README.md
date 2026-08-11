# pi_sparkles_broker_paper_alpaca

Status: **Designing** · split simulation/effect contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md).

## Reviewed first slice

This plugin has two explicitly different modes that never share receipts:

1. `DeterministicSimulation` folds caller-supplied observations through named Session 14 fill models with no network access.
2. `AlpacaPaper` drafts, previews, explicitly authorizes, submits, cancels, or replaces orders only against Alpaca's paper environment.

Both modes retain exact environment, desired instruction, encoding/capability receipt, order fingerprint, preview, authorization identity/time/expiry, idempotency key, lifecycle events, fills, races, unknown outcomes, and correction lineage. Paper-hosted mutation follows non-executable draft → exact preview → explicit human authorization → idempotent submission. Timeouts are reconciled by query, never blind retry.

Provider effects use bounded `finance_http`, opaque credentials, host/environment allowlists, cancellation, pacing, and audit events. Pure deterministic simulation remains a separate core.

## Gates and exclusions

Deterministic mode has no external blocker. Hosted mode needs an Alpaca paper account, rights review, and security review. No live endpoint, automatic authorization/retry, predicted fill, paper/live equivalence, readiness verdict, recommendation, or size increase chosen by the plugin.
