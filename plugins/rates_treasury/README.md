# pi_sparkles_rates_treasury

Status: **Designing** · public-source review pending · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 35](../../../trading-course/sessions/35_rates_fixed_income_convertible_contract_20260811.md).

## Reviewed first slice

The plugin returns exact US Treasury security and rate observations. Tradable bills/notes/bonds retain CUSIP, issue/maturity/auction dates, coupon, day-count, payment frequency, on/off-the-run status and price/yield observation facts. Constant Maturity Treasury series retain tenor/series identity and must never be represented as a tradable security.

Every observation preserves clean/dirty/rate kind, source lexeme, unit/convention, observation/publication/retrieval dates, revision/vintage, entitlement and receipt. No curve is constructed unless a separate caller request is sent to `pi_fixed_income`.

The adapter uses bounded public FRED/Treasury source plans; decoding and identity validation remain pure and fixture-tested.

## Gates and exclusions

Requires exact source/terms/coverage review. No benchmark selection, silent CMT/tradable equivalence, curve, forecast, relative-value/attractive-yield label, recommendation, or trade action.
