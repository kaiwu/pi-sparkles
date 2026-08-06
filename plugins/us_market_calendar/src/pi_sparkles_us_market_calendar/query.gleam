import finance_calendar/calendar.{type TradingDay}
import finance_core/time.{type Date}
import finance_market_calendar/dataset.{type Dataset}
import finance_us_calendar/dataset as us_calendar

pub type Venue {
  Nyse
  Nasdaq
}

pub type QueryError {
  InvalidVenue
  InvalidDataset(us_calendar.CalendarDatasetError)
  OutsideCoverage(dataset.QueryError)
}

pub type ResultValue {
  ResultValue(venue: Venue, dataset: Dataset, date: Date, day: TradingDay)
}

pub fn venue_from_name(value: String) -> Result(Venue, QueryError) {
  case value {
    "nyse" -> Ok(Nyse)
    "nasdaq" -> Ok(Nasdaq)
    _ -> Error(InvalidVenue)
  }
}

pub fn venue_name(value: Venue) -> String {
  case value {
    Nyse -> "nyse"
    Nasdaq -> "nasdaq"
  }
}

pub fn run(
  venue venue: Venue,
  on date: Date,
) -> Result(ResultValue, QueryError) {
  let market_venue = case venue {
    Nyse -> us_calendar.Nyse
    Nasdaq -> us_calendar.Nasdaq
  }
  case us_calendar.official_2026(market_venue) {
    Error(error) -> Error(InvalidDataset(error))
    Ok(calendar_dataset) ->
      case dataset.trading_day(calendar_dataset, on: date) {
        Error(error) -> Error(OutsideCoverage(error))
        Ok(day) -> Ok(ResultValue(venue, calendar_dataset, date, day))
      }
  }
}
