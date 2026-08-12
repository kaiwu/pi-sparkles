# pi_sparkles_cn_broker_paper

Status: **Implemented inventory — `track_partial`** · offline scenario/receipt review only · T6 remains blocked

## Implemented partial slice

`review_cn_paper_evidence` validates bounded caller-supplied CN deterministic
scenario envelopes or caller-owned external-paper facts and lifecycle events.
It enforces `cn`, exact environment modes, SHA-256 references, fact/event
budgets, content receipts, duplicate counting, and explicit conflict results.
It performs no network call and accepts no broker authority. The current
scenario mode validates supplied evidence; it is not yet a named fill engine.
Caller-supplied source hashes are retained but are not verified against absent
source bytes and do not authenticate a provider.
Market-depth fact names are rejected; this plugin does not read bid/ask/offer
data.

Missing: a named CN broker read-only/export contract and conformance fixtures;
named fill-model execution joined to exact CN rules, calendar, and settlement
receipts; and the authenticated CN intraday feed required by
`T6-INTRADAY-PROVIDERS`.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls.

## Reviewed completion target

The completed plugin will support a named deterministic CN simulation and bounded read-only
review of caller-owned external paper-account receipts. The modes remain
different types and receipts. Inputs must carry exact `cn`
listing/MIC/board/share class, a non-executable instruction, dated
rule/capability receipts, session/calendar state, lot/tick/limit/settlement
facts, and source observations.

The future deterministic engine mechanically applies only supplied versioned rules and named
fill models. Receipt-review mode imports or reads external paper lifecycle
facts, preserves provider status lexemes and races, and reconciles unknown
results without invoking a broker write. Neither mode can cause an order.

The CN domain cannot import HK/US market rules. Acceptance covers T+1, lot
grids, price-limit and suspension unknowns, rule conflicts, simulated or
externally reported partial fills, duplicate/conflicting imports, environment
isolation, and no secret leakage.

## Gates and exclusions

The current envelope validator can proceed with reviewed rule receipts. Named
fill execution remains missing. External receipt
review requires one named export/read-only contract and provider rights. No
write-capable credential, broker-hosted paper effect, order placement, routing,
order cancellation/replacement, live mutation, hard-coded universal CN rules,
provider fallback, readiness verdict, or recommendation.
