import finance_calendar/calendar
import finance_calendar/date
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

pub fn hong_kong_zone() -> time.Timezone {
  let assert Ok(value) = time.timezone("Asia/Hong_Kong")
  value
}
