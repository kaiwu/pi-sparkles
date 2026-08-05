# finance_cn_calendar

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_cn_calendar` binds caller-supplied SSE, SZSE, or BSE calendar data to
the `cn` track, the venue MIC, `Asia/Shanghai`, a source, licence, dataset
version, and inclusive coverage. It composes the generic session engine and the
bounded `finance_market_calendar` wrapper.

The package provides a reusable Monday–Friday base-template helper and a
source-reviewed `official_2026` dataset for each venue. The three datasets keep
separate SSE, SZSE, and BSE source references even where their published
holiday dates coincide. They model the published opening/closing auctions,
continuous sessions, midday gap, and 2026 planned closures.

Queries outside 2026 fail and no weekend-only inference is available through
the bounded API. A later exceptional-closure notice may supersede the planned
schedule. Settlement, Stock Connect, security-specific suspension, and
redistribution permission are not inferred. Tests cover both the generic
synthetic constructor and the venue-owned 2026 source/version/closure contract.

Sources: SSE's official annual closure page, SZSE notice `深证会〔2025〕481号`,
and BSE notice `北证公告〔2025〕58号`, linked by the dataset and companion plugin.
