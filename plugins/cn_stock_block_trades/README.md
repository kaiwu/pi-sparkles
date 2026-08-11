# pi_sparkles_cn_stock_block_trades

Status: **Designing** · exchange-information contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Return published 大宗交易 records for one exact CN listing/date range with trade date/time if supplied, price/currency, quantity/unit, amount, comparison-price identity, mechanically requested premium/discount, and buyer/seller branch labels exactly as published. Preserve source, correction, duplicates, coverage and receipts.

Branch labels are not beneficial-owner identities. Premium/discount requires a caller-selected coherent comparison price/date and exposes both leaves; missing reference facts are unperformed.

## Explicit exclusions

No participant motive, accumulation/distribution, liquidity or price-impact judgment, hidden identity resolution, recommendation, or trade action.
