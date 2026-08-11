# pi_sparkles_industry_research

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 26](../../../trading-course/sessions/26_peer_valuation_industry_research_contract_20260811.md).

## Reviewed first slice

`inspect_industry` validates and composes caller/provider-supplied industry evidence: exact taxonomy/version/code, market structure, participants, value-chain legs, capacity/supply-demand measures, regulatory documents, dated metrics, competitor identities, source language, coverage, revisions, and omissions.

Every statement links to independent source receipts and information states. Conflicting taxonomies/sources remain separate. Compact output lists covered/missing sections and bounded drill-down; it does not convert facts into Porter scores or attractiveness judgments.

The provider-neutral core validates identity, evidence and completeness declarations without Pi or HTTP. Future source adapters must be independently licensed, bounded, cancellable, fixture-tested, and use `finance_http`.

## Gates and exclusions

Provider/source/licence choices remain open. No attractiveness, moat/barrier/rivalry grade, industry forecast, causal claim, peer selection, investment implication, recommendation, or completeness claim beyond explicit coverage receipts.

## Implemented T2 import path

The package now exposes `industry_research` and `industry_research_record`. Both use the
shared versioned `industry_research_v1` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
`us`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
