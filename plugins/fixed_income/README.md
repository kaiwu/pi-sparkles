# pi_sparkles_fixed_income

Status: **Designing** · calculation and source contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 35](../../../trading-course/sessions/35_rates_fixed_income_convertible_contract_20260811.md).

## Reviewed first slice

Tools generate exact bond cash-flow schedules and calculate caller-selected YTM/YTC/YTP/YTW, Macaulay/modified duration, convexity, G/Z spread, present value, discount factors, and curves under named interpolation methods. Inputs retain security/issuer identity, terms, cash-flow/call/put schedules, clean/dirty price, accrued interest, currency, day-count/business-day conventions, settlement calendar, benchmark instruments and solver bounds.

Outputs expose ordered cash flows, formulas, curve knots, interpolation/extrapolation policy, solver iterations/convergence, every source leaf, approximations, unknown future floating cash flows, defaults/corrections, and canonical receipts. Incompatible conventions or missing terms are unperformed, never defaulted.

Pure fixed-income modules compose `finance_math`/calendars; provider-specific bond terms and TRACE-like observations remain separate bounded adapters.

## Gates and exclusions

Bond-terms/provider rights remain unresolved. No instrument/curve/method/rate selection, OAS without an explicit model, credit/default/recovery model, fair value, relative-value judgment, forecast, recommendation, or trade action.
