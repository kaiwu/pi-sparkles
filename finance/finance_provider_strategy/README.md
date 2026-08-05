# finance_provider_strategy

Experimental pure policy for track-isolated provider priority and fallback.
It reuses `finance_http/cache` modes but performs no network, storage, clock,
credential, or Pi effects.

A channel keeps the underlying source separate from its retrieval route. For
example, a document already proven by official metadata to be SSE-issued may
retain SSE origin when retrieved through `Via("CNINFO")`. Raw CNINFO bytes alone
remain CNINFO repository evidence and cannot establish that proof. A plan has
one track and one semantic contract.
Fallback succeeds only when the observed family, identity, freshness, unit,
and adjustment basis exactly match that contract.

Plans reject candidate/unreviewed channels, cross-track channels, duplicate
channel IDs, trust-order inversions, and contract mismatches. Resolution also
requires attempts to follow configured order and stops on a semantically
incompatible success. Every selected value remains wrapped with its channel;
callers must not flatten the source or route into a display string.

This package does not decide whether a public page may be redistributed.
`VerifiedReadOnly` plus `LocalAnalysisOnly` means only that a read-only local
snapshot route was technically approved. Source-specific packages still own
terms, attribution, pacing, cache lifetime, fixture rights, and outage policy.
