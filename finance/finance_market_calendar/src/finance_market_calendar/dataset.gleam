import finance_calendar/calendar.{
  type Calendar, type SessionOccurrence, type TradingDay,
}
import finance_calendar/date
import finance_calendar/local.{type ZonedDateTime}
import finance_core/source.{type SourceRef}
import finance_core/time.{type Date}
import finance_provenance/evidence.{type Licence}
import finance_track/context.{type Context}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/string

/// A versioned, source-labelled calendar whose queries fail outside declared
/// coverage rather than falling back to a weekday assumption.
pub opaque type Dataset {
  Dataset(
    context: Context,
    calendar: Calendar,
    version: String,
    coverage_start: Date,
    coverage_end: Date,
    source: SourceRef,
    licence: Licence,
  )
}

pub type DatasetError {
  InvalidVersion
  InvalidCoverage
  MissingContextTimezone
  TimezoneMismatch(expected: String, received: String)
  SourceProviderNotDeclared(provider: String)
}

pub type QueryError {
  OutsideCoverage(start: Date, end: Date, received: Date)
  CalendarError(calendar.CalendarError)
}

pub fn new(
  context track_context: Context,
  calendar market_calendar: Calendar,
  version version: String,
  coverage_start coverage_start: Date,
  coverage_end coverage_end: Date,
  source source_ref: SourceRef,
  licence licence: Licence,
) -> Result(Dataset, DatasetError) {
  case valid_version(version), date.compare(coverage_start, coverage_end) {
    False, _ -> Error(InvalidVersion)
    _, Gt -> Error(InvalidCoverage)
    True, Lt ->
      validate_context(
        track_context,
        market_calendar,
        source_ref,
        Dataset(
          track_context,
          market_calendar,
          version,
          coverage_start,
          coverage_end,
          source_ref,
          licence,
        ),
      )
    True, Eq ->
      validate_context(
        track_context,
        market_calendar,
        source_ref,
        Dataset(
          track_context,
          market_calendar,
          version,
          coverage_start,
          coverage_end,
          source_ref,
          licence,
        ),
      )
  }
}

pub fn context(value: Dataset) -> Context {
  value.context
}

pub fn version(value: Dataset) -> String {
  value.version
}

pub fn coverage(value: Dataset) -> #(Date, Date) {
  #(value.coverage_start, value.coverage_end)
}

pub fn source(value: Dataset) -> SourceRef {
  value.source
}

pub fn licence(value: Dataset) -> Licence {
  value.licence
}

pub fn calendar_name(value: Dataset) -> String {
  calendar.name(value.calendar)
}

pub fn trading_day(
  value: Dataset,
  on date_value: Date,
) -> Result(TradingDay, QueryError) {
  case within_coverage(value, date_value) {
    False ->
      Error(OutsideCoverage(
        value.coverage_start,
        value.coverage_end,
        date_value,
      ))
    True -> Ok(calendar.trading_day(value.calendar, on: date_value))
  }
}

pub fn session_at(
  value: Dataset,
  local_date_time: ZonedDateTime,
) -> Result(Option(SessionOccurrence), QueryError) {
  case within_coverage(value, local_date_time.date) {
    False ->
      Error(OutsideCoverage(
        value.coverage_start,
        value.coverage_end,
        local_date_time.date,
      ))
    True ->
      case calendar.session_at(value.calendar, local_date_time) {
        Ok(value) -> Ok(value)
        Error(error) -> Error(CalendarError(error))
      }
  }
}

fn validate_context(
  track_context: Context,
  market_calendar: Calendar,
  source_ref: SourceRef,
  value: Dataset,
) -> Result(Dataset, DatasetError) {
  case context.timezone(track_context) {
    None -> Error(MissingContextTimezone)
    Some(context_zone) -> {
      let expected = time.timezone_name(context_zone)
      let received = calendar.zone(market_calendar) |> local.zone_name
      let provider = source.provider(source_ref)
      case
        expected == received,
        list.contains(context.providers(track_context), provider)
      {
        False, _ -> Error(TimezoneMismatch(expected, received))
        _, False -> Error(SourceProviderNotDeclared(provider))
        True, True -> Ok(value)
      }
    }
  }
}

fn within_coverage(value: Dataset, date_value: Date) -> Bool {
  date.compare(date_value, value.coverage_start) != Lt
  && date.compare(date_value, value.coverage_end) != Gt
}

fn valid_version(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}
