import finance_calendar/calendar
import finance_calendar/date
import finance_calendar/local
import finance_cn_identity/identity as cn_identity
import finance_core/source
import finance_core/time
import finance_market_calendar/dataset as market_dataset
import finance_provenance/evidence.{type Licence}
import finance_track
import finance_track/context as track_context
import gleam/option.{None, Some}

pub type CalendarDatasetError {
  InvalidCalendar(calendar.CalendarError)
  InvalidContext(track_context.ContextError)
  InvalidDataset(market_dataset.DatasetError)
}

/// Construct one explicitly sourced, coverage-bounded mainland calendar.
///
/// `weekly` and `overrides` are provider data. This package does not bundle or
/// infer an authoritative holiday set.
pub fn new(
  venue venue: cn_identity.Venue,
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
  let zone = shanghai_zone()
  let name = "cn " <> venue_name(venue) <> " equities " <> version
  case
    calendar.new(name: name, zone: zone, weekly: weekly, overrides: overrides)
  {
    Error(error) -> Error(InvalidCalendar(error))
    Ok(market_calendar) ->
      case
        track_context.new(
          track: finance_track.Cn,
          market_scope: "cn_" <> venue_name(venue) <> "_trading_calendar",
          venue_mic: Some(cn_identity.venue_mic(venue)),
          board: None,
          timezone: Some(zone),
          source_language: "zh-CN",
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

/// Monday-through-Friday base template. Dated provider overrides are still
/// required for authoritative use.
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

/// The venue-published 2026 mainland equity calendar.
///
/// Each venue gets its own source reference even though the published holiday
/// dates coincide. Coverage is deliberately limited to calendar year 2026;
/// callers must refresh the dataset for later years and must treat a later
/// exceptional-closure notice as superseding this planned schedule.
pub fn official_2026(
  venue venue: cn_identity.Venue,
) -> Result(market_dataset.Dataset, CalendarDatasetError) {
  new(
    venue: venue,
    version: "official-2026-v1",
    coverage_start: civil(2026, 1, 1),
    coverage_end: civil(2026, 12, 31),
    source: official_2026_source(venue),
    licence: evidence.Licence(
      venue_licence_label(venue),
      evidence.UnknownRedistribution,
      Some(
        "Public venue notice used for local analysis; redistribution permission is not inferred",
      ),
    ),
    entitlement: "public_official_web_local_analysis",
    limitations: [
      "calendar_year_2026_only",
      "planned_schedule_may_be_superseded_by_later_exceptional_notice",
      "equity_auction_and_continuous_sessions_only",
      "settlement_and_stock_connect_calendars_are_separate",
      "redistribution_rights_unknown",
    ],
    weekly: weekday_template(mainland_equity_sessions()),
    overrides: mainland_2026_closures(),
  )
}

pub fn official_2026_source(venue: cn_identity.Venue) -> source.SourceRef {
  let #(provider, reference) = case venue {
    cn_identity.Sse -> #(
      "sse",
      "https://www.sse.com.cn/disclosure/dealinstruc/closed/",
    )
    cn_identity.Szse -> #(
      "szse",
      "https://investor.szse.cn/disclosure/notice/general/t20251222_618087.html",
    )
    cn_identity.Bse -> #(
      "bse",
      "https://www.bse.cn/important_news/200027428.html",
    )
  }
  let assert Ok(value) =
    source.new(provider: provider, reference: reference, kind: source.Exchange)
  value
}

pub fn mainland_equity_sessions() -> List(calendar.Session) {
  [
    session("opening_call_auction", 9, 15, 9, 25),
    session("continuous_auction_morning", 9, 30, 11, 30),
    session("continuous_auction_afternoon", 13, 0, 14, 57),
    session("closing_call_auction", 14, 57, 15, 0),
  ]
}

pub fn mainland_2026_closures() -> List(#(time.Date, calendar.TradingDay)) {
  [
    closure(1, 1, "new_year"),
    closure(1, 2, "new_year"),
    closure(2, 16, "spring_festival"),
    closure(2, 17, "spring_festival"),
    closure(2, 18, "spring_festival"),
    closure(2, 19, "spring_festival"),
    closure(2, 20, "spring_festival"),
    closure(2, 23, "spring_festival"),
    closure(4, 6, "qingming_festival"),
    closure(5, 1, "labour_day"),
    closure(5, 4, "labour_day"),
    closure(5, 5, "labour_day"),
    closure(6, 19, "dragon_boat_festival"),
    closure(9, 25, "mid_autumn_festival"),
    closure(10, 1, "national_day"),
    closure(10, 2, "national_day"),
    closure(10, 5, "national_day"),
    closure(10, 6, "national_day"),
    closure(10, 7, "national_day"),
  ]
}

pub fn shanghai_zone() -> time.Timezone {
  let assert Ok(value) = time.timezone("Asia/Shanghai")
  value
}

fn venue_name(value: cn_identity.Venue) -> String {
  case value {
    cn_identity.Sse -> "sse"
    cn_identity.Szse -> "szse"
    cn_identity.Bse -> "bse"
  }
}

fn venue_licence_label(value: cn_identity.Venue) -> String {
  venue_name(value) <> "-public-calendar-notice"
}

fn closure(
  month: Int,
  day: Int,
  reason: String,
) -> #(time.Date, calendar.TradingDay) {
  #(civil(2026, month, day), calendar.Closed(reason))
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
