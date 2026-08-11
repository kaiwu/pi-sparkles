# pi_sparkles_cn_macro

Status: **Designing** · official-series adapter pending · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md) and source/calculation boundaries from [Session 14](../../../trading-course/sessions/14_cg_day_execution_information_contract_20260807.md).

## Reviewed first slice

Search and retrieve exact NBS/PBOC/SAFE or another explicitly selected official macro series. Each series/observation retains publisher, series code/title, geography, unit/scale, frequency, seasonal adjustment, observation period/date, release/publication/retrieval times, vintage/revision, source language, coverage, rights and receipts.

Revisions are append-only vintages. Missing releases remain unavailable; frequency conversion or growth is performed only as a named caller-requested calculation with full leaves. Provider adapters are source-specific, bounded and fixture-tested.

## Explicit exclusions

No silent latest-vintage substitution, economic/regime interpretation, causal claim, forecast, policy advice, recommendation, or cross-country/global merge.
