# finance_hkex

Experimental read-only adapter for [HKEXnews](https://www.hkexnews.hk/). It
supports the public current-security prefix lookup, listed-company title-search
page, and exact PDF documents. Discovery has a separate path-allowlisted
runtime. Security JSONP must use the pinned callback before JSON decoding;
title-search HTML must satisfy fixture-tested identity and row markers. The
adapter exposes at most the initial 100 rendered rows and retains the site's
total/truncation receipt.

A typed document reference proves Gregorian date, 13-digit identifier shape,
and identifier/date-prefix coherence before constructing the
`listedco/listconews/sehk` path. Both runtimes apply bounded retry,
cancellation-aware one-per-second pacing, concurrency, response, and queue
limits.

The adapter retains the original bytes as base64, hashes those bytes with
SHA-256, requires a PDF signature, and records HK-track, `NoRedistribution`
evidence attributed directly to HKEXnews. `capture_inspected` additionally
binds a bounded real-parser page count to the same artifact hash. Discovery
preserves exact HKEXnews stock ID, multi-counter codes/names, release text,
headline HTML, title, displayed size, and canonical PDF identity. It does not
claim historical completeness, parse filing semantics, or inspect the PDF text
layer.

HKEX's public disclaimer says issuer materials are not verified by HKEX and
restricts reproduction/distribution/linking without consent. The implemented
route is therefore bounded read-only local analysis only; redistribution,
commercial products, and unrestricted caching remain unapproved.

Normal tests use constructed responses and never make live requests.
