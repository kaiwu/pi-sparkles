# pi_sparkles_cn_stock_corporate_actions

Status: **Implemented in ProductUseful T1** · structured CN source contract

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md) and [Session 20](../../../trading-course/sessions/20_cg_portfolio_classification_source_addendum_20260809.md).

## Reviewed first slice

Return exact cash/stock dividends, bonus/capitalization issues, rights issues, splits/consolidations, mergers and symbol changes for one resolved mainland listing. Preserve action identity/type, announced terms/ratios/currency, announcement/record/ex-right/ex-dividend/payment/effective dates separately, affected share class, source document, corrections, entitlement and receipts.

CN identity and document rules stay isolated. Conflicting timetables and revised actions remain alternatives with lineage. The source adapter is bounded; projection or adjustment is a separate pure request over exact action facts.

## Explicit exclusions

No inferred adjustment factor, default date/currency, action impact, total-return series, issuer/listing collapse, recommendation, or trade action.

## Implemented T1 scope

The first product-useful source slice uses Tushare Pro's structured `dividend`
endpoint for cash dividends, stock distributions, bonus shares, and
capitalization issues. It preserves proposal/decision/implementation rows rather
than collapsing revisions; retains period, announcement, record, ex, payment,
listing, implementation, and base dates separately; and keeps all numeric JSON
tokens exact. Cash currency is not present in this endpoint and remains unknown.

Rights issues, splits, consolidations, mergers, and symbol changes are explicit
unsupported classes in this adapter and fail closed instead of being inferred
from announcement titles. The caller supplies exact A-share identity evidence;
the tool retains but does not authenticate that reference. `TUSHARE_TOKEN` and
the provider's endpoint permission are runtime dependencies only.
