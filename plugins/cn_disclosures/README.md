# pi_sparkles_cn_disclosures

Experimental, read-only mainland-China discovery shell over CNINFO's public
security catalogue and announcement-query surface. It exposes
`cn_security_search` and `cn_disclosure_search`; every result is visibly `cn`
and never borrows an HK or US identity tool.

Set `CNINFO_USER_AGENT_CONTACT` to a non-secret operational contact.
`CNINFO_USER_AGENT_PRODUCT` is optional and defaults to
`pi-sparkles-cn-disclosures/0.1`. Missing/invalid caller identity leaves tools
registered but fail-closed.

The adapter is caller-identified, HTTPS-only, host/path allowlisted,
one-request-per-second, one-in-flight, cancellation-aware, retry-bounded,
20-second/5-MB bounded, and fixture tested. The announcement POST is marked as
a repeatable read only because its form is a public search query.

Both tools retain their identity lookup as a versioned CNINFO catalogue
receipt. The response is captured before decoding and exposes retrieval time,
byte length, body SHA-256, evidence ID/source fingerprint, exact candidates,
and a canonical SHA-256 digest. It proves repository catalogue association for
each returned exact candidate at that retrieval only. Venue, board, share
class, currency, effective listing interval, and trading status remain null;
the digest is content-bound rather than provider-authenticated. It therefore
cannot replace the listing/status evidence required by `cn_ohlcv_gaps`.

Security results preserve the CNINFO code, organization ID, Chinese short name,
category, and pinyin. A six-digit code is a candidate lookup, not proof of SSE,
SZSE, BSE, board, share class, currency, or current listing status. Disclosure
search resolves the exact `(code, organizationId)` catalogue association before
querying and refuses ambiguous candidates unless the caller supplies the exact
organization ID.

Announcement results preserve the CNINFO announcement ID, source time integer,
Chinese title/name, type codes, size, and exact canonical PDF identity. The
source time field is not relabelled as an exchange publication timestamp.
Public visibility permits this experimental read-only local-analysis route; it
does not approve bulk redistribution, commercial products, or an unrestricted
cache. No live request runs in `bun run test`.
