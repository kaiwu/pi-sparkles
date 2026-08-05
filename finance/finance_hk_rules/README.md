# finance_hk_rules

Experimental pure Hong Kong rule vocabulary and strict selection over
`finance_market_rules`. Rules are keyed to one exact HK listing and selected by
security type, market status, and inclusive effective date.

The package deliberately contains no authoritative HKEX constants yet. Board
lots, ticks, settlement and other constraints are injected from source-reviewed
tables. They are never borrowed from mainland or US behavior; unknown and
overlapping rules fail closed.
