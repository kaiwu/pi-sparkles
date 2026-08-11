# pi_sparkles_tax_lots

Status: **Designing** · requirements only · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 24](../../../trading-course/sessions/24_cg_portfolio_full_review_contract_20260811.md).

## Reviewed first slice

The plugin exposes lot-level information and caller-requested arithmetic. Proposed tools are `inspect_lots`, `select_lots`, `realized_gain`, `unrealized_gain`, and `holding_classification`.

Each lot retains account, listing/share-class identity, acquisition/disposal dates, quantity and unit, native currency, exact cost basis and adjustments, source receipt, information state, and correction lineage. Selection applies only an explicit method such as FIFO, LIFO, or caller-specified IDs. Results expose selected and remaining lots, proceeds, basis, gain/loss, caller-rule holding classification, formula leaves, unknowns, and receipt hashes.

## Laws and boundaries

- Tax jurisdiction, rates, holding-period rules, wash-sale parameters, FX policy, and disposal method are caller/expert-supplied versioned inputs—not embedded legal knowledge.
- Unknown basis, dates, identity, currency, or rule applicability stays unknown; no estimate or silent aggregation is allowed.
- The pure `finance_tax_lot` core owns immutable lot transitions and exact arithmetic. The shell neither reads a broker nor writes a tax record in the first slice.
- Corrections append lineage and never rewrite historical receipts.

Acceptance covers FIFO/LIFO/specific identification, partial disposals, basis adjustments, missing jurisdiction facts, caller-supplied wash-sale calculations, cross-currency rejection, correction lineage, and stable receipts.

## Explicit exclusions

No tax advice, jurisdiction selection, tax-efficiency label, filing preparation, automated harvesting, rebalance choice, recommendation, or broker mutation.
