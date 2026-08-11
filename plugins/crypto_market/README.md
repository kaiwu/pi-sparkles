# pi_sparkles_crypto_market

Status: **Designing** · provider/licence/security gated · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 38](../../../trading-course/sessions/38_crypto_market_information_contract_20260811.md).

## Reviewed first slice

Tools resolve asset/network/token/contract/venue-instrument identity and return one venue's spot quote, trades, candles, order-book snapshot, venue status, derivative funding context, and fork/airdrop/migration/delisting events. Explicit caller requests may calculate returns, spreads or time-aligned cross-venue differences over supplied facts.

Identity layers never collapse; symbol collisions, forks and migrations return alternatives. Observations retain 24/7 UTC interval semantics, venue/feed, sequence/gaps, quote/base units, fees, stablecoin classification, entitlement/licence and exact receipt. Stablecoin is not fiat; funding/OI context remains a separately labelled derivative leg.

Pure `finance_crypto` types/calculations remain independent of per-venue bounded adapters and a thin Pi shell. No wallet/withdrawal capability is permitted.

## Gates and exclusions

Requires reviewed CEX/DEX terms, data entitlement, source security and credential scopes. No venue/custody/solvency/safety judgment, regulatory classification, fair value, arbitrage/liquidity claim, funding signal, recommendation, wallet key, or trade action.
