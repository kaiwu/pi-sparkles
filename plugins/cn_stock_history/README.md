# pi_sparkles_cn_stock_history

Status: **Implemented in ProductUseful T1** · provider-adaptable source product

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## T1 provider contract

Return bounded daily OHLCV rows for one exact caller-resolved mainland listing,
inclusive date range and explicitly selected provider adapter. Eastmoney is the
working raw/unadjusted first adapter; Tushare Pro is the second mainstream
adapter/conformance proof. Preserve raw and normalized lexemes, date/time basis,
provider market code, currency, adjustment, volume/session semantics,
pagination, page receipts, entitlement/licence, duplicates, omissions and
decode failures without pretending the two sources have identical fields.

The plugin-facing request/result and canonical provider port remain stable.
Provider-specific request plans and decoders map into `finance_ohlcv` only after
their own identity, time, adjustment and unit facts pass conformance tests.
Eastmoney uses `EASTMONEY_USER_AGENT_CONTACT` and optional product identity;
Tushare Pro reads caller-owned `TUSHARE_TOKEN` only from the runtime or opt-in-
test environment. No credentials enter source receipts or persisted state.

The implemented `cn_stock_history` tool exposes one stable request/result
contract with an explicit `provider: eastmoney | tushare`. It requires `cn`, an
exact venue and six-digit code, `a_share`, an upstream identity-evidence
reference, an inclusive date range, and a common 1–1000 row budget. The selected
adapter is the only adapter called. Each successful response produces a shared
`finance_ohlcv` acquisition receipt with exact listing fields, raw-unadjusted
state, response byte length and content SHA-256; the receipt is explicitly
content-bound rather than provider-authenticated.

Provider differences remain visible. Eastmoney volume and amount units are
unknown; Tushare volume is retained as provider `手` lots and amount as thousand
CNY. Eastmoney-specific amplitude/turnover fields and Tushare-specific previous
close/change fields are preserved under `providerFields`. Rows retain provider
order and exact numeric lexemes.

After successful schema validation, the shell appends the bounded redacted
request identity and exact provider response to the shared branch-local cache
ledger. The cache receipt preserves its original source/rights/timestamps and
does not change the market-data result or authorize silent fallback.

The Eastmoney adapter remains `RawUnadjusted` and vendor evidence, not exchange
evidence. Tushare fields retain their independently proven semantics. Neither
adapter fills a calendar gap, and provider failure never triggers silent
fallback. Any adjustment projection needs separate corporate-action evidence.

## Explicit exclusions

No invented adjustment equivalence, returns, intraday bars, completeness/
freshness verdict, suspension inference, repair/interpolation, automatic
provider fallback, recommendation, or trade action. More adapters add focused
conformance coverage, not another T1 role journey.
