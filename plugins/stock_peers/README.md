# pi_sparkles_stock_peers

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

The package now validates a content-bound caller-defined target, universe,
evidence date, and predicate set. Its pure engine retains every candidate and
derives only three mechanical states: accepted when every predicate is observed
true, rejected when any predicate is observed false, and unresolved when facts
are unknown or conflicting. It provides stable paging and per-candidate drill
down with all source receipts; it never discovers, ranks, or chooses peers.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 26](../../../trading-course/sessions/26_peer_valuation_industry_research_contract_20260811.md).

## Reviewed first slice

`inspect_peer_set` accepts a caller-supplied target, candidate universe, evidence date, and explicit predicates. It returns every candidate as accepted, rejected, or unresolved with per-predicate facts, exact identities, classifications, currencies, fiscal periods, source receipts, duplicates/conflicts, and stable drill-down handles.

The plugin validates and projects the caller's criteria; it never discovers, ranks, weights, or silently removes peers. Missing facts produce unresolved predicates. A pure core composes listing/track, evidence, and exact predicate types; the Pi shell performs no provider fetch in the first slice.

Acceptance covers fiscal/currency/share-class mismatches, absent facts, overlapping classifications, caller additions/removals, duplicate candidates, stable receipts, and full preservation of rejected/unresolved rows.

## Explicit exclusions

No “right peers,” similarity score, default filters, peer recommendation, comparability verdict, valuation, industry attractiveness, or investment conclusion.
