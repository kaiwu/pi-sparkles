# pi_sparkles_cn_stock_history

Status: **Designing** · thin source slice · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Return bounded raw, unadjusted Eastmoney daily OHLCV rows for one exact caller-resolved mainland listing and inclusive date range. Preserve raw and normalized lexemes, date/time basis, provider market code, currency, unknown volume unit/session semantics, pagination, page receipts, entitlement/licence, duplicates, omissions and decode failures.

The plugin reuses `finance_eastmoney`, `finance_ohlcv`, and shared HTTP. It neither authenticates Eastmoney as exchange evidence nor fills a calendar gap. Adjustment remains explicitly `RawUnadjusted`; any later factor projection needs separate corporate-action evidence.

## Explicit exclusions

No adjusted series, returns, intraday bars, completeness/freshness verdict, suspension inference, repair/interpolation, provider fallback, recommendation, or trade action.
