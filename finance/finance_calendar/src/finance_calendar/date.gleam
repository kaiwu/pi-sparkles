import finance_core/time.{type Date}
import gleam/int
import gleam/order.{type Order}

pub type Weekday {
  Monday
  Tuesday
  Wednesday
  Thursday
  Friday
  Saturday
  Sunday
}

pub type MonthPolicy {
  ClampDay
  RejectInvalidDay
}

pub type DateError {
  InvalidResult
  InvalidMonthShift
}

pub fn compare(left: Date, right: Date) -> Order {
  int.compare(ordinal(left), ordinal(right))
}

/// Proleptic Gregorian ordinal where 0001-01-01 is day 1.
pub fn ordinal(date: Date) -> Int {
  let #(year, month, day) = time.date_parts(date)
  let previous_year = year - 1
  365
  * previous_year
  + previous_year
  / 4
  - previous_year
  / 100
  + previous_year
  / 400
  + days_before_month(year, month)
  + day
}

pub fn weekday(date: Date) -> Weekday {
  case { ordinal(date) - 1 } % 7 {
    0 -> Monday
    1 -> Tuesday
    2 -> Wednesday
    3 -> Thursday
    4 -> Friday
    5 -> Saturday
    _ -> Sunday
  }
}

/// Signed actual-day distance, excluding the start and including the end.
pub fn days_between(start: Date, end: Date) -> Int {
  ordinal(end) - ordinal(start)
}

pub fn add_days(date: Date, days: Int) -> Result(Date, DateError) {
  let target = ordinal(date) + days
  case target >= 1 {
    True -> from_ordinal(target)
    False -> Error(InvalidResult)
  }
}

pub fn from_ordinal(value: Int) -> Result(Date, DateError) {
  case value >= 1 {
    False -> Error(InvalidResult)
    True -> {
      let upper_year = { value - 1 } / 365 + 1
      let year = find_year(value, 1, upper_year)
      let assert Ok(year_start) = time.date(year, 1, 1)
      date_from_day_of_year(year, value - ordinal(year_start) + 1, 1)
    }
  }
}

pub fn add_months(
  date: Date,
  months: Int,
  policy: MonthPolicy,
) -> Result(Date, DateError) {
  let #(year, month, day) = time.date_parts(date)
  let absolute_month = { year - 1 } * 12 + { month - 1 } + months
  case absolute_month < 0 {
    True -> Error(InvalidMonthShift)
    False -> {
      let target_year = absolute_month / 12 + 1
      let target_month = absolute_month % 12 + 1
      let maximum_day = days_in_month(target_year, target_month)
      case day <= maximum_day, policy {
        True, _ -> make_date(target_year, target_month, day)
        False, ClampDay -> make_date(target_year, target_month, maximum_day)
        False, RejectInvalidDay -> Error(InvalidResult)
      }
    }
  }
}

pub fn is_end_of_month(date: Date) -> Bool {
  let #(year, month, day) = time.date_parts(date)
  day == days_in_month(year, month)
}

pub fn days_in_year(year: Int) -> Int {
  case is_leap_year(year) {
    True -> 366
    False -> 365
  }
}

pub fn days_in_month(year: Int, month: Int) -> Int {
  case month {
    2 ->
      case is_leap_year(year) {
        True -> 29
        False -> 28
      }
    4 | 6 | 9 | 11 -> 30
    _ -> 31
  }
}

pub fn is_leap_year(year: Int) -> Bool {
  year % 400 == 0 || { year % 4 == 0 && year % 100 != 0 }
}

fn find_year(target: Int, lower: Int, upper: Int) -> Int {
  case lower >= upper {
    True -> lower
    False -> {
      let middle = { lower + upper + 1 } / 2
      let assert Ok(middle_start) = time.date(middle, 1, 1)
      case ordinal(middle_start) <= target {
        True -> find_year(target, middle, upper)
        False -> find_year(target, lower, middle - 1)
      }
    }
  }
}

fn date_from_day_of_year(
  year: Int,
  remaining: Int,
  month: Int,
) -> Result(Date, DateError) {
  let month_days = days_in_month(year, month)
  case remaining <= month_days {
    True -> make_date(year, month, remaining)
    False -> date_from_day_of_year(year, remaining - month_days, month + 1)
  }
}

fn days_before_month(year: Int, month: Int) -> Int {
  let ordinary = case month {
    1 -> 0
    2 -> 31
    3 -> 59
    4 -> 90
    5 -> 120
    6 -> 151
    7 -> 181
    8 -> 212
    9 -> 243
    10 -> 273
    11 -> 304
    _ -> 334
  }
  case month > 2 && is_leap_year(year) {
    True -> ordinary + 1
    False -> ordinary
  }
}

fn make_date(year: Int, month: Int, day: Int) -> Result(Date, DateError) {
  case time.date(year, month, day) {
    Ok(date) -> Ok(date)
    Error(_) -> Error(InvalidResult)
  }
}
