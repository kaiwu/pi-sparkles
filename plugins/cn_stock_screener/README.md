# pi_sparkles_cn_stock_screener

Status: **Designing** · CN projection slice · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md), [Session 16](../../../trading-course/sessions/16_cg_quant_shared_replay_information_contract_20260807.md), and the existing `stock_screener` contract.

## Reviewed first slice

Project a point-in-time mainland universe and evaluate caller-authored predicates over exact CN facts such as board, share/ST/status, liquidity, market cap, financial/valuation/growth/dividend fields and dated trading constraints. It reuses `project_universe` and the pure predicate engine with exact `cn` identity.

Outputs retain every member and per-predicate true/false/unresolved state, dataset/vintage/cutoff receipts, duplicate/conflicting facts, and stable paging. Missing facts never remove a security; no current universe is used historically. CN-specific fields require exact sourced definitions.

## Explicit exclusions

No provider universe discovery in the first slice, default filters, ranking/score, candidate recommendation, cross-track fallback, backtest validity verdict, or trade action.
