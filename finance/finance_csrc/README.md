# finance_csrc

Experimental read-only adapter for three allowlisted mainland China Securities
Regulatory Commission public publication pages:

- [securities-market monthly reports](https://www.csrc.gov.cn/csrc/c100120/common_list.shtml);
- [securities-market weekly reports](https://www.csrc.gov.cn/csrc/c100119/common_list.shtml);
- [public-consultation feedback](https://www.csrc.gov.cn/csrc/c100114/common_list.shtml).

The package requires a product/contact user agent and constructs GET requests
with a 15-second/2-MB bound. Its shared authority runtime admits one request per
second, allows one concurrent request, makes at most two retry attempts, and
has a bounded 50-request queue. Cancellation and the exact CSRC origin/path
allowlist apply to every attempt.

Responses are retained first as unmodified UTF-8 HTML and hashed into CN-track
CSRC evidence. There is intentionally no selector/CSS scraper or normalized
record decoder yet: the official pages are public publication surfaces, not a
documented JSON API. A future decoder must be fixture-tested and must fail on
layout drift rather than returning partial invented records.

Access is approved only for local read-only snapshots. Evidence is
`NoRedistribution`; page visibility does not establish fixture or bulk
redistribution rights. Normal tests construct responses and never make live
requests.
