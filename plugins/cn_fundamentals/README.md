# cn_fundamentals

Experimental isolated `cn` Pi plugin exposing `cn_financial_statement`,
`cn_stock_fundamental`, and `cn_stock_fundamental_metric` over the shared,
bounded `finance_eastmoney` adapter.

The initial audited vendor slice accepts an explicit SSE/SZSE/BSE code, exact
report end, and independently verified presentation currency. It preserves
Eastmoney's exact JSON number tokens for `TOTAL_OPERATE_INCOME` and
`PARENT_NETPROFIT`, their original Chinese labels, provider row/report codes,
notice date, and all unknown statement context. The executable normalized
registry maps only revenue and parent-attributable net income. Net margin uses
exact decimal arithmetic and retains its formula, ordered inputs, mappings,
raw leaves, scale, half-even rounding, period, and context.

This is vendor data, not SSE/SZSE/BSE or CNINFO filing evidence. Source document
and version identity, report start, accounting standard, full statement scope,
audit/restatement state, correction history, service level, licence, and
redistribution rights remain unknown. There is no generated or stale fallback.
The feature receipt therefore measures installed workflow breadth, not statement
or issuer completeness and not truth probability.

Set the shared non-secret `AGENT_CONTACT`. The plugin supplies its product
label. Requests are read-only, caller-identified,
origin/path/size/time/rate/retry/queue bounded, and cancellable. Normal tests use
fixtures or mocked fetch only.
