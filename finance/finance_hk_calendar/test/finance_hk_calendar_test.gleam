import finance_calendar/calendar
import finance_calendar/local
import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_hk_calendar
import finance_hk_calendar/dataset as hk_calendar
import finance_market_calendar/dataset
import finance_provenance/evidence
import finance_track
import finance_track/context
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_hk_calendar.status()
  |> should.equal(finance_hk_calendar.Experimental)
}

pub fn hk_dataset_is_isolated_and_midday_is_not_open_test() {
  let value = synthetic_dataset()
  let track_context = dataset.context(value)
  context.track(track_context) |> should.equal(finance_track.Hk)
  let assert Some(mic) = context.venue_mic(track_context)
  identifier.mic_value(mic) |> should.equal("XHKG")
  dataset.session_at(value, zoned(2024, 1, 3, 12, 30))
  |> should.equal(Ok(None))
}

pub fn hk_coverage_does_not_fall_back_to_mainland_or_weekdays_test() {
  let value = synthetic_dataset()
  dataset.trading_day(value, on: civil(2024, 1, 8))
  |> should.equal(
    Error(dataset.OutsideCoverage(
      civil(2024, 1, 1),
      civil(2024, 1, 5),
      civil(2024, 1, 8),
    )),
  )
}

fn synthetic_dataset() -> dataset.Dataset {
  let sessions = [
    session("synthetic opening auction", 9, 0, 9, 30),
    session("synthetic morning", 9, 30, 12, 0),
    session("synthetic afternoon", 13, 0, 16, 0),
  ]
  let assert Ok(value) =
    hk_calendar.new(
      version: "synthetic-v1",
      coverage_start: civil(2024, 1, 1),
      coverage_end: civil(2024, 1, 5),
      source: source_ref(),
      licence: evidence.Licence(
        "synthetic-test-data",
        evidence.PublicDomain,
        None,
      ),
      entitlement: "synthetic",
      limitations: ["test_only"],
      weekly: hk_calendar.weekday_template(sessions),
      overrides: [],
    )
  value
}

fn session(
  label: String,
  open_h: Int,
  open_m: Int,
  close_h: Int,
  close_m: Int,
) -> calendar.Session {
  let assert Ok(value) =
    calendar.session(
      label: label,
      opens_at: clock(open_h, open_m),
      closes_at: clock(close_h, close_m),
      close_day: calendar.SameDay,
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
      zone: hk_calendar.hong_kong_zone(),
      utc_offset_minutes: 480,
    )
  value
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new(
      provider: "synthetic-hk-calendar",
      reference: "fixture/hk-calendar",
      kind: source.Synthetic,
    )
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn clock(hour: Int, minute: Int) -> time.TimeOfDay {
  let assert Ok(value) = local.local_time(hour, minute)
  value
}
