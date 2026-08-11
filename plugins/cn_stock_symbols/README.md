# pi_sparkles_cn_stock_symbols

Status: **Designing** · identity contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 2](../../../trading-course/sessions/02_four_traders_20260326.md) and [Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Search and resolve Chinese legal/short/historical names and exact six-digit source codes into candidate listing identities with `cn` track, SSE/SZSE/BSE MIC, board, security/share class, effective aliases, and sourced A/B/H/CDR relationships.

A symbol or code alone never proves venue, board, class, currency, current status or cross-listing. Search returns bounded candidates and ambiguity; resolution requires caller selection or unique evidence. Alias/name changes retain effective intervals and receipts. The pure identity core composes `finance_cn_identity`/`finance_listing`; source adapters are separate.

## Explicit exclusions

No guessed MIC/board, silent historical-to-current substitution, global fallback, issuer/listing collapse, preferred share class, recommendation, or market-data fetch.
