# pi_sparkles_macro_dashboard

Status: **Designing** · composition contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 39](../../../trading-course/sessions/39_macro_fx_global_market_composition_contract_20260811.md).

## Reviewed first slice

Tools define/inspect a caller-selected dashboard, drill one panel, and calculate an explicit transform over exact macro series receipts. Panels retain series/provider identity, unit/scale, frequency, seasonal adjustment, geography, observation/release/retrieval dates, vintage/revisions, transformation/version, currency basis and omissions.

Frequency alignment, lagging, growth, rebasing, rolling or other transformations execute only under a named caller policy and expose all input vintages. Each series keeps its entitlement; the composite carries the least-permissive rights fact. No direct acquisition occurs—the shell consumes existing macro adapters.

Acceptance covers mixed frequencies, missing releases, revision vintages, transformations, incompatible units, dashboard hashes and bounded drill-down.

## Explicit exclusions

No panel/series selection, stale substitution, regime/economic-strength label, causal/leading claim, forecast, recommendation, or synthetic global source.
