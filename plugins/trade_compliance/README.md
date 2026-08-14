# pi_sparkles_trade_compliance

Status: **Implemented inventory — `track_partial`** · pure supplied-rule evaluation only

## Implemented partial slice

`evaluate_supplied_trade_rules` evaluates up to 200 versioned caller-supplied
boolean rules over up to 200 exact facts at one non-negative time. It enforces
effective intervals and unique rule/version pairs, then reports each rule as
`True`, `False`, `Unknown`, `NotApplicable`, or `Conflict` with matched facts
and a content receipt. Aggregate verdict is always absent, and the result is
non-executable.
Simultaneously active supplied versions of one rule ID are conflicts. Exact
duplicate facts are counted without inventing a conflict, while different
facts under one name remain conflicting. The output retains the full supplied
fact and rule inventories. Aggregate payload, credential-shaped names,
control-character text, and unsafe integer times fail closed.
Market-depth fact/rule names are rejected; this plugin does not read
bid/ask/offer data.

Missing: authoritative rule acquisition and rule-set completeness evidence;
rule-version comparison, correction lineage, and individual
predicate-explanation tools; and typed compound expressions beyond one named
boolean fact per rule.

Private blocker-resolution inventory now includes an unwired typed rule engine
for non-empty `all`/`any`/`not` expressions, recursive predicate explanations,
exact track/account/effective-time isolation, active-version conflicts,
version diffs, and validated correction ancestry. It is not decoded by or
registered from the Pi shell, emits no public tool result or receipt, and does
not change this plugin's `track_partial` scope. Authoritative acquisition,
completeness evidence, public schemas/tools, and acceptance remain missing.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls.

## Reviewed completion target

The completed plugin evaluates versioned caller/expert-supplied rules over exact
account, position, instruction, market, calendar, and capability facts. The
current partial package evaluates one supplied boolean rule set; the remaining
tools inspect a rule set, explain individual predicates, and compare rule-set
versions.

Each rule retains jurisdiction/account scope, authority/source, version, effective interval, required facts, boolean/unknown expression, severity label supplied by the rule author, and correction lineage. Results are per-rule `True`, `False`, `Unknown`, `NotApplicable`, or `Conflict`, with exact inputs, intermediate predicates, missing facts, and content receipts.

The rule engine is pure and total; external acquisition of laws, broker policy, or account facts is outside it. It cannot submit or block an order. Acceptance covers effective-date selection, conflicting/unknown rules, account/track isolation, version comparison, deterministic evaluation, and receipt stability.

## Explicit exclusions

No universal compliant/non-compliant verdict, legal or tax advice, jurisdiction inference, automatic policy updates, order authorization/blocking, broker mutation, recommendation, or assertion that supplied rules are complete or legally correct.
