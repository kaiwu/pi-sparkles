# pi_sparkles_cn_stock_indices

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md) and point-in-time laws from [Session 16](../../../trading-course/sessions/16_cg_quant_shared_replay_information_contract_20260807.md).

## Reviewed first slice

Inspect one exact CSI/SSE/SZSE/BSE index identity/methodology and query point-in-time constituents, weights and rebalance events. Facts retain administrator, taxonomy/code, currency, price/total/net-return kind, methodology/version/source, effective and knowledge dates, constituent listing identity, weight/unit, corporate-action treatment, corrections, coverage and receipts.

Membership projection uses canonical point-in-time manifests and preserves entry, exit, re-entry, late, overlapping, unknown and conflicting facts. An index is never equated with an ETF or current constituent list used historically.

## Explicit exclusions

No complete-history claim without coverage, synthetic membership, index replication, fund equivalence, performance interpretation, recommendation, or trading action.

## Implemented T2 import path

The package now exposes `cn_index_records` and `cn_index_record`. Both use the
shared versioned `cn_stock_indices_v1` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
`cn`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
