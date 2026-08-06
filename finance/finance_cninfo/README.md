# finance_cninfo

Experimental read-only adapter for the
[CNINFO official disclosure repository](https://www.cninfo.com.cn/). It
supports the public six-digit-code catalogue, catalogue-bound announcement
queries, and exact PDF documents. Discovery has a separate allowlisted runtime;
the POST form is a repeatable read with page/page-size/date/category bounds.
Document references construct only the static
`finalpage/YYYY-MM-DD/identifier.PDF` path. Both runtimes apply bounded retry,
cancellation-aware one-per-second pacing, concurrency, response, and queue
limits.

The security catalogue is captured before decoding as a versioned
`pi-sparkles/cninfo-current-security-receipt`. It binds the exact repository
URL, observation/retrieval time, response byte length and SHA-256, provenance
evidence ID/source fingerprint, resolution, and every exact
code/organization/name/category/pinyin candidate into a canonical digest. This
proves the returned association in that CNINFO repository snapshot only. It
does not prove SSE/SZSE/BSE venue origin, board, share class, currency,
effective listing dates, or trading status, and it is not a provider signature.

The adapter retains the original bytes as base64, hashes those bytes with
SHA-256, requires a PDF signature, and records CN-track, `NoRedistribution`
evidence attributed to CNINFO as the repository. Discovery preserves code,
organization ID, Chinese name/title, CNINFO type/time fields, pagination, and
exact PDF identity. It does not interpret the provider time as an exchange
publication time, parse filing semantics, inspect the text layer, or infer that
a filing was issued by SSE, SZSE, or BSE. `capture_inspected` additionally binds
a bounded real-parser page count to the same artifact hash. Venue attribution
requires separate official evidence; a code prefix or caller hint is not proof.

The public route is approved only for bounded read-only local analysis.
Redistribution, commercial products, and unrestricted caching remain
unapproved.

Normal tests use constructed responses and never make live requests.
