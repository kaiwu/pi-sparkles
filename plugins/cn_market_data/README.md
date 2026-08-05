# cn_market_data

Experimental isolated `cn` Pi plugin exposing `cn_stock_quote` and
`cn_stock_history` over the shared `finance_eastmoney` adapter.

The tool requires an exact `sse`, `szse`, or `bse` choice and a six-digit code.
It is scoped to independently proven mainland A-share/CNY identities; the
Eastmoney response does not prove share class or currency. Quote prices retain
the provider's integer scale. History is daily, raw, and unadjusted (`fqt=0`),
and preserves exact numeric response lexemes.

Results visibly report Eastmoney as the vendor origin, direct route, provider
timestamp/retrieval time, local-analysis entitlement, unknown latency/service
level/redistribution rights, unverified volume semantics, and every limitation.
They are not exchange observations and do not silently use AKShare as origin,
though the contract follows the same endpoints used by its Eastmoney functions.

Set non-secret `EASTMONEY_USER_AGENT_CONTACT`; optionally set
`EASTMONEY_USER_AGENT_PRODUCT`. Normal tests never make live requests.
