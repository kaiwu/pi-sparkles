# pi_cn_stock_sector_concept

Experimental Session 20 source slice for one exact CAPCO listed-company
industry-classification row. It registers only `cn_industry_classification`.

Input is exact track `cn`, result period `2025-H2`, and one six-digit stock code.
The plugin downloads the reviewed, stock-code-sorted CAPCO PDF through
`finance_capco`, rejects any byte/hash change, extracts the matching row, and
returns:

- the CAPCO 2023 taxonomy name, 2023-05-01 taxonomy effective date, and
  GB/T 4754-2017 reference;
- CAPCO's `2025-H2` result-period label, 2026-04-03 publication date, and exact
  retrieval time as four distinct date facts;
- exact listing code/name, `门类`, `大类`, and manufacturing `次类` when present;
- CN track with MIC and instrument identifier explicitly unknown;
- membership `valid_from` and `valid_to` explicitly unknown;
- source/result/PDF URLs, content hash, parser facts, attribution, and
  no-redistribution rights.

It does not infer a venue from a code prefix, invent a membership interval,
publish `中类`, map to GICS/ICB/SIC/CSRC-2012/vendor taxonomies, expose concept
membership, return the full PDF, judge the classification, or make an investment
decision. A no-match means only that the requested code was not found in this
pinned snapshot.

The implementation follows
[Course Session 20](../../../trading-course/sessions/20_cg_portfolio_classification_source_addendum_20260809.md).

