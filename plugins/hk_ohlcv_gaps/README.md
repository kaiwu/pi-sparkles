# hk_ohlcv_gaps

Experimental, network-free Pi plugin for Hong Kong. It registers
`hk_ohlcv_gap_assessment`, which consumes the exact `gapAssessmentReceipt`
emitted by `hk_stock_ohlcv` plus an independently repeated listing identity,
effective interval, listing reference, and per-gap market-status receipts.

The copied receipt is HK-specific and SHA-256-bound: fixed HK/XHKG scope,
board, share class, declared currency, five-digit code, range, Eastmoney row
limit/source, retrieval time, coverage state, ordered bar dates, and the
response page's byte length, optional request ID, and body hash all participate
in the canonical digest. Any changed field fails before classification.

Only complete provider coverage can be assessed. The pure engine walks each
civil date against the exact 2026 HKEX planned securities calendar and returns
separate market-closure, suspension, provider-omission, and unavailable-history
states with all applicable evidence legs. Published half-day dates remain in
the calendar receipt, but a daily row does not prove intraday completeness.

No environment variables or runtime network access are used. The digest proves
copy coherence, not Eastmoney origin; listing and status references remain
caller supplied and unverified. Volume, amount, turnover, adjustments,
corporate actions, later calendars, exceptional notices, and redistribution
rights remain outside this slice.
