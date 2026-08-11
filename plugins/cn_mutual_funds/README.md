# pi_sparkles_cn_mutual_funds

Status: **Designing** · provider/licence gated · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 34](../../../trading-course/sessions/34_fund_etf_mutual_fund_contract_20260811.md).

## Reviewed first slice

Tools inspect an exact mainland mutual-fund share class, return official daily NAV, dealing/subscription/redemption/settlement facts, fee and distribution policy, calculate requested NAV returns or fee impact, and page top holdings from the latest disclosed report.

Fund and share-class identities never collapse; listed-price fields are absent rather than borrowed from ETFs. NAV facts retain valuation/publication dates, currency, accumulating/distributing basis and corrections. Holdings retain report period/publication time, top-N completeness, look-through limits, rights and receipts. Survivorship and historical universe status remain explicit.

Pure fund calculations are separated from bounded provider adapters and preserve exact source lexemes.

## Gates and exclusions

Requires reviewed fund-company/distributor sources and rights; full holdings may be licensed. No market-price/NAV equivalence, default peer group, risk rating, manager/fund quality judgment, survivorship claim, suitability, recommendation, or transaction effect.
