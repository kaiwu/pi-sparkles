# finance_market_rules

Experimental provider-neutral validation and strict effective-date selection
for stock-market execution rules. A record belongs to one exact track/MIC
listing and retains its source and optional evidence identity.

The package validates positive tick/lot constraints, price-limit and settlement
shapes, eligibility labels, and overlapping selection. It intentionally owns no
exchange constants. Market packages provide typed security/status vocabulary
and source-reviewed rule tables.

Unknown and overlapping rules are errors. Consumers must not infer a rule from
another listing, board, status, date, or track.
