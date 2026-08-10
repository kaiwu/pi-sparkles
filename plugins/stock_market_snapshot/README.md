# stock_market_snapshot

Experimental provider-neutral Pi plugin for inspecting one exact point-in-time
market breadth packet on the `cn`, `hk`, or `us` track.

`market_snapshot` validates one explicit market/MIC scope and a bounded list of
caller or provider-adapter member facts. It calculates overall and first-seen
group advance/decline/unchanged counts from exact current versus previous-close
values, explicit observed-row fractions, and maximum/minimum change-fraction
ties within the supplied rows. Output member paging is stable and input ordered.

Coverage can be complete, partial, or unknown, but those states remain
unverified declarations. Unavailable and conflicting price facts are retained
and excluded from directional arithmetic. Reported volume and volatility are
preserved with their explicit units and methods; neither is interpreted as
fund flow, liquidity, regime, or investment quality.

This first slice is network-free. It does not resolve identities, acquire or
select a provider, cross tracks, complete membership, choose a benchmark,
forecast, infer rotation or money flow, rank investments, generate signals, or
trade.
