import finance_core/time
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

const maximum_duration_seconds = 8_640_000_000_000

/// Parse the two standard `Retry-After` representations without reading a
/// clock: non-negative delta-seconds or an IMF-fixdate in GMT.
pub fn parse(value: String, now: time.Instant) -> Option(time.Duration) {
  let normalized = string.trim(value)
  case int.parse(normalized) {
    Ok(seconds) if seconds >= 0 && seconds <= maximum_duration_seconds ->
      duration(seconds * 1000)
    _ -> parse_http_date(normalized, now)
  }
}

fn parse_http_date(value: String, now: time.Instant) -> Option(time.Duration) {
  let parts =
    value
    |> string.split(" ")
    |> list.filter(fn(part) { part != "" })
  case parts {
    [weekday, day, month, year, clock, "GMT"] ->
      parse_date_parts(weekday, day, month, year, clock, now)
    _ -> None
  }
}

fn parse_date_parts(
  weekday: String,
  day_text: String,
  month_text: String,
  year_text: String,
  clock: String,
  now: time.Instant,
) -> Option(time.Duration) {
  case
    weekday_index(weekday),
    int.parse(day_text),
    month_number(month_text),
    int.parse(year_text),
    parse_clock(clock)
  {
    Some(expected_weekday),
      Ok(day),
      Some(month),
      Ok(year),
      Some(#(hour, minute, second))
      if year >= 1970 && year <= 9999
    -> {
      case time.date(year, month, day) {
        Error(_) -> None
        Ok(_) -> {
          let days =
            days_before_year(year) + days_before_month(year, month) + day - 1
          case { days + 4 } % 7 == expected_weekday {
            False -> None
            True -> {
              let target =
                { days * 86_400 + hour * 3600 + minute * 60 + second } * 1000
              let difference = target - time.unix_milliseconds(now)
              case difference < 0 {
                True -> duration(0)
                False -> duration(difference)
              }
            }
          }
        }
      }
    }
    _, _, _, _, _ -> None
  }
}

fn parse_clock(value: String) -> Option(#(Int, Int, Int)) {
  case string.split(value, ":") {
    [hour, minute, second] ->
      case int.parse(hour), int.parse(minute), int.parse(second) {
        Ok(hour), Ok(minute), Ok(second)
          if hour >= 0
          && hour <= 23
          && minute >= 0
          && minute <= 59
          && second >= 0
          && second <= 59
        -> Some(#(hour, minute, second))
        _, _, _ -> None
      }
    _ -> None
  }
}

fn weekday_index(value: String) -> Option(Int) {
  case value {
    "Sun," -> Some(0)
    "Mon," -> Some(1)
    "Tue," -> Some(2)
    "Wed," -> Some(3)
    "Thu," -> Some(4)
    "Fri," -> Some(5)
    "Sat," -> Some(6)
    _ -> None
  }
}

fn month_number(value: String) -> Option(Int) {
  case value {
    "Jan" -> Some(1)
    "Feb" -> Some(2)
    "Mar" -> Some(3)
    "Apr" -> Some(4)
    "May" -> Some(5)
    "Jun" -> Some(6)
    "Jul" -> Some(7)
    "Aug" -> Some(8)
    "Sep" -> Some(9)
    "Oct" -> Some(10)
    "Nov" -> Some(11)
    "Dec" -> Some(12)
    _ -> None
  }
}

fn days_before_year(year: Int) -> Int {
  let previous = year - 1
  365
  * { year - 1970 }
  + leap_years_through(previous)
  - leap_years_through(1969)
}

fn leap_years_through(year: Int) -> Int {
  year / 4 - year / 100 + year / 400
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
    12 -> 334
    _ -> 0
  }
  case month > 2 && is_leap_year(year) {
    True -> ordinary + 1
    False -> ordinary
  }
}

fn is_leap_year(year: Int) -> Bool {
  year % 400 == 0 || { year % 4 == 0 && year % 100 != 0 }
}

fn duration(milliseconds: Int) -> Option(time.Duration) {
  case time.duration(milliseconds) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}
