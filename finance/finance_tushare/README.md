# finance_tushare

`finance_tushare` is the provider adapter used to prove that the T1 mainland
market product is not coupled to Eastmoney. It covers `stock_basic`,
`namechange`, unadjusted `daily`, `dividend`, `forecast`, `express`,
`disclosure_date`, and `anns_d` through one bounded adapter contract.

The adapter requires an opaque caller token (normally supplied by a Pi shell
from `TUSHARE_TOKEN`). It places that token only in the actual HTTPS POST body;
request identities, cache keys, diagnostics, and retry accounting receive a
redacted body variant. The package has no ambient environment access and never
persists credentials.

Queries require the `cn` track. Exact-security queries also require an explicit
SSE, SZSE, or BSE exchange; the adapter never infers a venue from a code prefix.
Responses must match the requested field order and identity, remain within the
caller row budget, and preserve numeric JSON tokens as exact strings. Daily
volume is retained in provider lots and amount in thousands of CNY. The adapter
does not adjust prices and does not silently substitute another provider.

Network execution is read-only, POST-repeatable, HTTPS-origin/path allowlisted,
15-second bounded, 2 MB bounded, cancellable, paced, and retry-limited. Unit
tests use fixtures only. Provider access rights, redistribution rights, point
requirements, and freshness remain caller/provider facts rather than product
claims.

Primary contracts:

- <https://tushare.pro/document/1?doc_id=25> (`stock_basic`)
- <https://tushare.pro/document/1?doc_id=27> (`daily`)
- <https://tushare.pro/document/2?doc_id=103> (`dividend`)
- <https://tushare.pro/document/2?doc_id=45> (`forecast`)
- <https://tushare.pro/document/2?doc_id=46> (`express`)
- <https://tushare.pro/document/2?doc_id=162> (`disclosure_date`)
- <https://tushare.pro/document/2?doc_id=176> (`anns_d`)
- <https://www.tushare.pro/document/2?doc_id=130> (HTTP request/response shape)
