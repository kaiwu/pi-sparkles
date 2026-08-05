# pi_sparkles_hk_disclosures

Experimental, read-only Hong Kong discovery shell over HKEXnews's public
security-prefix and listed-company title-search surfaces. It exposes
`hk_security_search` and `hk_disclosure_search`; every result is visibly `hk`
and cannot borrow a CN or US identity surface.

Set `HKEX_USER_AGENT_CONTACT` to a non-secret operational contact.
`HKEX_USER_AGENT_PRODUCT` is optional and defaults to
`pi-sparkles-hk-disclosures/0.1`. Missing/invalid identity leaves tools
registered but fail-closed.

The adapter is caller-identified, HTTPS-only, host/path allowlisted,
one-request-per-second, one-in-flight, cancellation-aware, retry-bounded, and
20-second bounded. Security JSONP is unwrapped only for the pinned callback and
decoded as JSON. Title-search HTML is fixture-tested against semantic markers,
and exact document paths are revalidated by `finance_hkex`.

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
