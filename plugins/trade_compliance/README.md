# pi_sparkles_trade_compliance

Status: **Designing** · requirements only · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md).

## Reviewed first slice

The plugin evaluates versioned caller/expert-supplied rules over exact account, position, order, market, calendar, and capability facts. Proposed tools inspect a rule set, evaluate one draft, explain individual predicates, and compare rule-set versions.

Each rule retains jurisdiction/account scope, authority/source, version, effective interval, required facts, boolean/unknown expression, severity label supplied by the rule author, and correction lineage. Results are per-rule `True`, `False`, `Unknown`, `NotApplicable`, or `Conflict`, with exact inputs, intermediate predicates, missing facts, and content receipts.

The rule engine is pure and total; external acquisition of laws, broker policy, or account facts is outside it. It cannot submit or block an order. Acceptance covers effective-date selection, conflicting/unknown rules, account/track isolation, version comparison, deterministic evaluation, and receipt stability.

## Explicit exclusions

No universal compliant/non-compliant verdict, legal or tax advice, jurisdiction inference, automatic policy updates, order authorization/blocking, broker mutation, recommendation, or assertion that supplied rules are complete or legally correct.
