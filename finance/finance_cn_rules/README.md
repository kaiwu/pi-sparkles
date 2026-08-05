# finance_cn_rules

Experimental pure mainland-China rule vocabulary and strict selection over
`finance_market_rules`. Rules are keyed to an exact CN listing and selected by
security type, market status, and inclusive effective date.

The package deliberately contains no authoritative exchange constants yet.
Callers inject source-reviewed tables. Unknown or overlapping rules fail
closed; normal, special-treatment, delisting-risk, and suspended states are not
interchangeable, and no universal price-limit assumption is made.
