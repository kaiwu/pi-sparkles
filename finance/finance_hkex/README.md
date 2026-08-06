# finance_hkex

Experimental read-only adapter for [HKEXnews](https://www.hkexnews.hk/) and the
[HKEX Securities Lists](https://www.hkex.com.hk/Services/Trading/Securities/Securities-Lists?sc_lang=en).
It supports the public current-security prefix lookup, listed-company
title-search page, exact PDF documents, and the official current Full List of
Securities XLSX, plus HKEX's rolling current-two-week newly-listed/traded page.
Discovery, documents, the workbook, and recent listings use separate
path-allowlisted runtimes. Security JSONP must use the pinned callback before
JSON decoding; title-search and recent-listing HTML must satisfy fixture-tested
identity, table, update-date, and row markers. The adapter exposes at most the
initial 100 rendered title rows and retains the site's total/truncation receipt.

The current-security lookup is captured before decoding as a versioned
`pi-sparkles/hkex-current-security-receipt`. It binds the exact query URL,
retrieval/observation time, response byte length and SHA-256, provenance
evidence ID/source fingerprint, resolution, and every exact code/name/stock-ID
candidate into a canonical digest. The provider's raw `more` marker is retained
without assigning it undocumented completeness semantics. This is direct
HKEXnews exchange evidence
for current catalogue membership at retrieval only. Board, share class,
currency, listing start/end, and trading/session status remain explicit
unknowns; the digest is content-bound and is not an HKEX signature.

The Full List request is limited to the exact official XLSX path, 2 MB, 30
seconds, one request per second, one in flight, bounded retry, and cancellation.
`pi-sparkles/hkex-current-security-profile-receipt` captures the original bytes
and SHA-256 before `finance_archive` extracts only five required UTF-8 parts.
Archive entry/count/decompression budgets, safe names, no encryption/ZIP64,
store-or-deflate-only compression, length, UTF-8, and CRC-32 are enforced with
no filesystem writes or nested extraction. The pure decoder validates content
types, workbook relationship, fixed headers, and the stated update date before
resolving an exact code. It preserves category, sub-category, board lot, ISIN,
expiry/eligibility/debt fields, spread table, trading currency, and RMB counter.
Main Board/GEM is derived only from the exact source sub-category.

`pi-sparkles/hkex-recent-listing-event-receipt` captures and hashes the public
recent-listing page before a pure exact-code decoder runs. The request is
limited to the exact English page, 4 MB, 30 seconds, one request per second,
one in flight, bounded retry, and cancellation. A listing-start claim is
created only when the exact event is non-tentative and its corporate action is
exactly `New Listing`. The rolling window does not prove historical absence,
and listing end and positive trading/session status remain unknown.

A typed document reference proves Gregorian date, 13-digit identifier shape,
and identifier/date-prefix coherence before constructing the
`listedco/listconews/sehk` path. All runtimes apply bounded retry,
cancellation-aware one-per-second pacing, concurrency, response, and queue
limits.

The adapter retains the original bytes as base64, hashes those bytes with
SHA-256, requires a PDF signature, and records HK-track, `NoRedistribution`
evidence attributed directly to HKEXnews. `capture_inspected` additionally
binds a bounded real-parser page count to the same artifact hash. Discovery
preserves exact HKEXnews stock ID, multi-counter codes/names, release text,
headline HTML, title, displayed size, and canonical PDF identity. It does not
claim a historical listing interval, historical completeness, positive
per-session trading status, filing semantics, or PDF text-layer inspection.
The Full List has no listing-start field, and current membership is not treated
as a positive trading-status assertion.

HKEX's public disclaimer says issuer materials are not verified by HKEX and
restricts reproduction/distribution/linking without consent. The implemented
route is therefore bounded read-only local analysis only; redistribution,
commercial products, and unrestricted caching remain unapproved.

Normal tests use constructed responses and never make live requests.
