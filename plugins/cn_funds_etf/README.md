# pi_sparkles_cn_funds_etf

Status: **Designing** · provider/licence gated · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 34](../../../trading-course/sessions/34_fund_etf_mutual_fund_contract_20260811.md).

## Reviewed first slice

Tools inspect one exact mainland listed fund/share class, return official daily NAV plus independently sourced market price, calculate requested premium/discount or NAV return, and page the latest published top holdings. Identity retains fund/share-class/listing/MIC, legal structure, manager, benchmark, fee lexemes, inception, distribution policy and currency.

NAV, IOPV, market trade/close and adjusted return are different observation kinds with their own date/publication/retrieval times and rights. Holdings retain disclosure vintage, weights/quantities, top-N/full-coverage declaration, omissions and source receipt. Calculations expose formula leaves and never bridge mismatched vintages silently.

Pure fund types/calculations are provider-neutral; bounded adapters retrieve exchange/fund-company data through `finance_http`.

## Gates and exclusions

Requires reviewed public/vendor sources; full holdings may require a licence. No ETF-as-stock equivalence, intraday IOPV or creation basket in the first slice, tracking-quality/risk rating, fund comparison, suitability, recommendation, or trade signal.
