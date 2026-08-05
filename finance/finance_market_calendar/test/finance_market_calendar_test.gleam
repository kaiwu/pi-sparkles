import finance_calendar/calendar
import finance_calendar/date
import finance_calendar/local
import finance_core/source
import finance_core/time
import finance_market_calendar
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
  finance_market_calendar.status()
  |> should.equal(finance_market_calendar.Experimental)
}

pub fn bounded_dataset_rejects_unknown_dates_test() {
  let value = synthetic_dataset()
  dataset.trading_day(value, on: civil(2024, 1, 1)) |> should.be_ok
  dataset.trading_day(value, on: civil(2023, 12, 31))
  |> should.equal(
    Error(dataset.OutsideCoverage(
      civil(2024, 1, 1),
      civil(2024, 1, 5),
      civil(2023, 12, 31),
    )),
  )
}

pub fn dataset_rejects_context_calendar_timezone_mismatch_test() {
  let market = make_calendar(zone("Asia/Hong_Kong"))
  dataset.new(
    context: track_context("Asia/Shanghai"),
    calendar: market,
    version: "synthetic-v1",
    coverage_start: civil(2024, 1, 1),
    coverage_end: civil(2024, 1, 5),
    source: source_ref(),
    licence: licence(),
  )
  |> should.equal(
    Error(dataset.TimezoneMismatch("Asia/Shanghai", "Asia/Hong_Kong")),
  )
}

fn synthetic_dataset() -> dataset.Dataset {
  let market = make_calendar(zone("Asia/Shanghai"))
  let assert Ok(value) =
    dataset.new(
      context: track_context("Asia/Shanghai"),
      calendar: market,
      version: "synthetic-v1",
      coverage_start: civil(2024, 1, 1),
      coverage_end: civil(2024, 1, 5),
      source: source_ref(),
      licence: licence(),
    )
  value
}

fn make_calendar(zone: time.Timezone) -> calendar.Calendar {
  let assert Ok(session) =
    calendar.session(
      label: "synthetic",
      opens_at: clock(9, 0),
      closes_at: clock(10, 0),
      close_day: calendar.SameDay,
    )
  let assert Ok(value) =
    calendar.new(
      name: "synthetic calendar",
      zone: zone,
      weekly: [#(date.Monday, calendar.Open([session]))],
      overrides: [],
    )
  value
}

fn track_context(zone_name: String) -> context.Context {
  let assert Ok(value) =
    context.new(
      track: finance_track.Cn,
      market_scope: "cn_synthetic_calendar",
      venue_mic: None,
      board: None,
      timezone: Some(zone(zone_name)),
      source_language: "zh-CN",
      providers: ["synthetic-provider"],
      entitlement: "synthetic",
      limitations: ["test_only"],
    )
  value
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new(
      provider: "synthetic-provider",
      reference: "fixture/calendar",
      kind: source.Synthetic,
    )
  value
}

fn licence() -> evidence.Licence {
  evidence.Licence("synthetic-test-data", evidence.PublicDomain, None)
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn zone(name: String) -> time.Timezone {
  let assert Ok(value) = local.zone_id(name)
  value
}

fn clock(hour: Int, minute: Int) -> time.TimeOfDay {
  let assert Ok(value) = local.local_time(hour, minute)
  value
}
