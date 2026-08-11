# pi_sparkles_hk_stock_shareholders

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 33](../../../trading-course/sessions/33_hk_stock_track_completion_contract_20260811.md) and Session 11.

## Reviewed first slice

The plugin decodes exact HKEX substantial-shareholder notices for one resolved XHKG listing/share class. Observations retain notice/event identity, holder label and identifiers as disclosed, capacity/nature of interest, share count and percentage lexemes, event and disclosure dates, reason/transaction codes, source language/document, corrections, rights and receipts.

Name similarity never merges holders. Denominators, beneficial/control relationships and percentages remain provider/disclosure facts unless independently evidenced. Duplicates and amended notices are preserved with lineage in an HK-only pure domain.

## Gates and exclusions

Requires HKEX DW/SSD source access and terms review. No beneficial-owner inference beyond disclosures, holder ranking, control/governance/materiality judgment, CN holder substitution, recommendation, or trade action.

## Implemented T2 import path

The package now exposes `hk_shareholder_notices` and `hk_shareholder_notice_record`. Both use the
shared versioned `hk_stock_shareholders_v1` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
`hk`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
