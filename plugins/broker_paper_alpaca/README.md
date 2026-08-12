# pi_sparkles_broker_paper_alpaca

Status: **Implemented inventory — `track_partial`** · offline scenario/receipt review only · US network path on hold

## Implemented partial slice

`review_alpaca_paper_evidence` validates bounded caller-supplied deterministic
scenario envelopes or caller-owned Alpaca paper lifecycle observations. It
content-binds the projection, preserves status lexemes, and reports duplicate
or conflicting events. It has no network or broker authority. Scenario mode is
evidence validation only and does not predict or calculate a fill.
Caller-supplied source hashes are retained but are not verified against absent
source bytes and do not authenticate Alpaca.
Market-depth fact names are rejected; this plugin does not read bid/ask/offer
data.
The shared boundary also enforces an aggregate semantic-payload budget,
credential-shaped input rejection, JavaScript-safe event times, cross-track MIC
exclusion, and separate input-order versus occurred-time lifecycle projections.

Missing: named fill-model execution; Alpaca paper response decoders and
provider conformance fixtures; and read-only Alpaca network observation, which
remains on hold.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls.

## Reviewed completion target

The completed plugin has two explicitly different non-executing modes that
never share receipts:

1. `DeterministicSimulation` will fold caller-supplied observations through
   named Session 14 fill models with no network access. The current partial
   slice validates its evidence envelope only.
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
