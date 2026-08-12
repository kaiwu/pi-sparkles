# pi_sparkles_portfolio_rebalance

Status: **Tier 3 ProductUseful** · mechanical-delta implementation

The implemented `compute_rebalance` tool consumes exact snapshot and target
receipts and calculates continuous plus caller-grid deltas, projected cash,
turnover, and minimum-trade/cash constraint facts. Foreign-currency legs require
an explicit `fxToBase` operand before any aggregation. It creates no order,
sequence, authorization, recommendation, or optimization.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 24](../../../trading-course/sessions/24_cg_portfolio_full_review_contract_20260811.md). Live effects remain separately controlled by [Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md).

## Reviewed first slice

The plugin mechanically projects a supplied portfolio toward caller-supplied target weights and constraints. Proposed tools are `compute_rebalance`, `project_weights`, and `estimate_costs`.

Inputs bind an exact portfolio snapshot, target specification, tolerance bands, cash/turnover constraints, account scope, lot-size grids, optional cost assumptions, and an explicit tax-lot selection policy. Outputs retain continuous deltas, grid-projected quantities, projected weights and cash, constraint facts, estimated costs, infeasibility reasons, tax-lot links, expression trees, and a content receipt.

## Laws and boundaries

- A result is a `MechanicalProposal`, never a recommendation, optimum, order, or authorization.
- The caller owns targets, constraints, rounding direction, lot selection, priorities, and any choice among alternatives.
- Grid projection cannot silently violate cash, turnover, short-sale, account, currency, or lot constraints; infeasibility is a first-class result.
- A pure `finance_portfolio_rebalance` core composes exact math/risk and tax-lot facts. The Pi shell performs no provider call, durable mutation, or broker submission.

Acceptance covers continuous/grid deltas, multi-account and currency legs, cost assumptions, cash/turnover limits, infeasible cases, missing facts, deterministic receipts, and no executable order fields.

## Explicit exclusions

No optimization, target generation, trade sequencing, automated tax-loss harvesting, suitability, preferred proposal, order routing, or paper/live execution.
