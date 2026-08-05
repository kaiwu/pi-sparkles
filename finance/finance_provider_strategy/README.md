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

## Multi-channel coverage

`finance_provider_strategy/coverage` implements the operational breadth gate.
The standard policy is **8,500 basis points (85%) for each applicable data
family**, computed over a declared, versioned requirement denominator. Coverage
is the set union of accepted channel contributions, so overlapping observations
are counted once.

The policy deliberately does not claim that 85% from several channels is a
mathematically complete dataset. It makes the remaining uncertainty auditable:

- every family is assessed independently; scores cannot be averaged across
  identity, calendar, quotes, disclosures, fundamentals, news, or other
  families;
- family-owned critical requirements remain mandatory even above 85%;
- the report retains covered and missing requirement IDs;
- each channel is track-prefixed and source groups represent underlying origins,
  so direct and mirrored routes from the same origin count as one group;
- a family chooses its minimum independent source-group count. One canonical
  authority can be sufficient for an official artifact, while a composite
  research picture can require two or more groups;
- `picture` advances only when every applicable family passes. It has no
  blended average and never imputes the permitted gap.

Coverage is not accuracy, recency, entitlement, or semantic compatibility.
Only observations already accepted by those separate contracts may contribute.
Conflicts stay conflicts and uncovered facts stay unknown.

## Source credibility receipts

`finance_provider_strategy/credibility` provides a separate, auditable source
control score. Callers declare a versioned source-set ID and stable criteria;
each criterion is `Verified` (100%), `Partial` (50%), or `Missing` (0%). The
receipt retains the criterion importance, level, and evidence text. Equal
weights make the calculation inspectable and prevent callers from assigning a
persuasive arbitrary percentage to one criterion.

The standard gate is 8,500 basis points, and every critical criterion must be
fully verified. The result is an **evidence-maturity percentage**, not a
probability that a source statement is true. It must not be combined with
feature coverage, used to erase conflicts, or substituted for freshness,
semantic decoding, fixture validation, entitlement, or independent
corroboration. Adding or removing criteria requires a new source-set version.

This package does not decide whether a public page may be redistributed.
`VerifiedReadOnly` plus `LocalAnalysisOnly` means only that a read-only local
snapshot route was technically approved. Source-specific packages still own
terms, attribution, pacing, cache lifetime, fixture rights, and outage policy.
