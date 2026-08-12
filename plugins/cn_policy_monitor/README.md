# pi_sparkles_cn_policy_monitor

Tier 5 ProductUseful, stateless Pi shell over the pure `finance_multi_asset`
contract. It registers `cn_policy_documents` and accepts one bounded caller-owned,
versioned JSON packet plus its expected SHA-256 digest.

The first slice validates bounded original-language mainland policy documents, exact publishers/dates, correction lineage, rights and receipts. Every result retains exact source,
time, entitlement, licence, correction and receipt context. The input digest
binds the imported bytes and the result receipt, but is not a provider
signature, authority proof or origin authentication.

The shell owns only bounded UTF-8 import, cancellation and Pi presentation.
Domain decoding, validation and calculations remain pure Gleam. There is no
ambient credential, network fallback, storage or cross-plugin source import.

No translation substitution, legal conclusion, policy-impact prediction or recommendation.

Focused package builds are inner-loop diagnostics only. Product usefulness is
decided once by the complete T5 multi-asset researcher acceptance lane.
