# hk_market_data

Experimental isolated `hk` Pi plugin exposing `hk_stock_quote` and
`hk_stock_history` over the shared `finance_eastmoney` adapter.

Every call requires a five-digit HK code and an explicit `HKD`, `CNY`, or `USD`
currency that must be independently proven for the listing/counter. The vendor
payload does not establish currency, so the result labels it
`caller_declared_not_provider_verified` instead of assuming HKD. Quote prices
retain the provider's integer scale. History is daily, raw, and unadjusted
(`fqt=0`) and preserves exact numeric response lexemes.

Results visibly report Eastmoney as vendor origin, direct route, provider and
retrieval timestamps, local-analysis entitlement, unknown latency/service
level/redistribution rights, unverified volume semantics, and all limitations.
They are not HKEX observations and do not borrow the CN shell.

Set non-secret `EASTMONEY_USER_AGENT_CONTACT`; optionally set
`EASTMONEY_USER_AGENT_PRODUCT`. Normal tests never make live requests.
