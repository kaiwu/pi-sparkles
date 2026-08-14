# pi_sparkles_broker_paper_ibkr

Status: **Implemented inventory — `track_partial`** · offline scenario/receipt review only · optional IBKR observation absent

## Implemented partial slice

`review_ibkr_paper_evidence` validates bounded caller-supplied deterministic
scenario envelopes or caller-owned IBKR paper lifecycle observations. It
content-binds the projection, preserves status lexemes, and reports duplicate
or conflicting events. It has no gateway, network, or broker authority.
Scenario mode is evidence validation only and does not predict or calculate a
fill.
Caller-supplied source hashes are retained but are not verified against absent
source bytes and do not authenticate IBKR.
Market-depth fact names are rejected; this plugin does not read bid/ask/offer
data.
The shared boundary also enforces an aggregate semantic-payload budget,
credential-shaped input rejection, JavaScript-safe event times, cross-track MIC
exclusion, and separate input-order versus occurred-time lifecycle projections.

Missing: named fill-model execution; IBKR paper response decoders and provider
conformance fixtures; and optional read-only IBKR network observation. Futu is
T6's required first US live-data provider and is not a paper-broker substitute.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls.

## Reviewed completion target

The completed scope adds an IBKR paper-environment receipt-review adapter plus
deterministic local simulation. It accepts a non-executable plan and imports caller-owned paper
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

Optional IBKR network observation requires its own reviewed read-only authority
and does not substitute for Futu's required US live-data leg. Fixture/import
work and deterministic scenario-envelope validation can proceed without it;
named fill-model execution is still missing. No write-capable credential,
paper/live order placement,
routing, cancellation/replacement, automatic retry, hidden confirmation,
inferred fill, live-readiness judgment, or trade recommendation.
