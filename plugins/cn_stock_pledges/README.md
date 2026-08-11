# pi_sparkles_cn_stock_pledges

Status: **Designing** · disclosure-information contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Return disclosed share pledge, release and freeze events for one exact CN issuer/listing. Preserve pledgor/holder labels, pledgee/court where disclosed, share class, quantity/percentage/denominator lexemes, start/end/event/publication dates, purpose/status, controlling-holder flag only when sourced, correction lineage and receipts.

Events are append-only and never collapsed into a current balance without an explicit complete fold. Holder identity ambiguity, missing releases and incompatible denominators remain visible.

## Explicit exclusions

No default probability, distress/control/concentration judgment, causal price implication, complete exposure claim, recommendation, or trade action.
