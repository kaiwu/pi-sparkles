# pi_sparkles_cn_stock_research_report

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

The package now implements a bounded content-bound CN report packet. Its pure
core validates exact mainland identity, allowed section kinds, fact states,
source handles, hashes, conflicts, omissions, and original/translation lineage.
Chinese originals are mandatory for un-translated sections; any other language
must identify its controlling Chinese section, translator, time, and source
span. Paging and drill-down never invent narrative or fill missing sections.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 26](../../../trading-course/sessions/26_peer_valuation_industry_research_contract_20260811.md).

## Reviewed first slice

`inspect_report` deterministically composes caller-selected CN identity, disclosure, financial, peer, comparable, valuation and industry receipts into a sectioned company-research packet. It exposes section identities, exact claims/facts, source links, calculations, assumptions, conflicts, omissions, and content hashes.

Chinese originals remain controlling. Any English text is a separately labelled translation with translator/model, time, source span, and correction lineage. A missing section stays missing; source authority and vendor-derived metrics remain distinguishable. Compact output gives section/language/omission counts and drill-down handles.

The composition core is pure and consumes completed receipts; it does not fetch, select evidence, generate new assumptions, or turn prose into an investment conclusion.

## Explicit exclusions

No automatic report narrative, source substitution, uncited statement, translation presented as original, completeness/quality grade, peer or valuation selection, thesis verdict, recommendation, rating, or target price.
