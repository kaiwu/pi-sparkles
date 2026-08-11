# pi_sparkles_filing_diff

Status: **Designing** · document-comparison contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 30](../../../trading-course/sessions/30_filing_earnings_company_intelligence_contract_20260811.md).

## Reviewed first slice

`diff_filings`, `list_changed_sections`, and `drill_change` compare two exact filing versions under caller-selected raw or named normalized views and bounded section/table scopes. Results retain document/accession identity, section/table anchors, insert/delete/replace/move facts, raw spans, normalization and diff algorithm versions, amendment/correction lineage, omissions, and content hashes.

Alignment and diffing are pure and deterministic. Normalization never overwrites raw text. Unaligned sections/tables remain explicit; OCR or unsupported attachments fail closed. Outputs are bounded to 100 sections and 10,000 changes with stable paging.

Acceptance covers amendments, moved/renamed sections, table cells, raw versus normalized views, duplicate anchors, unsupported attachments, truncation and receipt stability.

## Explicit exclusions

No semantic/materiality/importance judgment, accounting-policy interpretation, sentiment, causal explanation, completeness claim, recommendation, or automatic monitor update.
