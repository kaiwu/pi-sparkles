# pi_sparkles_cn_stock_announcements

Status: **Designing** · disclosure source slice · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Search and retrieve CNINFO/exchange announcement metadata for one exact mainland issuer/listing. Retain Chinese title and event type, document/repository IDs, issuer organization/code mapping, publication/retrieval times, report period where stated, source URL/receipt, correction/version lineage, attachment metadata, rights, coverage and stable paging.

Retrieval uses the existing CNINFO adapter and reviewed bounded attachment contract. Organization/listing ambiguity, conflicting catalogues, missing documents and unsupported attachments fail closed. Original Chinese remains controlling; translation is a separately labelled derivative.

## Explicit exclusions

No arbitrary archive/OCR, semantic/materiality judgment, completeness-from-no-match, issuer identity guess, summary presented as source text, recommendation, or trading action.
