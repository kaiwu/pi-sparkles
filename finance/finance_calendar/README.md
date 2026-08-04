# finance_calendar

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_calendar` supplies pure civil-date, market-session, business-day,
joint-calendar, coupon-schedule, and financial day-count rules. It is the
market-time policy layer used before `finance_series` resampling and
time-dependent `finance_math` calculations.

The package depends on `finance_core` through a local path. It includes no Pi,
HTTP, filesystem, system clock, timezone database, JavaScript FFI, or bundled
exchange holiday dataset.

## Design boundary

Calendar correctness has two distinct parts:

1. pure rules describing weekdays, sessions, holidays, early closes, business
   adjustments, and day-count conventions; and
2. maintained external data and timezone resolution establishing which rules
   were effective for a venue and how an `Instant` maps into local civil time.

This package implements the first part and defines a typed boundary for the
second. Provider or licensed calendar packages supply dated overrides and use a
real IANA timezone resolver. No generic base library should claim that weekends
alone constitute an authoritative trading calendar.

## Modules

| Module | Responsibility |
| --- | --- |
| `finance_calendar/date` | Gregorian ordinals, weekdays, signed day distances, large day shifts, month shifts, leap years, and month-end rules |
| `finance_calendar/local` | validated IANA-style zone IDs, local wall times, and explicitly offset zoned date-times |
| `finance_calendar/calendar` | weekly trading templates, dated closures/overrides, same-day and overnight sessions, local-time classification |
| `finance_calendar/business` | bounded following/preceding adjustments and business-day shifts |
| `finance_calendar/day_count` | Actual/360, Actual/365 Fixed, ISDA/ICMA actual, US/European/ISDA 30/360, and Business/252 |
| `finance_calendar/joint` | explicit all-open and any-open calendar composition |
| `finance_calendar/schedule` | bounded coupon/payment boundaries, stub rules, end-of-month preservation, and adjustment |

## Civil dates

`date.ordinal` uses the proleptic Gregorian calendar with `0001-01-01` as day
one and Monday. `days_between` is signed and follows the conventional
start-exclusive/end-inclusive interval. `add_days` converts through ordinals
using bounded logarithmic year search, so large shifts do not recurse once per
day.

Month shifts require either `ClampDay` or `RejectInvalidDay`. For example,
January 31 plus one month can become the February month-end only when clamping
was explicitly requested.

## Local time and timezone safety

`ZoneId` accepts `UTC` and IANA-style names such as `America/New_York` or
`Asia/Shanghai`. `LocalTime` is a validated wall-clock minute.
`ZonedDateTime` contains a date, local time, zone, and explicit UTC offset.

The package intentionally does not derive the offset. Daylight-saving and
historical timezone transitions require an external maintained timezone
database. A caller must convert an `Instant` through such a resolver and then
construct `ZonedDateTime`; `calendar.session_at` rejects a value carrying a
different zone from the market calendar. The offset remains visible evidence
of the conversion rather than being inferred from a fixed UTC assumption.

## Trading calendars and sessions

A `Calendar` has:

- a stable name and zone;
- zero or one weekly rule per weekday; and
- unique dated overrides for holidays, exceptional closures, late opens, and
  early closes.

Missing weekday rules are closed. `Open` days require at least one validated,
ordered, non-overlapping session. A session closes either `SameDay` or
`NextDay`; the latter allows futures, FX, and other overnight trading days.
When local time falls after midnight in an overnight session,
`SessionOccurrence.trading_date` remains the date on which that session opened.

Dated overrides replace the weekly rule completely. This prevents a generic
holiday label from accidentally retaining regular hours. If independently
configured current-day and prior overnight sessions overlap,
`session_at` returns `AmbiguousSession` rather than choosing one.

## Business-day conventions

`business.adjust` implements:

- unadjusted;
- following and modified following; and
- preceding and modified preceding.

Modified conventions reverse direction when the first adjustment crosses a
month boundary. `add_business_days` and every nontrivial adjustment require a
finite `maximum_scan_days`. A malformed or intentionally always-closed calendar
therefore returns `SearchExhausted` rather than looping forever.

Calendar days and settlement business days are not assumed to be identical.
Callers can construct separate venue, currency, publication, and settlement
calendars and select the correct one as an explicit metric assumption.

## Day-count conventions

`day_count.days` returns a signed convention-specific numerator.
`day_count.year_fraction` returns an explicitly approximate `Float`:

- `Actual360` and `Actual365Fixed` divide actual Gregorian days by a fixed
  denominator;
- `ActualActualIsda` partitions cross-year intervals by each calendar year’s
  actual length; `actual_actual_icma` takes an explicit reference coupon period;
- `Thirty360Us` and `ThirtyE360` apply their distinct month-end rules.

The separate ISDA 30E/360 helper makes termination-date treatment explicit,
and `business_252` counts a caller-supplied calendar over a bounded half-open
interval. Coupon schedules require a finite period count, a short/long first or
last stub rule, and an explicit end-of-month policy.

The convention must be carried with any interest, yield, accrual, duration, or
XIRR result. The package never selects one based on currency or instrument name.

## Composition with series and math

```text
Instant -- maintained IANA resolver --> ZonedDateTime
                                           │
                            Calendar + dated overrides
                                           │
                      trading date / session / business date
                                           │
                          finance_series bucket + alignment
                                           │
                               finance_math calculation
```

This keeps timezone and holiday data replaceable while preserving deterministic
rule evaluation. Calendar providers can be tested with synthetic overrides and
the same functions without networking or a system clock.

## Acceptance criteria

- Gregorian date arithmetic covers leap years, month ends, signed intervals,
  and large shifts deterministically.
- Market zones and observed UTC offsets remain explicit.
- Weekly rules, closures, holidays, and early closes are immutable dated data.
- Same-day and overnight sessions classify local time without losing trading
  date ownership.
- Duplicate, empty, overlapping, wrong-zone, and ambiguous rules fail visibly.
- Every business-day search has a finite caller-provided budget.
- Named day-count conventions have signed known-answer tests.
- The package remains pure and contains no FFI or bundled unreviewed datasets.
- Formatting and warnings-as-errors builds pass.

## Post-foundation expansion

- ex-date/record-date helpers and specialized settlement schedules;
- additional market-specific day-count interpretations;
- higher-level trading versus settlement convenience helpers;
- pure calendar-to-series bucket adapters around an injected timezone resolver;
- versioned provider-calendar metadata, effective dates, provenance, and
  licence labels; and
- reviewed synthetic fixtures for DST gaps/folds, emergency closures, and
  historical rule changes.

## Non-goals

- No claim of authoritative NYSE, Nasdaq, CME, HKEX, SSE, SZSE, BSE, bank,
  currency, or government-publication holidays in the base package.
- No fixed-offset substitute for IANA timezone conversion.
- No silent weekend-only fallback where an authoritative calendar was required.
- No exchange-data redistribution claim, trading-status feed, scheduling daemon,
  order-routing clock, or guarantee that a venue will open as scheduled.
