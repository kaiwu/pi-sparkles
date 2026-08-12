# pi_sparkles_commodities

Tier 5 ProductUseful, stateless Pi shell over the pure `finance_multi_asset`
contract. It registers `commodities_analyze` and accepts one bounded caller-owned,
versioned JSON packet plus its expected SHA-256 digest.

The first slice validates exact futures contracts/specifications, dated curve, calendar and inter-commodity spreads, and a caller-named roll artifact. Every result retains exact source,
time, entitlement, licence, correction and receipt context. The input digest
binds the imported bytes and the result receipt, but is not a provider
signature, authority proof or origin authentication.

The shell owns only bounded UTF-8 import, cancellation and Pi presentation.
Domain decoding, validation and calculations remain pure Gleam. There is no
ambient credential, network fallback, storage or cross-plugin source import.

No anonymous continuous contract, silent FX, structure label, storage inference, forecast or roll recommendation.

Focused package builds are inner-loop diagnostics only. Product usefulness is
decided once by the complete T5 multi-asset researcher acceptance lane.
