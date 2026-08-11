# pi_sparkles_cn_convertible_bonds

Status: **Designing** · CN source contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 35](../../../trading-course/sessions/35_rates_fixed_income_convertible_contract_20260811.md).

## Reviewed first slice

The plugin inspects an exact mainland convertible and its linked underlying listing, terms and revision announcements; calculates conversion value/parity, conversion and investment premium, caller-model bond floor, requested call/convert/hold/put scenario payoffs, and mechanical trigger counts.

Identity retains bond/listing/MIC, issuer, underlying share class, currency, issue/maturity/coupon and lot facts. Conversion price/ratio, reset, redemption/call/put clauses, effective dates, corporate-action adjustments, trading calendars and source receipts remain versioned. Calculations expose every bond/stock/rate leaf and fail on unknown/conflicting terms rather than predicting them.

CN-only domain code composes shared exact math/fixed-income calculations but imports no HK/US market domain. Provider effects are bounded and source-specific.

## Gates and exclusions

Requires a reviewed convertible-terms source plus underlying/rate evidence. No call/reset/exercise prediction, cheap/expensive/fair-value label, credit/volatility model by default, trigger interpretation, recommendation, or order action.
