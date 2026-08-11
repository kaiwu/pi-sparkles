# pi_sparkles_sec_insiders

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md) and the existing `finance_sec`/`sec_edgar` contracts.

## Reviewed first slice

Decode exact Forms 3/4/5 with issuer/reporting-owner identities, relationship/role flags as filed, transaction/security/ownership codes, direct/indirect nature, date, quantity/price lexemes, post-transaction holdings, derivative terms, footnotes, accession/amendment and source receipt.

Transaction codes and footnotes remain authoritative source facts; acquisitions/disposals are not automatically open-market buys/sells. Amendments, duplicates, late filings and unresolved owner/entity mappings remain explicit.

## Explicit exclusions

No insider intent, legality/timeliness verdict, bullish/bearish signal, realized profit, current holdings guarantee, recommendation, or trade action.

## Implemented T2 import path

The package now exposes `sec_insider_filings` and `sec_insider_record`. Both use the
shared versioned `sec_insiders_v1` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
`us`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
