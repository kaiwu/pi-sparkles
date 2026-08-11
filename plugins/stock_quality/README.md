# pi_sparkles_stock_quality

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 27](../../../trading-course/sessions/27_quality_growth_thesis_evidence_contract_20260811.md).

## Reviewed first slice

`quality_dimension(s)` and `quality_flag(s)` calculate separately requested profitability, return-on-capital, margin stability, cash conversion, leverage/coverage, working-capital, dilution, accrual, or other explicitly defined dimensions over resolved statement candidates.

Each result retains dimension/version, exact periods, units, filing/accession/tag leaves, expression tree, assumptions, result or unperformed reason, restatement/duplicate facts, and mechanical accounting flags. Period, filing, unit and taxonomy coherence are proved before calculation. Batch results never produce a composite.

A pure calculation core composes `finance_math` and consumes resolved fundamentals; the shell only decodes and returns compact results with bounded expression drill-down.

## Explicit exclusions

No quality score or weighting, threshold supplied by the plugin, good/bad/high/low label, fraud detection, management assessment, peer/sector ranking, sustainable-quality claim, forecast, recommendation, or investment verdict.

## Implemented T2 calculation path

`quality_dimensions` reads one versioned `stock_quality_v1` request from a
caller-owned regular UTF-8 file under an exact SHA-256 and explicit byte budget.
It accepts only `ratio`, `difference`
and retains exact decimal lexemes, separately labelled market legs, MICs,
units/currencies, periods, accession/taxonomy/tag contexts, source receipts,
caller assumptions, expression trees, output scale and rounding. Wrong tracks,
contexts or units, duplicate/missing operands, zero denominators, invalid
decimals and unsupported operations fail closed. The result is a mechanical
calculation receipt, never a score, base case, fair-value label,
recommendation, or trade decision.
