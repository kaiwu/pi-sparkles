# pi_sparkles_options

Status: **Designing** · provider/licence gated · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 36](../../../trading-course/sessions/36_options_information_calculation_contract_20260811.md).

## Reviewed first slice

Tools inspect exact option contracts and adjustment lineage; retrieve quote/trade/open-interest facts and bounded chains; calculate caller-defined single/multi-leg payoff grids and break-evens; run explicitly selected Black–Scholes or binomial pricing, implied-volatility root finding, requested Greeks, and a named surface interpolation.

Identity binds underlying listing, OCC/venue series, call/put, exercise style, strike/currency, multiplier, expiration/settlement, deliverable and corporate-action adjustments. Market observations preserve bid/ask/trade/OI state, timestamps, venue/feed, entitlement and conflicts. Calculations expose model/version, inputs, expression tree, solver iterations/roots, approximation/rounding and unperformed reasons.

A pure `finance_options` core owns identity and calculations. Licensed provider adapters use bounded shared HTTP; the Pi shell never selects a contract/model/strategy.

## Gates and exclusions

Requires options and underlying data rights plus adjustment evidence. No cheap/expensive/fair-value label, probability-of-profit claim, exercise/assignment prediction, hedge/strategy recommendation, liquidity judgment, portfolio risk aggregation, or trading effect.
