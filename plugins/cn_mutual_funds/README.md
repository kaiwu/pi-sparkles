# pi_sparkles_cn_mutual_funds

Tier 5 ProductUseful, stateless Pi shell over the pure `finance_multi_asset`
contract. It registers `cn_mutual_fund_analyze` and accepts one bounded caller-owned,
versioned JSON packet plus its expected SHA-256 digest.

The first slice validates mainland mutual-fund and share-class identity, dated holdings, NAV return, fee drag, rights and source receipts. Every result retains exact source,
time, entitlement, licence, correction and receipt context. The input digest
binds the imported bytes and the result receipt, but is not a provider
signature, authority proof or origin authentication.

The shell owns only bounded UTF-8 import, cancellation and Pi presentation.
Domain decoding, validation and calculations remain pure Gleam. There is no
ambient credential, network fallback, storage or cross-plugin source import.

No listed-market proxy, stale holding fill, performance verdict, share-class recommendation or account effect.

Focused package builds are inner-loop diagnostics only. Product usefulness is
decided once by the complete T5 multi-asset researcher acceptance lane.
