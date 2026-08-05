# cn_market_rules

Track-isolated Pi tool `cn_trading_rules` for the source-reviewed rule set that
became effective on 2026-07-06. It supports only established, normally traded
CNY A-shares on exact SSE Main, SSE STAR, SZSE Main, SZSE ChiNext, or BSE
board/venue pairs. It returns exact source URLs and clauses, tick size, standard
daily price-limit ratio, quantity constraints, odd-lot exit policy, and visible
limitations.

The tool rejects historical dates, invalid board/venue pairs, and exceptional
IPO, relisting, delisting, warning, suspension, block, after-hours, and Connect
regimes. It does not convert a standard price-limit ratio into an order price or
claim settlement/eligibility rules. Source redistribution rights remain unknown.
