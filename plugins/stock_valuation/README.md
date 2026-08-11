# pi_sparkles_stock_valuation

Status: **Designing** · calculation contract only · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 26](../../../trading-course/sessions/26_peer_valuation_industry_research_contract_20260811.md).

## Reviewed first slice

`inspect_valuation` executes an explicit, caller-supplied assumption graph for named DCF, dividend-discount, residual-income, or multiples-based variants. Sensitivity grids and scenario comparisons run only when requested.

Inputs retain instrument/share identity, valuation date, source candidates, forecast/terminal assumptions, discount rates, capital/share facts, currencies and FX receipts, selected method/version, rounding, and scenario identity. Outputs expose every source leaf, ordered expression tree, intermediate cash flows, solver parameters/iterations, per-share result or range supplied by scenarios, unperformed reasons, and canonical receipt.

Pure domain modules compose `finance_math`; provider acquisition and assumption generation stay outside. Incompatible periods/units/currencies, missing leaves, invalid terminal relationships, zero denominators, or non-convergent solvers fail visibly.

## Explicit exclusions

No built-in WACC/growth/forecast, default or base case, fair-value/target-price label, scenario probability, model correctness, peer choice, recommendation, or trade action.
