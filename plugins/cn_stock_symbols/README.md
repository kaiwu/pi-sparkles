# pi_sparkles_cn_stock_symbols

Status: **Implemented in ProductUseful T1** · identity contract

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 2](../../../trading-course/sessions/02_four_traders_20260326.md) and [Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Search and resolve Chinese legal/short/historical names and exact six-digit source codes into candidate listing identities with `cn` track, SSE/SZSE/BSE MIC, board, security/share class, effective aliases, and sourced A/B/H/CDR relationships.

A symbol or code alone never proves venue, board, class, currency, current status or cross-listing. Search returns bounded candidates and ambiguity; resolution requires caller selection or unique evidence. Alias/name changes retain effective intervals and receipts. The pure identity core composes `finance_cn_identity`/`finance_listing`; source adapters are separate.

## Explicit exclusions

No guessed MIC/board, silent historical-to-current substitution, global fallback, issuer/listing collapse, preferred share class, recommendation, or market-data fetch.

## Implemented T1 scope

`cn_stock_symbol_search` performs either an exact code search with a mandatory
venue or a name search with an optional venue. It preserves zero/unique/multiple
candidate resolution and returns bounded Tushare `stock_basic` candidates with
short/legal names, pinyin, provider market/exchange, mapped MIC/board, currency,
status, and listing dates. Every venue/board field is visibly vendor-reported or
mapped from exact provider labels; it is not exchange-authenticated.
The visible tool schema and prompt state the conditional requirement explicitly:
code mode cannot discover a venue from a bare code, and name mode is not a
fallback for missing venue evidence. This is a single-query Tushare operation,
not a per-row batch enrichment surface; both modes require caller-owned
`TUSHARE_TOKEN` and the applicable provider permission. Tushare may impose a
much smaller account-specific `stock_basic` quota than its generic published
limits. Provider code `40203` is therefore surfaced as an explicit quota or
permission rejection with no retry/fallback, never as invalid listing rows.
Composition should reuse an already returned symbol receipt and must not fan out
or issue code-to-name workaround calls.

`cn_stock_alias_history` requires an already resolved venue/code plus upstream
identity-evidence reference and returns every `namechange` row with separate
effective-start, effective-end, announcement-date, and original Chinese reason.
Missing dates stay unknown and aliases are never substituted into current
identity. Cross-listing and issuer relationships remain unsupported rather than
guessed. Both operations use a caller-owned `TUSHARE_TOKEN` and content-bound
receipts.
