import gleam/string

pub opaque type Instant {
  Instant(unix_milliseconds: Int)
}

pub opaque type Duration {
  Duration(milliseconds: Int)
}

pub opaque type Date {
  Date(year: Int, month: Int, day: Int)
}

pub opaque type TimeOfDay {
  TimeOfDay(minutes_after_midnight: Int)
}

pub opaque type Timezone {
  Timezone(name: String)
}

pub type TimeError {
  InstantOutOfRange
  NegativeDuration
  DurationOutOfRange
  InvalidDate
  InvalidHour
  InvalidMinute
  InvalidTimezone
}

const maximum_safe_instant = 8_640_000_000_000_000

pub fn instant(unix_milliseconds: Int) -> Result(Instant, TimeError) {
  case
    unix_milliseconds < 0 - maximum_safe_instant
    || unix_milliseconds > maximum_safe_instant
  {
    True -> Error(InstantOutOfRange)
    False -> Ok(Instant(unix_milliseconds))
  }
}

pub fn unix_milliseconds(value: Instant) -> Int {
  let Instant(milliseconds) = value
  milliseconds
}

pub fn duration(milliseconds: Int) -> Result(Duration, TimeError) {
  case milliseconds < 0, milliseconds > maximum_safe_instant {
    True, _ -> Error(NegativeDuration)
    _, True -> Error(DurationOutOfRange)
    False, False -> Ok(Duration(milliseconds))
  }
}

pub fn duration_milliseconds(value: Duration) -> Int {
  let Duration(milliseconds) = value
  milliseconds
}

pub fn date(year: Int, month: Int, day: Int) -> Result(Date, TimeError) {
  case
    year >= 1
    && month >= 1
    && month <= 12
    && day >= 1
    && day <= days_in_month(year, month)
  {
    True -> Ok(Date(year, month, day))
    False -> Error(InvalidDate)
  }
}

pub fn date_parts(value: Date) -> #(Int, Int, Int) {
  let Date(year, month, day) = value
  #(year, month, day)
}

pub fn time_of_day(hour: Int, minute: Int) -> Result(TimeOfDay, TimeError) {
  case hour >= 0 && hour <= 23, minute >= 0 && minute <= 59 {
    False, _ -> Error(InvalidHour)
    _, False -> Error(InvalidMinute)
    True, True -> Ok(TimeOfDay(hour * 60 + minute))
  }
}

pub fn time_of_day_parts(value: TimeOfDay) -> #(Int, Int) {
  let TimeOfDay(minutes) = value
  #(minutes / 60, minutes % 60)
}

pub fn minutes_after_midnight(value: TimeOfDay) -> Int {
  let TimeOfDay(minutes) = value
  minutes
}

pub fn timezone(name: String) -> Result(Timezone, TimeError) {
  case
    name != ""
    && string.trim(name) == name
    && { name == "UTC" || string.contains(name, "/") }
    && !string.contains(name, " ")
  {
    True -> Ok(Timezone(name))
    False -> Error(InvalidTimezone)
  }
}

pub fn timezone_name(value: Timezone) -> String {
  let Timezone(name) = value
  name
}

fn days_in_month(year: Int, month: Int) -> Int {
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

fn is_leap_year(year: Int) -> Bool {
  year % 400 == 0 || { year % 4 == 0 && year % 100 != 0 }
}
