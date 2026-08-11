# pi_sparkles_stock_growth

Status: **Designing** · calculation contract only · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 27](../../../trading-course/sessions/27_quality_growth_thesis_evidence_contract_20260811.md).

## Reviewed first slice

`growth_decomposition`, `growth_metrics`, and `compound_growth` calculate exact caller-selected changes between coherent periods. Supported components are only those backed by supplied evidence, such as organic/acquired, price/volume, currency, mix, share-count, or segment contributions.

Outputs retain metric identity, exact period candidates, unit/taxonomy/tag/accession coherence, historical versus caller-supplied component provenance, formulas, residuals, base effects, restatement lineage, missing components, and canonical receipts. CAGR requires a valid ordered span; decompositions never force residuals into named causes.

The pure core composes exact math. Provider facts, forecasts, classifications, and component selection remain outside the plugin.

## Explicit exclusions

No trend interpretation, sustainability label, forecast/extrapolation, default growth driver, terminal growth, peer comparison, quality judgment, recommendation, or investment conclusion.
