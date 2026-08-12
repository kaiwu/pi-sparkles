# pi_sparkles_cftc_cot

Tier 5 ProductUseful, stateless Pi shell over the pure `finance_multi_asset`
contract. It registers `cot_analyze` and accepts one bounded caller-owned,
versioned JSON packet plus its expected SHA-256 digest.

The first slice validates exact CFTC report identity, reporting/release lag, categories, revisions, crosswalk limits, net/change/net-percent/percentile/z-score calculations. Every result retains exact source,
time, entitlement, licence, correction and receipt context. The input digest
binds the imported bytes and the result receipt, but is not a provider
signature, authority proof or origin authentication.

The shell owns only bounded UTF-8 import, cancellation and Pi presentation.
Domain decoding, validation and calculations remain pure Gleam. There is no
ambient credential, network fallback, storage or cross-plugin source import.

No category equivalence inference, suppressed-value fill, positioning signal, forecast or recommendation.

Focused package builds are inner-loop diagnostics only. Product usefulness is
decided once by the complete T5 multi-asset researcher acceptance lane.
