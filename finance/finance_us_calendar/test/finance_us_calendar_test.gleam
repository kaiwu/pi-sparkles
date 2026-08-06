import finance_calendar/calendar
import finance_calendar/local
import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_market_calendar/dataset
import finance_provenance/evidence
import finance_track
import finance_track/context
import finance_us_calendar
import finance_us_calendar/dataset as us_calendar
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_us_calendar.status()
  |> should.equal(finance_us_calendar.Experimental)
}

pub fn synthetic_datasets_are_us_scoped_and_venue_explicit_test() {
  let nyse = synthetic_dataset(us_calendar.Nyse)
  let nasdaq = synthetic_dataset(us_calendar.Nasdaq)
  let nyse_context = dataset.context(nyse)
  let nasdaq_context = dataset.context(nasdaq)

  context.track(nyse_context) |> should.equal(finance_track.Us)
  let assert Some(nyse_mic) = context.venue_mic(nyse_context)
  let assert Some(nasdaq_mic) = context.venue_mic(nasdaq_context)
  identifier.mic_value(nyse_mic) |> should.equal("XNYS")
  identifier.mic_value(nasdaq_mic) |> should.equal("XNAS")
  context.timezone(nyse_context)
  |> should.equal(Some(us_calendar.new_york_zone()))
}

pub fn official_2026_sources_are_venue_owned_test() {
  let assert Ok(nyse) = us_calendar.official_2026(us_calendar.Nyse)
  let assert Ok(nasdaq) = us_calendar.official_2026(us_calendar.Nasdaq)

  source.provider(dataset.source(nyse)) |> should.equal("nyse")
  source.provider(dataset.source(nasdaq)) |> should.equal("nasdaq")
  source.reference(dataset.source(nyse))
  |> should.equal("https://www.nyse.com/trade/hours-calendars")
  source.reference(dataset.source(nasdaq))
  |> should.equal("https://www.nasdaqtrader.com/trader.aspx?id=Calendar")
  dataset.version(nyse) |> should.equal("official-2026-v1")
}

pub fn official_closures_and_early_closes_are_preserved_test() {
  let assert Ok(nyse) = us_calendar.official_2026(us_calendar.Nyse)

  dataset.trading_day(nyse, on: civil(2026, 7, 3))
  |> should.equal(Ok(calendar.Closed("independence_day_observed")))
  let assert Ok(calendar.Open(early_sessions)) =
    dataset.trading_day(nyse, on: civil(2026, 11, 27))
  list.length(early_sessions) |> should.equal(1)
  let assert [early_session] = early_sessions
  local.time_parts(calendar.closes_at(early_session)) |> should.equal(#(13, 0))

  let assert Ok(calendar.Open(full_sessions)) =
    dataset.trading_day(nyse, on: civil(2026, 11, 30))
  let assert [full_session] = full_sessions
  local.time_parts(calendar.opens_at(full_session)) |> should.equal(#(9, 30))
  local.time_parts(calendar.closes_at(full_session)) |> should.equal(#(16, 0))
}

pub fn coverage_edges_fail_closed_without_weekday_fallback_test() {
  let assert Ok(value) = us_calendar.official_2026(us_calendar.Nasdaq)
  dataset.trading_day(value, on: civil(2027, 1, 4))
  |> should.equal(
    Error(dataset.OutsideCoverage(
      civil(2026, 1, 1),
      civil(2026, 12, 31),
      civil(2027, 1, 4),
    )),
  )
}

fn synthetic_dataset(venue: us_calendar.Venue) -> dataset.Dataset {
  let assert Ok(value) =
    us_calendar.new(
      venue: venue,
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
      weekly: us_calendar.weekday_template(us_calendar.regular_session()),
      overrides: [],
    )
  value
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new(
      provider: "synthetic-us-calendar",
      reference: "fixture/us-calendar",
      kind: source.Synthetic,
    )
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
