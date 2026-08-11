# pi_sparkles_cn_stock_financials

Status: **Designing** · narrow accounting-source slice · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md) and [Session 19](../../../trading-course/sessions/19_cg_fundamental_investor_dossier_contract_20260809.md).

## Reviewed first slice

Expose exact vendor-reported revenue and parent-company profit observations for one resolved CN issuer/listing, plus an explicitly requested net-margin calculation. Facts preserve Chinese labels, numeric lexemes, reported scale/unit/currency, period and statement scope as known, provider mapping/version, source/retrieval time, duplicates/conflicts, unknown filing/audit/restatement context, entitlement and receipts.

The plugin composes the existing CN accounting/vendor substrate. It does not turn vendor fields into official filing facts or choose among alternatives. Margin uses exact resolved operands and retains both leaves/formula.

## Explicit exclusions

No complete statements, segments, hidden tag mapping, vendor-to-official equivalence, quality/valuation judgment, forecast, recommendation, or trade action.
