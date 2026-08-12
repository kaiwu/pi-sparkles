# pi_sparkles_broker_paper_alpaca

Status: **Designing — US network path on hold** · local simulation/receipt review · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls.

## Reviewed first slice

This plugin has two explicitly different non-executing modes that never share receipts:

1. `DeterministicSimulation` folds caller-supplied observations through named Session 14 fill models with no network access.
2. `AlpacaPaperReceiptReview` imports caller-owned Alpaca paper activity or
   observes it through a demonstrably read-only capability.

Both modes retain exact environment, non-executable instruction, capability or
import receipt, plan fingerprint, lifecycle events, fills, races, unknown
outcomes, and correction lineage. Imported lifecycle facts are deduplicated and
reconciled without a broker write or blind retry.

Any later read-only provider effect uses bounded `finance_http`, read-only
credentials, GET-only host/environment allowlists, data-subscription
cancellation, pacing, and audit events. Pure deterministic simulation remains a
separate core.

## Gates and exclusions

Deterministic and fixture/import modes have no external blocker. The US network
path is on hold. No write-capable credential, paper/live order placement,
routing, cancellation/replacement, automatic authorization/retry, predicted
fill, paper/live equivalence, readiness verdict, recommendation, or size
increase chosen by the plugin.
