# pi_sparkles_fx_ecb

Tier 5 ProductUseful, stateless Pi shell over the pure `finance_multi_asset`
contract. It registers `ecb_fx_calculate` and accepts one bounded caller-owned,
versioned JSON packet plus its expected SHA-256 digest.

The first slice validates same-date ECB euro-reference cross, inverse and amount conversion with publication, TARGET-calendar, rights and receipts. Every result retains exact source,
time, entitlement, licence, correction and receipt context. The input digest
binds the imported bytes and the result receipt, but is not a provider
signature, authority proof or origin authentication.

The shell owns only bounded UTF-8 import, cancellation and Pi presentation.
Domain decoding, validation and calculations remain pure Gleam. There is no
ambient credential, network fallback, storage or cross-plugin source import.

Rates are non-executable references. No stale carry, silent provider fallback, FX view or trading advice.

Focused package builds are inner-loop diagnostics only. Product usefulness is
decided once by the complete T5 multi-asset researcher acceptance lane.
