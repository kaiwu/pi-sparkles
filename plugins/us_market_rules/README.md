# us_market_rules

Experimental Pi plugin for the isolated `us` track. It registers
`us_trading_rules`, which returns one effective minimum-price-increment profile
for an exact caller-identified NYSE/XNYS or Nasdaq/XNAS listing.

The first slice accepts only USD, caller-declared `nms_stock`, `normal` status,
and `regular_displayed_quote`. It returns `$0.01` at or above `$1.00` and
`$0.0001` below `$1.00`, retaining the namespaced instrument ID, uppercase
symbol, MIC, nominal price, reviewed interval, exchange source, SEC relief
order, clauses, audit state, and limitations.

The profile covers June 11, 2026 through October 31, 2027. SEC Release
34-105656 defers compliance with amended Rule 612's half-cent assignment until
the first business day of November 2027. Dates outside coverage fail closed;
later SEC or exchange changes require a new profile version.

Listing identity, NMS-stock class, and status remain caller supplied and
unverified. Round lots and odd lots, customer-order acceptance, order types,
auctions, extended hours, LULD, halts, short sales, access fees, settlement,
fees, execution, and best execution are explicitly outside the contract. The
plugin has no environment dependencies and performs no runtime network request.

Official sources:

- NYSE Rule 7.6: <https://www.nyse.com/publicdocs/nyse/regulation/nyse/NYSE_Rules.pdf>
- Nasdaq Equity 2, Section 5(a)(2)(I): <https://listingcenter.nasdaq.com/rulebook/nasdaq/rules/nasdaq-equity-2>
- SEC Release 34-105656: <https://www.sec.gov/files/rules/exorders/2026/34-105656.pdf>

Build and test with:

```sh
bun run test:unit -- us_market_rules
bun run build -- us_market_rules
```
