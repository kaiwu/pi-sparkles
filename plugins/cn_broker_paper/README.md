# pi_sparkles_cn_broker_paper

Status: **Experimental implementation — owned by T6** · named local simulation plus external receipt review

The package exposes two non-executing CN operations:

- `simulate_cn_tape_possible_fill` runs the shared
  `transaction_tape_possible_fill_v1` model over an exact limit instruction and
  bounded external CN tape. It retains eligible/excluded prints, sequence and
  condition limitations, and both compatible non-fill and possible-fill-up-to
  branches. It never claims queue position or an observed fill.
- `review_cn_paper_evidence` reviews bounded externally produced paper-account,
  order, fill, capability, entitlement, and lifecycle evidence.

Exact XSHG/XSHE/XBSE identity plus rule, capability, account, provider, and
content receipts are required. Providers, SDKs, credentials, transports, and
broker-hosted mutation are external and unbundled.

Focused checks live in `finance_execution` and
`test/binding/broker_paper.test.js`.
