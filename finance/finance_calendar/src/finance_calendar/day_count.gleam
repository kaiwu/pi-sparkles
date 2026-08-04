import finance_calendar/date
import finance_core/time.{type Date}
import gleam/int
import gleam/order.{Eq, Gt, Lt}

pub type Convention {
  Actual360
  Actual365Fixed
  ActualActualIsda
  Thirty360Us
  ThirtyE360
}

/// Signed convention-specific numerator in days.
pub fn days(start: Date, end: Date, convention: Convention) -> Int {
  case date.compare(start, end) {
    Eq -> 0
    Gt -> 0 - days(end, start, convention)
    Lt ->
      case convention {
        Actual360 | Actual365Fixed | ActualActualIsda ->
          date.days_between(start, end)
        Thirty360Us -> thirty_360_us(start, end)
        ThirtyE360 -> thirty_e_360(start, end)
      }
  }
}

/// Signed year fraction under the named convention.
pub fn year_fraction(start: Date, end: Date, convention: Convention) -> Float {
  case date.compare(start, end) {
    Eq -> 0.0
    Gt -> 0.0 -. year_fraction(end, start, convention)
    Lt ->
      case convention {
        Actual360 -> int.to_float(date.days_between(start, end)) /. 360.0
        Actual365Fixed -> int.to_float(date.days_between(start, end)) /. 365.0
        Thirty360Us -> int.to_float(thirty_360_us(start, end)) /. 360.0
        ThirtyE360 -> int.to_float(thirty_e_360(start, end)) /. 360.0
        ActualActualIsda -> actual_actual_isda(start, end)
      }
  }
}

fn thirty_360_us(start: Date, end: Date) -> Int {
  let #(start_year, start_month, start_day_raw) = time.date_parts(start)
  let #(end_year, end_month, end_day_raw) = time.date_parts(end)
  let start_is_february_end = start_month == 2 && date.is_end_of_month(start)
  let end_is_february_end = end_month == 2 && date.is_end_of_month(end)
  let start_day = case start_day_raw == 31 || start_is_february_end {
    True -> 30
    False -> start_day_raw
  }
  let end_day = case
    { end_is_february_end && start_is_february_end }
    || { end_day_raw == 31 && start_day >= 30 }
  {
    True -> 30
    False -> end_day_raw
  }
  360
  * { end_year - start_year }
  + 30
  * { end_month - start_month }
  + { end_day - start_day }
}

fn thirty_e_360(start: Date, end: Date) -> Int {
  let #(start_year, start_month, start_day) = time.date_parts(start)
  let #(end_year, end_month, end_day) = time.date_parts(end)
  360
  * { end_year - start_year }
  + 30
  * { end_month - start_month }
  + { int.min(end_day, 30) - int.min(start_day, 30) }
}

fn actual_actual_isda(start: Date, end: Date) -> Float {
  let #(start_year, _, _) = time.date_parts(start)
  let #(end_year, _, _) = time.date_parts(end)
  case start_year == end_year {
    True ->
      int.to_float(date.days_between(start, end))
      /. int.to_float(date.days_in_year(start_year))
    False -> {
      let assert Ok(next_year_start) = time.date(start_year + 1, 1, 1)
      let assert Ok(end_year_start) = time.date(end_year, 1, 1)
      let first =
        int.to_float(date.days_between(start, next_year_start))
        /. int.to_float(date.days_in_year(start_year))
      let middle = int.to_float(end_year - start_year - 1)
      let last =
        int.to_float(date.days_between(end_year_start, end))
        /. int.to_float(date.days_in_year(end_year))
      first +. middle +. last
    }
  }
}
