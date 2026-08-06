# finance_us_calendar

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_us_calendar` binds caller-supplied schedules to the `us` track and an
exact `XNYS` or `XNAS` venue, `America/New_York`, an explicit source/licence/
version, and bounded coverage. It composes the provider-neutral
`finance_market_calendar` and `finance_calendar` engines without importing Pi,
CN/HK market packages, or a provider runtime.

The package supplies source-reviewed `official_2026` NYSE and Nasdaq regular-
equity datasets. Both preserve the published ten full-day closures and the
1:00 p.m. Eastern early closes on November 27 and December 24. Each venue keeps
its own official source reference and MIC even where the dates coincide.

Coverage ends on December 31, 2026. Later exchange alerts or exceptional-
closure notices supersede the planned schedule and require a new reviewed
dataset version. Pre-market, after-hours, auctions, options, bonds, settlement,
FINRA reporting, security-specific suspension, and provider-history gap
classification are outside this contract. Redistribution permission is not
inferred from public access.

Official sources:

- NYSE: <https://www.nyse.com/trade/hours-calendars>
- Nasdaq Trader: <https://www.nasdaqtrader.com/trader.aspx?id=Calendar>

Tests cover venue/MIC isolation, official source identity, full closures, early
closes, regular session hours, and coverage edges.
