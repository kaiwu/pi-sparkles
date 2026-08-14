# pi_sparkles_broker_live

Status: **Implemented inventory — `track_partial`** · non-executable handoff/import review only · provider network paths absent

## Implemented partial slice

`review_external_execution_evidence` content-binds exact caller-supplied facts
as a non-executable handoff or reviews bounded caller-owned external lifecycle
observations. It retains exact environment/track labels, status lexemes,
duplicates, conflicts, and a semantic receipt. It has no transport, credentials,
or broker authority.
Caller-supplied source hashes are retained but are not verified against absent
source bytes and do not authenticate any provider.

The unregistered `review_local_execution_file` package function is the private
local import channel. It reads one caller-selected regular UTF-8 file through
`finance_local_import` under a 250 KB ceiling, rejects symlinks, supports
cancellation, verifies an out-of-band SHA-256 over the exact bytes before JSON
decoding, and accepts only `broker_local_execution_import_v1` external receipt
review. It returns a normalized bounded review or a typed failure; neither the
path nor raw text is registered as a Pi tool or returned in the review. This
does not authenticate the external provider.
Market-depth fact names are rejected; this plugin does not read bid/ask/offer
data.
Non-executable handoff mode requires exactly one known
`instruction_side`, `instruction_kind`, `quantity`, `quantity_unit`,
`time_in_force`, `plan_fingerprint`, and `rule_reference` fact. Missing,
non-known, or duplicate instruction fields fail closed. The shared boundary
also enforces an aggregate semantic-payload budget, credential-shaped input
rejection, JavaScript-safe event times, exact track/MIC isolation, and separate
input-order versus occurred-time lifecycle projections.

Missing: named read-only provider adapters and rights review; and
authenticated live sequence/reconciliation conformance evidence.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls and supersedes the directory's legacy name.

## Reviewed completion target

This legacy-named proposal's completed scope exports a content-bound,
non-executable handoff for
the user to inspect and act on outside Pi, then imports caller-owned execution
receipts or observes lifecycle state through a demonstrably read-only provider
capability. It never sends an order operation.

The completed handoff target binds declared account context, external
environment, instrument, side, type, quantity, caller-declared price context
when applicable, time-in-force, rule versions and plan fingerprint.
Any change creates a different artifact. Imported/read-only results retain
provider IDs/statuses, acknowledgements, fills, partial fills, rejection,
timeout/disconnect ambiguity, externally performed cancel/replace/fill races,
duplicates, conflicts and audit evidence.

No write-capable credential is accepted. Any future optional read-only credentials are
opaque capabilities unavailable to pure/domain modules and model context.
Provider adapters are isolated; there is no generic cross-broker fallback.

## Hard gates and exclusions

T6 requires separately conformed Futu `cn`, `hk`, and `us` live-data legs;
read-only account observation remains a distinct capability and may never be
inferred from quote entitlement. Import and handoff work may proceed with exact
schemas, rights and private-data controls. No plugin
may place, submit, route, cancel, replace, modify, approve, or otherwise mutate
an order; no broker preview or write endpoint; no unattended/algorithmic
trading, LLM authorization, hidden retry, rollback claim, size escalation,
readiness verdict, legal advice, or recommendation.
