# finance_calendar

Experimental shared Pi shell for exact, read-only inspection of the existing
track-owned 2026 trading-calendar datasets. It registers three tools:

- `inspect_session` classifies one covered date and returns its session type
  and ordered venue-local phase intervals.
- `list_holidays` returns a stable, date-ordered page of venue-published dated
  full closures within an inclusive range. Ordinary weekend closures are not
  called holidays.
- `next_session` returns the first scheduled open date strictly after a covered
  date, or an explicit unavailable result when no later open date exists inside
  the dataset coverage.

Every call requires both a user-visible track (`cn`, `hk`, or `us`) and an exact
MIC. The only valid pairs are `cn` with `XSHG`, `XSHE`, or `XBSE`; `hk` with
`XHKG`; and `us` with `XNYS` or `XNAS`. Mismatched pairs fail. There is no
symbol inference, active-track lookup, venue choice, sibling-track fallback, or
provider substitution.

## Result contract

Results retain the track context, MIC, venue timezone, calendar name, dataset
version, exact coverage, exchange source URL, licence and redistribution state,
entitlement, and every source limitation. Open days are classified as
`regular_full` or `regular_shortened`; the ordered phase labels and intervals
remain the controlling facts. CN call/continuous-auction phases, HK pre-opening
and continuous phases, and US regular-market phases are not flattened into a
single synthetic interval. Overnight support remains explicit through each
phase's close-day value even though the bundled 2026 equity datasets use
same-day phases.

`list_holidays` is inclusive and ordered by date before `offset`/`limit` are
applied. Its `rangeId` binds the requested track, MIC, dataset version, and exact
range and therefore remains unchanged across pages. Range endpoints and all
single-date inputs must be inside the declared 2026 coverage. Invalid or
out-of-coverage dates fail closed; no weekday assumption is used beyond the
reviewed dataset's own weekly template.

## Scope boundary

This shell reports planned calendar facts only. It does not schedule work,
create alerts, resolve symbols, classify security suspensions, infer later
exceptional-closure notices, cover settlement or Stock Connect calendars,
resolve daylight-saving instants, or make a trading decision. A later venue
notice may supersede the bundled plan. The source packages' redistribution
permission remains unknown.

Lifecycle: **Experimental**. The first slice stops at the three tools above.
Additional scheduling, alerts, settlement, or intraday operations require a
new professional workflow gate.

Verification covers all six MICs, CN multi-phase sessions, HK half-days, US
early closes, published holidays versus weekends, stable range paging,
strictly-later next sessions, track-pair rejection, coverage failure, bundled
tool registration/results, artifact export, architecture, Pi loading, and the
full repository regression.

Build and test with:

```sh
bun run test:unit -- finance_calendar
bun run build -- finance_calendar
```
