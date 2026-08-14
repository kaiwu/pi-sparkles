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
Nonzero provider envelopes are classified before `data` is decoded because
Tushare may omit or null that field for quota, point, token, parameter, or
permission failures. The typed error retains the original provider message for
controlled diagnostics, while the public renderer emits only a bounded provider
code and remediation categories so a provider message cannot echo credentials
into Pi output. Code `40203` is reported as a caller-account rate/permission
limit, not as malformed market data.

Network execution is read-only, POST-repeatable, HTTPS-origin/path allowlisted,
15-second bounded, 2 MB bounded, cancellable, paced, and retry-limited. Only
transient transport failures and retryable HTTP statuses are eligible for the
second attempt; HTTP-200 provider errors, schema failures, permission failures,
and parameter failures are never retried. Unit tests use fixtures only. Provider
access rights, redistribution rights, point requirements, endpoint-specific
quota windows, completeness, and freshness remain caller/provider facts rather
than product claims. Consumers must avoid fan-out over `stock_basic`; any reuse
or caching must stay explicit and content-bound rather than becoming hidden
mutable adapter state.

Primary contracts:

- <https://tushare.pro/document/1?doc_id=25> (`stock_basic`)
- <https://tushare.pro/document/1?doc_id=27> (`daily`)
- <https://tushare.pro/document/2?doc_id=103> (`dividend`)
- <https://tushare.pro/document/2?doc_id=45> (`forecast`)
- <https://tushare.pro/document/2?doc_id=46> (`express`)
- <https://tushare.pro/document/2?doc_id=162> (`disclosure_date`)
- <https://tushare.pro/document/2?doc_id=176> (`anns_d`)
- <https://www.tushare.pro/document/2?doc_id=130> (HTTP request/response shape)
