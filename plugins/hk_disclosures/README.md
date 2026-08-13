# pi_sparkles_hk_disclosures

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Experimental, read-only Hong Kong shell over HKEXnews's public security-prefix
and listed-company title-search surfaces plus HKEX's official Full List of
Securities. It exposes `hk_security_search`, `hk_security_profile`,
`hk_recent_listing_event`, and `hk_disclosure_search`; every result is visibly
`hk` and cannot borrow a CN or US identity surface.

Set the shared non-secret `AGENT_CONTACT` operator identity.
The outbound product label is fixed as `pi-sparkles-hk-disclosures/0.1`.
Missing/invalid identity leaves tools
registered but fail-closed.

The adapter is caller-identified, HTTPS-only, host/path allowlisted,
one-request-per-second, one-in-flight, cancellation-aware, retry-bounded, and
20-second bounded for discovery; the separate Full List request is bounded to
30 seconds and 2 MB, and the recent-listing page to 30 seconds and 4 MB.
Security JSONP is unwrapped only for the pinned callback and decoded as JSON.
Title-search and recent-listing HTML are fixture-tested against semantic
markers, and exact document paths are revalidated by `finance_hkex`.

`hk_security_search` and the identity leg of `hk_disclosure_search` retain the
lookup as a versioned current-security receipt.
The receipt captures the exact HKEXnews response before decoding and exposes
retrieval time, byte length, body SHA-256, evidence ID/source fingerprint,
exact candidates, and a canonical SHA-256 digest. It proves current catalogue
membership for each returned exact candidate at that retrieval only; the raw
provider `more` marker is retained with unknown semantics. Its board, share
class, currency, effective
listing interval, and trading status fields are deliberately null, and its
digest is not provider authentication. Consequently this receipt cannot yet
replace the effective listing/status evidence required by `hk_ohlcv_gaps`.

`hk_security_profile` captures the official XLSX bytes and source SHA-256
before a reviewed exact-entry, in-memory ZIP decode. It returns the workbook
update date and exact current category/sub-category, board lot, ISIN,
expiry/eligibility/debt fields, spread table, trading currency, and RMB counter,
plus entry lengths/CRCs and a canonical receipt. Archive and decompression
budgets are explicit; unsafe names, encryption, ZIP64, unsupported compression,
length/CRC drift, invalid UTF-8, and cancellation fail closed. Main Board/GEM is
derived only from an exact source label. Listing start/end and trading status
remain null because the workbook does not prove them, so this receipt also
cannot replace `hk_ohlcv_gaps` listing/status evidence.

`hk_recent_listing_event` captures the exact public HKEX newly-listed page
before decoding its rolling current-two-week table. It preserves the stated
page update date and exact event date/tentative marker, short name, code, board
lot, four eligibility markers, corporate action, and related code. Only an
exact non-tentative `New Listing` row yields `listingEffectiveFrom`. Tentative
dates and other actions fail closed to null; listing end and trading status are
always null. A no-match result says nothing about dates outside the rolling
window, so the receipt is not wired into `hk_ohlcv_gaps` as general historical
listing evidence.

The title page is a public end-user search surface, not a documented bulk API.
The adapter returns at most the initial 100 rendered rows, reports the site's
total count, and marks truncation. It preserves multi-counter codes/names,
source release text, headline HTML, title, displayed file size, and canonical
PDF identity. It does not claim historical completeness or decode arbitrary
HTML entities beyond the declared fixture contract.

HKEX states that issuer materials are public information but are not verified
by HKEX, and warns that reproduction/distribution/linking can require consent.
This package therefore approves only bounded read-only local analysis;
redistribution, commercial products, and unrestricted caching remain
unapproved. No live request runs in `bun run test`.
