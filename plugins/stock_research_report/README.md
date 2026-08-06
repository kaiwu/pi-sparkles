# stock_research_report

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`stock_research_report` registers `/us-research` and `us_company_brief`.
The command queues a bounded workflow for the agent to call the existing
Alpaca and SEC tools. The tool then validates and deterministically renders the
selected receipts as a concise US company brief.

This first slice is deliberately network-free and has no environment
variables. It does not duplicate provider clients and Pi's public extension API
does not expose registered tool execution through `getAllTools`; that method
returns metadata only. Consequently the agent performs the tool sequence and
passes exact, uniquely resolved receipt fields into `us_company_brief`.

The compositor accepts at most one latest quote, one bounded OHLCV summary, ten
recent filings, and twenty unique SEC fundamental facts. It validates exact US
identity, dates, decimal tokens, Alpaca feed/source coherence, SEC CIK/source
coherence, accession/document safety, and section budgets. Output retains
direct source links and stable evidence IDs and marks receipt integrity as
`caller_supplied_not_cryptographically_verified`. Ambiguous fundamentals must
remain missing; the report tool does not choose a candidate.

The brief contains source facts and explicit gaps only. It does not generate an
investment thesis, infer freshness/session state, calculate valuation, claim
that a copied receipt is cryptographically authentic, or substitute model
knowledge for a missing tool result.
