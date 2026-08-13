# hk_fundamentals

Experimental isolated `hk` Pi plugin exposing `hk_financial_statement`,
`hk_stock_fundamental`, and `hk_stock_fundamental_metric` over the shared,
bounded `finance_eastmoney` adapter.

The initial audited vendor slice accepts an exact five-digit HK code and report
end. It fetches a provider report-context index and exact-period income lines,
then rejects code, name, organization, report-end, start, fiscal-year, or report
type incoherence. It preserves exact JSON number tokens for every numeric line;
null amounts remain explicitly unavailable and are never treated as zero.
The executable registry maps only revenue (`004001001`, `营业额`) and
shareholder-attributable profit (`004025002`, `股东应占溢利`). Net margin retains
the formula, raw leaves, mappings, period, provider-reported currency/accounting
standard/report type, scale, half-even rounding, and assumptions.

This is vendor data, not HKEXnews filing evidence. Source document, notice and
version identity, full statement scope, audit/restatement state, correction
history, service level, licence, and redistribution rights remain unknown. No
generated or stale fallback exists. Feature coverage measures installed workflow
breadth, not complete statement coverage and not truth probability.

Set the shared non-secret `AGENT_CONTACT`. The plugin supplies its product
label. Requests are read-only, caller-identified,
origin/path/size/time/rate/retry/queue bounded, and cancellable. Normal tests use
fixtures or mocked fetch only.
