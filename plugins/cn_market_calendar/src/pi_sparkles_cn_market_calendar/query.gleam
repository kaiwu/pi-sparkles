import finance_calendar/calendar.{type TradingDay}
import finance_cn_calendar/dataset as cn_calendar
import finance_cn_identity/identity
import finance_core/time.{type Date}
import finance_market_calendar/dataset.{type Dataset}

pub type Venue {
  Sse
  Szse
  Bse
}

pub type QueryError {
  InvalidVenue
  InvalidDataset(cn_calendar.CalendarDatasetError)
  OutsideCoverage(dataset.QueryError)
}

pub type ResultValue {
  ResultValue(venue: Venue, dataset: Dataset, date: Date, day: TradingDay)
}

pub fn venue_from_name(value: String) -> Result(Venue, QueryError) {
  case value {
    "sse" -> Ok(Sse)
    "szse" -> Ok(Szse)
    "bse" -> Ok(Bse)
    _ -> Error(InvalidVenue)
  }
}

pub fn venue_name(value: Venue) -> String {
  case value {
    Sse -> "sse"
    Szse -> "szse"
    Bse -> "bse"
  }
}

pub fn run(
  venue venue: Venue,
  on date: Date,
) -> Result(ResultValue, QueryError) {
  let market_venue = case venue {
    Sse -> identity.Sse
    Szse -> identity.Szse
    Bse -> identity.Bse
  }
  case cn_calendar.official_2026(market_venue) {
    Error(error) -> Error(InvalidDataset(error))
    Ok(calendar_dataset) ->
      case dataset.trading_day(calendar_dataset, on: date) {
        Error(error) -> Error(OutsideCoverage(error))
        Ok(day) -> Ok(ResultValue(venue, calendar_dataset, date, day))
      }
  }
}
