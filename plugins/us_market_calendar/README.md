# us_market_calendar

Experimental Pi plugin for the isolated `us` track. It registers
`us_market_calendar`, which classifies one exact 2026 date for an explicitly
selected `nyse` or `nasdaq` regular-equity venue.

The plugin composes `finance_us_calendar` over the provider-neutral calendar
engines. Results expose `XNYS` or `XNAS`, `America/New_York`, the exact exchange
source, dataset version and coverage, full-day/early-close state, sessions,
entitlement, licence state, and every limitation. No symbol-to-venue inference
or CN/HK calendar substitution is allowed.

The source-reviewed dataset covers calendar year 2026 only. It preserves ten
published full closures and the November 27 and December 24 1:00 p.m. Eastern
early closes. Later exchange alerts can supersede the planned schedule.
Pre-market, after-hours, auctions, options, bonds, settlement, FINRA reporting,
security-specific suspension, and redistribution permission are outside this
contract. Dates outside coverage fail closed instead of using a weekday guess.

This plugin has no environment dependencies and performs no runtime network
request. It does not itself classify missing rows returned by
`us_stock_ohlcv`; the separate `us_ohlcv_gaps` receipt compositor now performs
that explicit calendar/listing/status/provider join for fully evidenced copied
2026 inputs.

Official sources:

- NYSE: <https://www.nyse.com/trade/hours-calendars>
- Nasdaq Trader: <https://www.nasdaqtrader.com/trader.aspx?id=Calendar>

Build and test with the repository task runner:

```sh
bun run test:unit -- us_market_calendar
bun run build -- us_market_calendar
```
