import finance_calendar/calendar
import finance_calendar/date
import finance_calendar/local
import finance_core/source
import finance_core/time
import finance_hk_identity/identity as hk_identity
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

pub fn new(
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
  let zone = hong_kong_zone()
  case
    calendar.new(
      name: "hk xhkg equities " <> version,
      zone: zone,
      weekly: weekly,
      overrides: overrides,
    )
  {
    Error(error) -> Error(InvalidCalendar(error))
    Ok(market_calendar) ->
      case
        track_context.new(
          track: finance_track.Hk,
          market_scope: "hk_xhkg_trading_calendar",
          venue_mic: Some(hk_identity.venue_mic()),
          board: None,
          timezone: Some(zone),
          source_language: "zh-HK",
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

/// The Stock Exchange of Hong Kong's published 2026 securities-market
/// schedule. It preserves full closures and the three published half-days.
/// Coverage is intentionally limited to calendar year 2026.
pub fn official_2026() -> Result(market_dataset.Dataset, CalendarDatasetError) {
  new(
    version: "official-2026-ct-075-25-v1",
    coverage_start: civil(2026, 1, 1),
    coverage_end: civil(2026, 12, 31),
    source: official_2026_source(),
    licence: evidence.Licence(
      "hkex-public-calendar-circular",
      evidence.UnknownRedistribution,
      Some(
        "Public exchange circular used for local analysis; redistribution permission is not inferred",
      ),
    ),
    entitlement: "public_official_web_local_analysis",
    limitations: [
      "calendar_year_2026_only",
      "planned_schedule_may_be_superseded_by_later_exceptional_notice",
      "securities_market_only",
      "extended_morning_and_random_closing_windows_not_classified",
      "settlement_and_stock_connect_calendars_are_separate",
      "redistribution_rights_unknown",
    ],
    weekly: weekday_template(full_day_sessions()),
    overrides: hk_2026_overrides(),
  )
}

pub fn official_2026_source() -> source.SourceRef {
  let assert Ok(value) =
    source.new(
      provider: "hkex",
      reference: "https://www.hkex.com.hk/-/media/HKEX-Market/Services/Circulars-and-Notices/Participant-and-Members-Circulars/SEHK/2025/ce_SEHK_CT_075_2025.pdf",
      kind: source.Exchange,
    )
  value
}

pub fn full_day_sessions() -> List(calendar.Session) {
  [
    session("pre_opening", 9, 0, 9, 30),
    session("continuous_morning", 9, 30, 12, 0),
    session("continuous_afternoon", 13, 0, 16, 0),
  ]
}

pub fn half_day_sessions() -> List(calendar.Session) {
  [
    session("pre_opening", 9, 0, 9, 30),
    session("continuous_morning", 9, 30, 12, 0),
  ]
}

pub fn hk_2026_overrides() -> List(#(time.Date, calendar.TradingDay)) {
  [
    closure(1, 1, "first_day_of_january"),
    half_day(2, 16, "eve_of_lunar_new_year"),
    closure(2, 17, "lunar_new_year"),
    closure(2, 18, "second_day_of_lunar_new_year"),
    closure(2, 19, "third_day_of_lunar_new_year"),
    closure(4, 3, "good_friday"),
    closure(4, 6, "day_following_ching_ming_festival"),
    closure(4, 7, "day_following_easter_monday"),
    closure(5, 1, "labour_day"),
    closure(5, 25, "day_following_birthday_of_the_buddha"),
    closure(6, 19, "tuen_ng_festival"),
    closure(7, 1, "hksar_establishment_day"),
    closure(10, 1, "national_day"),
    closure(10, 19, "day_following_chung_yeung_festival"),
    half_day(12, 24, "eve_of_christmas_day"),
    closure(12, 25, "christmas_day"),
    half_day(12, 31, "eve_of_new_year"),
  ]
}

pub fn hong_kong_zone() -> time.Timezone {
  let assert Ok(value) = time.timezone("Asia/Hong_Kong")
  value
}

fn closure(
  month: Int,
  day: Int,
  reason: String,
) -> #(time.Date, calendar.TradingDay) {
  #(civil(2026, month, day), calendar.Closed(reason))
}

fn half_day(
  month: Int,
  day: Int,
  _reason: String,
) -> #(time.Date, calendar.TradingDay) {
  #(civil(2026, month, day), calendar.Open(half_day_sessions()))
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
