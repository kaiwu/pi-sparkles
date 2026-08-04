import finance_calendar/business.{type BusinessError}
import finance_calendar/calendar.{type Calendar}
import finance_calendar/date
import finance_core/time.{type Date}
import gleam/int
import gleam/list
import gleam/order.{Eq, Gt, Lt}

pub type DayCountError {
  InvalidCouponFrequency
  InvalidReferencePeriod
  BusinessCalendarFailure(error: BusinessError)
  DateFailure
}

pub type Convention {
  Actual360
  Actual365Fixed
  ActualActualIsda
  Thirty360Us
  ThirtyE360
}

/// Actual/Actual ICMA for an accrual contained in one reference coupon period.
pub fn actual_actual_icma(
  start: Date,
  end: Date,
  reference_start: Date,
  reference_end: Date,
  coupons_per_year: Int,
) -> Result(Float, DayCountError) {
  case
    coupons_per_year > 0,
    date.compare(reference_start, reference_end),
    date.compare(start, end),
    date.compare(start, reference_start),
    date.compare(end, reference_end)
  {
    False, _, _, _, _ -> Error(InvalidCouponFrequency)
    _, Eq, _, _, _ -> Error(InvalidReferencePeriod)
    _, Gt, _, _, _ -> Error(InvalidReferencePeriod)
    _, _, Gt, _, _ -> Error(InvalidReferencePeriod)
    _, _, _, Lt, _ -> Error(InvalidReferencePeriod)
    _, _, _, _, Gt -> Error(InvalidReferencePeriod)
    True, Lt, Eq, _, _ -> Ok(0.0)
    True, Lt, Lt, _, _ ->
      Ok(
        int.to_float(date.days_between(start, end))
        /. int.to_float(date.days_between(reference_start, reference_end))
        /. int.to_float(coupons_per_year),
      )
  }
}

/// 30E/360 ISDA with explicit termination-date treatment.
pub fn thirty_e_360_isda_days(
  start: Date,
  end: Date,
  end_is_termination_date: Bool,
) -> Int {
  case date.compare(start, end) {
    Eq -> 0
    Gt -> 0 - thirty_e_360_isda_days(end, start, False)
    Lt -> {
      let #(start_year, start_month, start_raw) = time.date_parts(start)
      let #(end_year, end_month, end_raw) = time.date_parts(end)
      let start_day = case start_raw == 31 || date.is_end_of_month(start) {
        True -> 30
        False -> start_raw
      }
      let end_day = case
        end_raw == 31
        || { date.is_end_of_month(end) && !end_is_termination_date }
      {
        True -> 30
        False -> end_raw
      }
      360
      * { end_year - start_year }
      + 30
      * { end_month - start_month }
      + { end_day - start_day }
    }
  }
}

/// Business/252 over the half-open interval `[start, end)`.
pub fn business_252(
  start: Date,
  end: Date,
  calendar calendar_value: Calendar,
  maximum_scan_days maximum_scan_days: Int,
) -> Result(Float, DayCountError) {
  case date.compare(start, end) {
    Eq -> Ok(0.0)
    Gt ->
      case business_252(end, start, calendar_value, maximum_scan_days) {
        Ok(value) -> Ok(0.0 -. value)
        Error(error) -> Error(error)
      }
    Lt ->
      case date.add_days(end, -1) {
        Error(_) -> Error(DateFailure)
        Ok(last) ->
          case
            business.open_dates_between(
              calendar_value,
              start: start,
              end: last,
              maximum_scan_days: maximum_scan_days,
            )
          {
            Error(error) -> Error(BusinessCalendarFailure(error))
            Ok(dates) -> Ok(int.to_float(list.length(dates)) /. 252.0)
          }
      }
  }
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
