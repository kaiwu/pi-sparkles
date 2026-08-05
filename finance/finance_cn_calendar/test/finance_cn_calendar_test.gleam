import finance_calendar/calendar
import finance_calendar/local
import finance_cn_calendar
import finance_cn_calendar/dataset as cn_calendar
import finance_cn_identity/identity
import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_market_calendar/dataset
import finance_provenance/evidence
import finance_track
import finance_track/context
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_cn_calendar.status()
  |> should.equal(finance_cn_calendar.Experimental)
}

pub fn mainland_dataset_is_cn_scoped_and_venue_explicit_test() {
  let value = synthetic_dataset(identity.Sse)
  let track_context = dataset.context(value)
  context.track(track_context) |> should.equal(finance_track.Cn)
  let assert Some(mic) = context.venue_mic(track_context)
  identifier.mic_value(mic) |> should.equal("XSHG")
  context.timezone(track_context)
  |> should.equal(Some(cn_calendar.shanghai_zone()))
}

pub fn multiple_sessions_preserve_the_midday_gap_test() {
  let value = synthetic_dataset(identity.Szse)
  dataset.session_at(value, zoned(2024, 1, 3, 10, 0)) |> should.be_ok
  dataset.session_at(value, zoned(2024, 1, 3, 12, 0))
  |> should.equal(Ok(None))
  dataset.session_at(value, zoned(2024, 1, 3, 14, 59)) |> should.be_ok
}

pub fn closure_override_and_coverage_edges_fail_closed_test() {
  let value = synthetic_dataset(identity.Bse)
  dataset.trading_day(value, on: civil(2024, 1, 2))
  |> should.equal(Ok(calendar.Closed("synthetic closure")))
  dataset.trading_day(value, on: civil(2024, 1, 6))
  |> should.equal(
    Error(dataset.OutsideCoverage(
      civil(2024, 1, 1),
      civil(2024, 1, 5),
      civil(2024, 1, 6),
    )),
  )
}

pub fn official_2026_calendars_are_venue_owned_and_bounded_test() {
  let assert Ok(sse) = cn_calendar.official_2026(identity.Sse)
  let assert Ok(szse) = cn_calendar.official_2026(identity.Szse)
  let assert Ok(bse) = cn_calendar.official_2026(identity.Bse)

  source.provider(dataset.source(sse)) |> should.equal("sse")
  source.provider(dataset.source(szse)) |> should.equal("szse")
  source.provider(dataset.source(bse)) |> should.equal("bse")
  dataset.version(sse) |> should.equal("official-2026-v1")

  dataset.trading_day(sse, on: civil(2026, 2, 20))
  |> should.equal(Ok(calendar.Closed("spring_festival")))
  let assert Ok(calendar.Open(sessions)) =
    dataset.trading_day(sse, on: civil(2026, 2, 24))
  list.length(sessions) |> should.equal(4)
  dataset.trading_day(sse, on: civil(2027, 1, 4))
  |> should.equal(
    Error(dataset.OutsideCoverage(
      civil(2026, 1, 1),
      civil(2026, 12, 31),
      civil(2027, 1, 4),
    )),
  )
}

fn synthetic_dataset(venue: identity.Venue) -> dataset.Dataset {
  let sessions = [
    session("synthetic opening auction", 9, 15, 9, 25),
    session("synthetic morning", 9, 30, 11, 30),
    session("synthetic afternoon", 13, 0, 14, 57),
    session("synthetic closing auction", 14, 57, 15, 0),
  ]
  let assert Ok(value) =
    cn_calendar.new(
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
      weekly: cn_calendar.weekday_template(sessions),
      overrides: [#(civil(2024, 1, 2), calendar.Closed("synthetic closure"))],
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
      zone: cn_calendar.shanghai_zone(),
      utc_offset_minutes: 480,
    )
  value
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new(
      provider: "synthetic-cn-calendar",
      reference: "fixture/mainland-calendar",
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
