import finance_calendar
import finance_calendar/business
import finance_calendar/calendar
import finance_calendar/date
import finance_calendar/day_count
import finance_calendar/joint
import finance_calendar/local
import finance_calendar/schedule
import finance_core/time
import gleam/float
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_calendar.status()
  |> should.equal(finance_calendar.Experimental)
}

pub fn gregorian_arithmetic_handles_leap_years_and_month_policy_test() {
  date.weekday(civil(2024, 2, 29))
  |> should.equal(date.Thursday)
  date.days_between(civil(2024, 2, 28), civil(2024, 3, 1))
  |> should.equal(2)
  date.add_days(civil(2024, 2, 28), 2)
  |> should.equal(Ok(civil(2024, 3, 1)))
  date.add_days(civil(2024, 3, 1), -2)
  |> should.equal(Ok(civil(2024, 2, 28)))
  date.add_days(civil(2000, 1, 1), 36_525)
  |> should.equal(Ok(civil(2100, 1, 1)))
  date.from_ordinal(date.ordinal(civil(2400, 12, 31)))
  |> should.equal(Ok(civil(2400, 12, 31)))
  date.add_months(civil(2024, 1, 31), 1, date.ClampDay)
  |> should.equal(Ok(civil(2024, 2, 29)))
  date.add_months(civil(2024, 1, 31), 1, date.RejectInvalidDay)
  |> should.equal(Error(date.InvalidResult))
}

pub fn local_time_requires_named_zone_and_explicit_offset_test() {
  local.zone_id("UTC") |> should.be_ok
  local.zone_id("America/New_York") |> should.be_ok
  local.zone_id("New York") |> should.equal(Error(local.InvalidZoneId))
  local.local_time(24, 0) |> should.equal(Error(local.InvalidHour))
  let zone = zone("America/New_York")
  local.zoned_date_time(
    date: civil(2024, 7, 3),
    time: clock(10, 0),
    zone: zone,
    utc_offset_minutes: -240,
  )
  |> should.be_ok
  local.zoned_date_time(
    date: civil(2024, 7, 3),
    time: clock(10, 0),
    zone: zone,
    utc_offset_minutes: 900,
  )
  |> should.equal(Error(local.InvalidUtcOffset))
}

pub fn weekly_calendar_supports_holidays_and_early_close_overrides_test() {
  let market = equity_calendar()

  calendar.is_open_date(market, civil(2024, 7, 4))
  |> should.be_false
  calendar.is_open_date(market, civil(2024, 7, 6))
  |> should.be_false
  calendar.trading_day(market, civil(2024, 7, 3))
  |> should.equal(calendar.Open([regular_session(close_hour: 13)]))

  let assert Ok(open_time) =
    calendar.session_at(market, zoned(2024, 7, 3, 10, 0))
  let assert Some(calendar.SessionOccurrence(trading_date, open_session)) =
    open_time
  trading_date |> should.equal(civil(2024, 7, 3))
  calendar.label(open_session) |> should.equal("regular")
  calendar.session_at(market, zoned(2024, 7, 3, 14, 0))
  |> should.equal(Ok(None))
}

pub fn overnight_session_retains_its_trading_date_test() {
  let overnight = session("overnight", 18, 0, 17, 0, calendar.NextDay)
  let assert Ok(market) =
    calendar.new(
      name: "overnight market",
      zone: zone("America/New_York"),
      weekly: [#(date.Monday, calendar.Open([overnight]))],
      overrides: [],
    )
  let assert Ok(found) = calendar.session_at(market, zoned(2024, 7, 2, 1, 0))

  found
  |> should.equal(
    Some(calendar.SessionOccurrence(civil(2024, 7, 1), overnight)),
  )
  calendar.session_at(market, zoned(2024, 7, 2, 17, 0))
  |> should.equal(Ok(None))
}

pub fn calendar_rejects_duplicate_and_overlapping_rules_test() {
  let regular = regular_session(close_hour: 16)
  calendar.new(
    name: "duplicate",
    zone: zone("UTC"),
    weekly: [
      #(date.Monday, calendar.Open([regular])),
      #(date.Monday, calendar.Open([regular])),
    ],
    overrides: [],
  )
  |> should.equal(Error(calendar.DuplicateWeekday(date.Monday)))

  let first = session("first", 9, 0, 12, 0, calendar.SameDay)
  let overlapping = session("overlap", 11, 0, 13, 0, calendar.SameDay)
  calendar.new(
    name: "overlap",
    zone: zone("UTC"),
    weekly: [#(date.Monday, calendar.Open([first, overlapping]))],
    overrides: [],
  )
  |> should.equal(Error(calendar.SessionsOverlap))
}

pub fn zoned_classification_rejects_the_wrong_market_zone_test() {
  let market = equity_calendar()
  let assert Ok(value) =
    local.zoned_date_time(
      date: civil(2024, 7, 3),
      time: clock(10, 0),
      zone: zone("Asia/Shanghai"),
      utc_offset_minutes: 480,
    )

  calendar.session_at(market, value)
  |> should.equal(
    Error(calendar.ZoneMismatch("America/New_York", "Asia/Shanghai")),
  )
}

pub fn business_day_adjustment_is_bounded_and_convention_explicit_test() {
  let market = equity_calendar()

  business.adjust(
    market,
    date: civil(2024, 6, 29),
    convention: business.Following,
    maximum_scan_days: 5,
  )
  |> should.equal(Ok(civil(2024, 7, 1)))
  business.adjust(
    market,
    date: civil(2024, 6, 30),
    convention: business.ModifiedFollowing,
    maximum_scan_days: 5,
  )
  |> should.equal(Ok(civil(2024, 6, 28)))
  business.add_business_days(
    market,
    date: civil(2024, 7, 3),
    days: 1,
    maximum_scan_days: 5,
  )
  |> should.equal(Ok(civil(2024, 7, 5)))
  business.open_dates_between(
    market,
    start: civil(2024, 7, 3),
    end: civil(2024, 7, 5),
    maximum_scan_days: 3,
  )
  |> should.equal(Ok([civil(2024, 7, 3), civil(2024, 7, 5)]))
}

pub fn business_day_search_never_runs_forever_test() {
  let assert Ok(closed) =
    calendar.new(name: "closed", zone: zone("UTC"), weekly: [], overrides: [])
  business.adjust(
    closed,
    date: civil(2024, 1, 1),
    convention: business.Following,
    maximum_scan_days: 2,
  )
  |> should.equal(Error(business.SearchExhausted(civil(2024, 1, 3))))
}

pub fn day_count_conventions_are_named_signed_and_testable_test() {
  day_count.days(civil(2024, 1, 1), civil(2025, 1, 1), day_count.Actual365Fixed)
  |> should.equal(366)
  day_count.days(civil(2025, 1, 1), civil(2024, 1, 1), day_count.Actual365Fixed)
  |> should.equal(-366)
  day_count.days(civil(2024, 1, 31), civil(2025, 1, 31), day_count.Thirty360Us)
  |> should.equal(360)
  day_count.days(civil(2024, 1, 31), civil(2025, 1, 31), day_count.ThirtyE360)
  |> should.equal(360)
  expect_close(
    day_count.year_fraction(
      civil(2024, 1, 1),
      civil(2025, 1, 1),
      day_count.ActualActualIsda,
    ),
    1.0,
  )
}

pub fn coupon_schedules_make_stubs_eom_and_termination_budgets_explicit_test() {
  let assert Ok(exact) =
    schedule.generate(
      start: civil(2024, 1, 31),
      end: civil(2024, 7, 31),
      months: 3,
      stub: schedule.NoStub,
      preserve_end_of_month: True,
      maximum_periods: 4,
    )
  exact.dates
  |> should.equal([
    civil(2024, 1, 31),
    civil(2024, 4, 30),
    civil(2024, 7, 31),
  ])

  let assert Ok(long_last) =
    schedule.generate(
      start: civil(2024, 1, 31),
      end: civil(2024, 8, 15),
      months: 3,
      stub: schedule.LongLast,
      preserve_end_of_month: True,
      maximum_periods: 4,
    )
  long_last.dates
  |> should.equal([civil(2024, 1, 31), civil(2024, 4, 30), civil(2024, 8, 15)])
  schedule.generate(
    start: civil(2024, 1, 31),
    end: civil(2024, 8, 15),
    months: 3,
    stub: schedule.NoStub,
    preserve_end_of_month: True,
    maximum_periods: 4,
  )
  |> should.equal(Error(schedule.StubRequired))
  schedule.generate(
    start: civil(2024, 1, 1),
    end: civil(2030, 1, 1),
    months: 1,
    stub: schedule.ShortLast,
    preserve_end_of_month: False,
    maximum_periods: 2,
  )
  |> should.equal(Error(schedule.PeriodLimitExceeded))
}

pub fn joint_calendars_and_extended_day_counts_are_composable_test() {
  let market = equity_calendar()
  let assert Ok(thursday_open) =
    calendar.new(
      name: "Thursday settlement",
      zone: zone("America/New_York"),
      weekly: [
        #(date.Thursday, calendar.Open([regular_session(close_hour: 16)])),
      ],
      overrides: [],
    )
  let assert Ok(all_open) =
    joint.new([market, thursday_open], rule: joint.AllOpen)
  let assert Ok(any_open) =
    joint.new([market, thursday_open], rule: joint.AnyOpen)

  joint.is_open_date(all_open, date: civil(2024, 7, 4))
  |> should.be_false
  joint.is_open_date(any_open, date: civil(2024, 7, 4))
  |> should.be_true

  expect_close(
    day_count.actual_actual_icma(
      civil(2024, 1, 1),
      civil(2024, 7, 1),
      civil(2024, 1, 1),
      civil(2024, 7, 1),
      2,
    )
      |> result_value,
    0.5,
  )
  day_count.thirty_e_360_isda_days(
    civil(2024, 2, 29),
    civil(2024, 3, 31),
    False,
  )
  |> should.equal(30)
  day_count.business_252(
    civil(2024, 7, 3),
    civil(2024, 7, 6),
    calendar: market,
    maximum_scan_days: 3,
  )
  |> result_value
  |> expect_close(2.0 /. 252.0)
}

fn equity_calendar() -> calendar.Calendar {
  let regular = calendar.Open([regular_session(close_hour: 16)])
  let assert Ok(value) =
    calendar.new(
      name: "example equities",
      zone: zone("America/New_York"),
      weekly: [
        #(date.Monday, regular),
        #(date.Tuesday, regular),
        #(date.Wednesday, regular),
        #(date.Thursday, regular),
        #(date.Friday, regular),
      ],
      overrides: [
        #(civil(2024, 7, 4), calendar.Closed("Independence Day")),
        #(civil(2024, 7, 3), calendar.Open([regular_session(close_hour: 13)])),
      ],
    )
  value
}

fn regular_session(close_hour close_hour: Int) -> calendar.Session {
  session("regular", 9, 30, close_hour, 0, calendar.SameDay)
}

fn session(
  label: String,
  open_hour: Int,
  open_minute: Int,
  close_hour: Int,
  close_minute: Int,
  close_day: calendar.CloseDay,
) -> calendar.Session {
  let assert Ok(value) =
    calendar.session(
      label: label,
      opens_at: clock(open_hour, open_minute),
      closes_at: clock(close_hour, close_minute),
      close_day: close_day,
    )
  value
}

fn zoned(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
) -> local.ZonedDateTime {
  let assert Ok(value) =
    local.zoned_date_time(
      date: civil(year, month, day),
      time: clock(hour, minute),
      zone: zone("America/New_York"),
      utc_offset_minutes: -240,
    )
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn clock(hour: Int, minute: Int) -> local.LocalTime {
  let assert Ok(value) = local.local_time(hour, minute)
  value
}

fn zone(name: String) -> local.ZoneId {
  let assert Ok(value) = local.zone_id(name)
  value
}

fn expect_close(value: Float, expected: Float) -> Nil {
  { float.absolute_value(value -. expected) <=. 0.000_001 }
  |> should.be_true
}

fn result_value(result: Result(value, error)) -> value {
  let assert Ok(value) = result
  value
}
