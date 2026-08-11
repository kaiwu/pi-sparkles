# finance_research_diff

Pure, deterministic, content-bound section comparison for T2 research
workflows. The caller supplies two exact document projections and selects the
raw or `whitespace_v1` view. The engine verifies packet and document hashes,
aligns only exact section identifiers, preserves both raw versions, exposes
insert/delete/replace/move facts, and pages bounded results.

It does not infer semantic equivalence, materiality, importance, or investment
meaning. Unsupported extraction, ambiguous anchors, and incorrect lineage fail
closed before comparison.
