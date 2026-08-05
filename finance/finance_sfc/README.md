# finance_sfc

Experimental read-only adapter for the Hong Kong Securities and Futures
Commission's official public press-release RSS feed:
<https://www.sfc.hk/en/RSS-Feeds/Press-releases>.

The package requires a product/contact user agent, constructs a GET request
with a 15-second/1-MB bound, and uses the shared authority runtime at one
admission per second, one concurrent request, two retry attempts, and a bounded
50-request queue. Cancellation and the exact SFC host/path allowlist are
enforced below retry, so every retry consumes another admission.

Responses are retained first as unmodified UTF-8 XML and hashed into HK-track
SFC evidence. Accepted media types are `application/rss+xml`,
`application/xml`, and `text/xml`. The adapter does not yet parse RSS items,
infer publication time, translate content, or treat press releases as issuer
filings or market data.

Access is technically verified for a local read-only snapshot only. Evidence
is `NoRedistribution`; public visibility is not a bulk-copy or redistribution
grant. Tests construct fixture responses and injected policies and perform no
live requests.
