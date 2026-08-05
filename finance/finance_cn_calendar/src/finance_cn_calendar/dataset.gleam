import finance_calendar/calendar
import finance_calendar/date
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
