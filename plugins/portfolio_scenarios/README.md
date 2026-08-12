# pi_sparkles_portfolio_scenarios

Status: **Tier 3 ProductUseful** · calculation-only price-scenario implementation

The implemented `run_scenario` tool consumes one bounded, SHA-256-bound,
versioned portfolio receipt packet. It applies exact caller-defined price
shocks, retains separately labelled market legs and explicit FX operands, and
returns per-position and aggregate impacts with a canonical receipt. Other
reviewed shock families remain explicitly unsupported until their required
sensitivity operands are modelled; there is no silent approximation.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 24](../../../trading-course/sessions/24_cg_portfolio_full_review_contract_20260811.md). This README narrows that normative contract for `pi_portfolio_scenarios`; it does not select an implementation provider or authorize portfolio action.

## Reviewed first slice

The plugin applies caller-defined price, factor, rate, FX, volatility, liquidity, correlation, or custom-expression shocks to one content-bound multi-account portfolio snapshot. Proposed tools are `define_scenario`, `run_scenario`, `run_scenario_set`, and `compare_scenarios`.

Inputs retain the exact snapshot, native currencies, explicit FX receipts, scenario identity/source kind, ordered shocks, horizon, and any caller-selected interaction assumptions. Outputs retain per-position and aggregate impacts, base-currency conversion leaves, unaffected positions, requested extrema, multi-period steps, expression trees, unknowns, conflicts, and a canonical receipt.

## Laws and boundaries

- Scenarios are independently labelled `Hypothetical` or `HistoricalReplay`; neither is a forecast or probability claim.
- Missing identity, FX, or shock operands makes only the affected calculation unperformed. The plugin never fills or calibrates them.
- The functional core applies shocks and exact arithmetic without Pi, promises, HTTP, storage, or mutable state. A future Pi shell only decodes, invokes the core, and exposes compact output plus bounded drill-down.
- Reuse `finance_core`, `finance_math`, `finance_risk`, and the Session 24 portfolio fact model. Every result binds the source snapshot and scenario definition.

Initial acceptance must cover every shock family, multi-period ordering, incompatible currency/identity, partial results, stable receipts, cancellation at the shell, and bundled compact/drill-down interactions.

## Explicit exclusions

No scenario calibration, probability assignment, likely/worst-case label, stress-test verdict, capital-adequacy judgment, optimization, rebalance selection, recommendation, order construction, or broker effect.
