# pi_sparkles_global_markets

Tier 5 ProductUseful, stateless Pi shell over the pure `finance_multi_asset`
contract. It registers `global_markets_compare` and accepts one bounded caller-owned,
versioned JSON packet plus its expected SHA-256 digest.

The first slice validates exact labelled CN/HK/US index, ETF, equity or ADR legs, open-session intersection, unmatched points, native-currency returns, rebasing and correlation. Every result retains exact source,
time, entitlement, licence, correction and receipt context. The input digest
binds the imported bytes and the result receipt, but is not a provider
signature, authority proof or origin authentication.

The shell owns only bounded UTF-8 import, cancellation and Pi presentation.
Domain decoding, validation and calculations remain pure Gleam. There is no
ambient credential, network fallback, storage or cross-plugin source import.

No synthetic global track, index/ETF equivalence, silent FX, stale carry, ranking, causal claim or recommendation.

Focused package builds are inner-loop diagnostics only. Product usefulness is
decided once by the complete T5 multi-asset researcher acceptance lane.
