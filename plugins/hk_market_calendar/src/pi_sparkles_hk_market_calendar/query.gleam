import finance_calendar/calendar.{type TradingDay}
import finance_core/time.{type Date}
import finance_hk_calendar/dataset as hk_calendar
import finance_market_calendar/dataset.{type Dataset}

pub type QueryError {
  InvalidDataset(hk_calendar.CalendarDatasetError)
  OutsideCoverage(dataset.QueryError)
}

pub type ResultValue {
  ResultValue(dataset: Dataset, date: Date, day: TradingDay)
}

pub fn run(on date: Date) -> Result(ResultValue, QueryError) {
  case hk_calendar.official_2026() {
    Error(error) -> Error(InvalidDataset(error))
    Ok(calendar_dataset) ->
      case dataset.trading_day(calendar_dataset, on: date) {
        Error(error) -> Error(OutsideCoverage(error))
        Ok(day) -> Ok(ResultValue(calendar_dataset, date, day))
      }
  }
}
