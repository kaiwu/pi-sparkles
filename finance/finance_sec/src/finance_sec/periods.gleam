import finance_calendar/date
import finance_core/time.{type Date}
import finance_sec/xbrl.{type Fact}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Class {
  Instant
  Quarter
  HalfYearToDate
  NineMonthToDate
  Annual
  OtherDuration(days: Int)
}

pub type Classified {
  Classified(
    class: Class,
    start: Option(String),
    end: String,
    days: Option(Int),
  )
}

pub opaque type Target {
  Target(class: Class, end: String)
}

pub type PeriodError {
  InvalidStart
  InvalidEnd
  DurationTargetRequired
  ConcreteTargetRequired
}

pub fn target(class: Class, end: String) -> Result(Target, PeriodError) {
  case class, parse_date(end) {
    OtherDuration(_), _ -> Error(ConcreteTargetRequired)
    _, Error(_) -> Error(InvalidEnd)
    _, Ok(_) -> Ok(Target(class, end))
  }
}

pub fn target_class(value: Target) -> Class {
  let Target(class, _) = value
  class
}

pub fn target_end(value: Target) -> String {
  let Target(_, end) = value
  end
}

pub fn classify(fact: Fact) -> Result(Classified, PeriodError) {
  case fact.start {
    None ->
      case parse_date(fact.end) {
        Error(_) -> Error(InvalidEnd)
        Ok(_) -> Ok(Classified(Instant, None, fact.end, None))
      }
    Some(start) -> classify_range(start, fact.end)
  }
}

pub fn classify_range(
  start: String,
  end: String,
) -> Result(Classified, PeriodError) {
  use end_date <- result.try(
    parse_date(end) |> result.map_error(fn(_) { InvalidEnd }),
  )
  use start_date <- result.try(
    parse_date(start) |> result.map_error(fn(_) { InvalidStart }),
  )
  let days = date.days_between(start_date, end_date) + 1
  case days > 0 {
    False -> Error(InvalidStart)
    True -> Ok(Classified(duration_class(days), Some(start), end, Some(days)))
  }
}

pub fn matches(target: Target, fact: Fact) -> Result(Bool, PeriodError) {
  let Target(expected_class, expected_end) = target
  use classified <- result.try(classify(fact))
  Ok(
    classified.end == expected_end
    && same_class(expected_class, classified.class),
  )
}

pub fn class_name(value: Class) -> String {
  case value {
    Instant -> "instant"
    Quarter -> "quarter"
    HalfYearToDate -> "half_year_ytd"
    NineMonthToDate -> "nine_month_ytd"
    Annual -> "annual"
    OtherDuration(_) -> "other_duration"
  }
}

pub fn day_after(value: String) -> Result(String, PeriodError) {
  use parsed <- result.try(
    parse_date(value) |> result.map_error(fn(_) { InvalidEnd }),
  )
  case date.add_days(parsed, 1) {
    Error(_) -> Error(InvalidEnd)
    Ok(next) -> Ok(format_date(next))
  }
}

fn duration_class(days: Int) -> Class {
  case Nil {
    _ if days >= 61 && days <= 121 -> Quarter
    _ if days >= 152 && days <= 212 -> HalfYearToDate
    _ if days >= 243 && days <= 303 -> NineMonthToDate
    _ if days >= 335 && days <= 395 -> Annual
    _ -> OtherDuration(days)
  }
}

fn same_class(expected: Class, actual: Class) -> Bool {
  case expected, actual {
    Instant, Instant -> True
    Quarter, Quarter -> True
    HalfYearToDate, HalfYearToDate -> True
    NineMonthToDate, NineMonthToDate -> True
    Annual, Annual -> True
    OtherDuration(left), OtherDuration(right) -> left == right
    _, _ -> False
  }
}

fn parse_date(value: String) -> Result(Date, Nil) {
  case string.split(value, "-") {
    [year, month, day] ->
      case int.parse(year), int.parse(month), int.parse(day) {
        Ok(year_number), Ok(month_number), Ok(day_number) ->
          case
            string.length(year) == 4,
            string.length(month) == 2,
            string.length(day) == 2,
            time.date(year_number, month_number, day_number)
          {
            True, True, True, Ok(date) -> Ok(date)
            _, _, _, _ -> Error(Nil)
          }
        _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn format_date(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  pad(year, 4) <> "-" <> pad(month, 2) <> "-" <> pad(day, 2)
}

fn pad(value: Int, width: Int) -> String {
  let raw = int.to_string(value)
  string.repeat("0", width - string.length(raw)) <> raw
}
