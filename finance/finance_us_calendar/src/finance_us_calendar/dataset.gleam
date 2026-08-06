import finance_calendar/calendar
import finance_calendar/date
import finance_calendar/local
import finance_core/identifier.{type Mic}
import finance_core/source
import finance_core/time
import finance_market_calendar/dataset as market_dataset
import finance_provenance/evidence.{type Licence}
import finance_track
import finance_track/context as track_context
import gleam/option.{None, Some}

pub type Venue {
  Nyse
  Nasdaq
}

pub type CalendarDatasetError {
  InvalidCalendar(calendar.CalendarError)
  InvalidContext(track_context.ContextError)
  InvalidDataset(market_dataset.DatasetError)
}

/// Construct one explicitly sourced, venue-scoped US calendar.
///
/// `weekly` and `overrides` are caller data. Only `official_2026` supplies a
/// source-reviewed exchange schedule.
pub fn new(
  venue venue: Venue,
  version version: String,
  coverage_start coverage_start: time.Date,
  coverage_end coverage_end: time.Date,
  source source_ref: source.SourceRef,
  licence licence: Licence,
  entitlement entitlement: String,
  limitations limitations: List(String),
  weekly weekly: List(#(date.Weekday, calendar.TradingDay)),
  overrides overrides: List(#(time.Date, calendar.TradingDay)),
) -> Result(market_dataset.Dataset, CalendarDatasetError) {
  let zone = new_york_zone()
  let venue_label = venue_name(venue)
  case
    calendar.new(
      name: "us " <> venue_label <> " equities " <> version,
      zone: zone,
      weekly: weekly,
      overrides: overrides,
    )
  {
    Error(error) -> Error(InvalidCalendar(error))
    Ok(market_calendar) ->
      case
        track_context.new(
          track: finance_track.Us,
          market_scope: "us_" <> venue_label <> "_trading_calendar",
          venue_mic: Some(venue_mic(venue)),
          board: None,
          timezone: Some(zone),
          source_language: "en-US",
          providers: [source.provider(source_ref)],
          entitlement: entitlement,
          limitations: limitations,
        )
      {
        Error(error) -> Error(InvalidContext(error))
        Ok(track_context) ->
          case
            market_dataset.new(
              context: track_context,
              calendar: market_calendar,
              version: version,
              coverage_start: coverage_start,
              coverage_end: coverage_end,
              source: source_ref,
              licence: licence,
            )
          {
            Ok(value) -> Ok(value)
            Error(error) -> Error(InvalidDataset(error))
          }
      }
  }
}

pub fn weekday_template(
  sessions: List(calendar.Session),
) -> List(#(date.Weekday, calendar.TradingDay)) {
  [
    #(date.Monday, calendar.Open(sessions)),
    #(date.Tuesday, calendar.Open(sessions)),
    #(date.Wednesday, calendar.Open(sessions)),
    #(date.Thursday, calendar.Open(sessions)),
    #(date.Friday, calendar.Open(sessions)),
  ]
}

/// NYSE and Nasdaq's published 2026 regular-equity schedules.
///
/// Coverage is intentionally limited to calendar year 2026. Later exchange
/// alerts and exceptional closures supersede this planned schedule.
pub fn official_2026(
  venue venue: Venue,
) -> Result(market_dataset.Dataset, CalendarDatasetError) {
  new(
    venue: venue,
    version: "official-2026-v1",
    coverage_start: civil(2026, 1, 1),
    coverage_end: civil(2026, 12, 31),
    source: official_2026_source(venue),
    licence: evidence.Licence(
      venue_name(venue) <> "-public-trading-calendar",
      evidence.UnknownRedistribution,
      Some(
        "Public exchange schedule used for local analysis; redistribution permission is not inferred",
      ),
    ),
    entitlement: "public_official_web_local_analysis",
    limitations: [
      "calendar_year_2026_only",
      "planned_schedule_may_be_superseded_by_exchange_alert_or_exceptional_notice",
      "regular_equity_session_only",
      "pre_market_after_hours_auctions_options_and_bonds_excluded",
      "settlement_and_finra_reporting_calendars_are_separate",
      "early_close_system_hours_require_exchange_alert",
      "redistribution_rights_unknown",
    ],
    weekly: weekday_template(regular_session()),
    overrides: us_2026_overrides(),
  )
}

pub fn official_2026_source(venue: Venue) -> source.SourceRef {
  let #(provider, reference) = case venue {
    Nyse -> #("nyse", "https://www.nyse.com/trade/hours-calendars")
    Nasdaq -> #(
      "nasdaq",
      "https://www.nasdaqtrader.com/trader.aspx?id=Calendar",
    )
  }
  let assert Ok(value) =
    source.new(provider: provider, reference: reference, kind: source.Exchange)
  value
}

pub fn regular_session() -> List(calendar.Session) {
  [session("regular_market", 9, 30, 16, 0)]
}

pub fn early_close_session() -> List(calendar.Session) {
  [session("regular_market_early_close", 9, 30, 13, 0)]
}

pub fn us_2026_overrides() -> List(#(time.Date, calendar.TradingDay)) {
  [
    closure(1, 1, "new_years_day"),
    closure(1, 19, "martin_luther_king_jr_day"),
    closure(2, 16, "washingtons_birthday_presidents_day"),
    closure(4, 3, "good_friday"),
    closure(5, 25, "memorial_day"),
    closure(6, 19, "juneteenth_national_independence_day"),
    closure(7, 3, "independence_day_observed"),
    closure(9, 7, "labor_day"),
    closure(11, 26, "thanksgiving_day"),
    early_close(11, 27),
    early_close(12, 24),
    closure(12, 25, "christmas_day"),
  ]
}

pub fn venue_name(value: Venue) -> String {
  case value {
    Nyse -> "nyse"
    Nasdaq -> "nasdaq"
  }
}

pub fn venue_mic(value: Venue) -> Mic {
  let assert Ok(value) = identifier.mic(venue_mic_text(value))
  value
}

pub fn new_york_zone() -> time.Timezone {
  let assert Ok(value) = time.timezone("America/New_York")
  value
}

fn venue_mic_text(value: Venue) -> String {
  case value {
    Nyse -> "XNYS"
    Nasdaq -> "XNAS"
  }
}

fn closure(
  month: Int,
  day: Int,
  reason: String,
) -> #(time.Date, calendar.TradingDay) {
  #(civil(2026, month, day), calendar.Closed(reason))
}

fn early_close(month: Int, day: Int) -> #(time.Date, calendar.TradingDay) {
  #(civil(2026, month, day), calendar.Open(early_close_session()))
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn session(
  label: String,
  open_hour: Int,
  open_minute: Int,
  close_hour: Int,
  close_minute: Int,
) -> calendar.Session {
  let assert Ok(opens_at) = local.local_time(open_hour, open_minute)
  let assert Ok(closes_at) = local.local_time(close_hour, close_minute)
  let assert Ok(value) =
    calendar.session(
      label: label,
      opens_at: opens_at,
      closes_at: closes_at,
      close_day: calendar.SameDay,
    )
  value
}
