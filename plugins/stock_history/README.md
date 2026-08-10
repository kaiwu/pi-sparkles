# stock_history

Experimental provider-neutral Pi plugin for inspecting one exact, bounded daily
OHLCV series on the `cn`, `hk`, or `us` track.

The `stock_bars` tool accepts caller or provider-adapter facts. It validates the
explicit track/MIC scope, exact decimal lexemes, daily bar geometry and order,
time basis, adjustment declaration, pagination state, calendar gaps, source
receipt hash, entitlement, and licence. It returns a bounded page while keeping
the full validated batch count visible.

This first slice is deliberately network-free. It does not resolve identities,
select or call a provider, infer a calendar, authenticate a receipt, repair
gaps, adjust prices, compute returns, interpret signals, rank securities, or
trade. A session-date anchor is an ordering device, not a provider timestamp.
Calendar-assessed gaps are caller or provider-adapter claims unless their
evidence can be checked independently.
