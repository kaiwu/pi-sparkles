# stock_market_calendar

Experimental provider-neutral Pi plugin for inspecting one exact `cn`, `hk`,
or `us` stock-session status packet.

`stock_session_status` accepts one exact market or listing scope, MIC-local
query date/time, caller-declared Unix instant, bounded source catalogue, and
typed schedule, phase, market-status, and listing-halt facts. Schedule facts
retain explicit full, shortened, closed, or other states. Phase facts retain
exact half-open local intervals and pre-market, auction, continuous, break,
after-hours, or other labels. A listing scope is mandatory when listing-halt
facts are supplied.

Every fact is represented by a canonical `finance_core.Observation` and retains
source, as-of/retrieval time, entitlement, licence, receipt, and exact observed,
unavailable, or conflicting state. Source coverage is either one exact Unix
range or explicitly unknown. Unsafe URL credentials and query secrets are
redacted before a reference is returned.

The result compares schedule, market-status, and listing-halt reports only when
all supplied facts in that family are observed. It reports a single report,
exact agreement, exact disagreement, or an indeterminate state without choosing
a source. It mechanically lists every observed phase interval containing the
query local timestamp and separately retains matching alternatives from
conflicting phase facts. Intervals are half-open: start is included and end is
excluded. Overlaps are not collapsed.

This first slice is network-free and stateless. It does not authenticate source
receipts or scope identity, prove that the local timestamp corresponds to the
caller-declared Unix instant, complete a calendar, infer a phase or halt from a
schedule or absence, select a provider, schedule work, create alerts, judge
readiness, or trade.

Build and test with:

```sh
bun run test:unit -- stock_market_calendar
bun run build -- stock_market_calendar
```
