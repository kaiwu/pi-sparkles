# pi_sparkles_fx_ecb

Status: **Designing** · public-source adapter pending · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 39](../../../trading-course/sessions/39_macro_fx_global_market_composition_contract_20260811.md).

## Reviewed first slice

Tools return one ECB reference-rate observation, calculate an explicitly requested inverse/cross rate, and convert an exact amount for one date. Inputs/outputs retain base/quote direction, rate kind, value lexeme, observation/publication/retrieval times, ECB source, TARGET calendar facts, missing/revised state, formula and conversion receipt.

Cross rates use explicit coherent ECB legs through EUR (or another caller-selected supported pivot); multiplication/division direction is visible. Missing holiday/date facts remain unavailable unless the caller explicitly requests a dated alternative—no silent last-value carry.

The ECB SDMX adapter is bounded, cancellable and fixture-tested; exact FX arithmetic is pure and composes shared math.

## Gates and exclusions

Source schema/terms/attribution require review. Reference rates are not executable quotes. No silent inversion/cross/carry-forward, forward/swap pricing, currency value judgment, forecast, recommendation, or trade action.
