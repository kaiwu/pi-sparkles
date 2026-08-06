# finance_us_rules

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_us_rules` owns effective-dated US market-rule profiles without
importing Pi or CN/HK market packages. Its first source-reviewed profile covers
only the minimum price increment for a regular displayed quotation in a
caller-identified, normally traded NMS stock on NYSE/XNYS or Nasdaq/XNAS.

During the reviewed June 11, 2026 through October 31, 2027 interval, the
profile returns `$0.01` for a nominal price at or above `$1.00` and `$0.0001`
below `$1.00`. It preserves an exact namespaced instrument ID, uppercase symbol,
venue/MIC, nominal price, effective interval, exchange rule source, and SEC
Release 34-105656. That release defers compliance with amended Rule 612's
half-cent assignment until the first business day of November 2027.

The listing identity, NMS-stock classification, and normal status are caller
declarations, not provider-verified facts. Round lots and odd lots, customer
order acceptance, order types, auctions, extended hours, LULD bands, halts,
short sales, access fees, settlement, fees, execution, and best execution are
outside this profile. A later SEC order or exchange amendment supersedes the
reviewed interval and requires a new version. Public access does not establish
redistribution rights.

Official sources:

- NYSE Rule 7.6: <https://www.nyse.com/publicdocs/nyse/regulation/nyse/NYSE_Rules.pdf>
- Nasdaq Equity 2, Section 5(a)(2)(I): <https://listingcenter.nasdaq.com/rulebook/nasdaq/rules/nasdaq-equity-2>
- SEC Release 34-105656: <https://www.sec.gov/files/rules/exorders/2026/34-105656.pdf>
