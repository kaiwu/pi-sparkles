# pi_sparkles_broker_live

Status: **Designing — non-executing scope** · US network path on hold · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls and supersedes the directory's legacy name.

## Reviewed first slice

This legacy-named proposal exports a content-bound, non-executable handoff for
the user to inspect and act on outside Pi, then imports caller-owned execution
receipts or observes lifecycle state through a demonstrably read-only provider
capability. It never sends an order operation.

The handoff binds declared account context, external environment, instrument,
side, type, quantity, prices, time-in-force, rule versions and plan fingerprint.
Any change creates a different artifact. Imported/read-only results retain
provider IDs/statuses, acknowledgements, fills, partial fills, rejection,
timeout/disconnect ambiguity, externally performed cancel/replace/fill races,
duplicates, conflicts and audit evidence.

No write-capable credential is accepted. Optional read-only credentials are
opaque capabilities unavailable to pure/domain modules and model context.
Provider adapters are isolated; there is no generic cross-broker fallback.

## Hard gates and exclusions

The US network path is on hold while T6 uses its CN anchor. Import and handoff
work may proceed with exact schemas, rights and private-data controls. No plugin
may place, submit, route, cancel, replace, modify, approve, or otherwise mutate
an order; no broker preview or write endpoint; no unattended/algorithmic
trading, LLM authorization, hidden retry, rollback claim, size escalation,
readiness verdict, legal advice, or recommendation.
