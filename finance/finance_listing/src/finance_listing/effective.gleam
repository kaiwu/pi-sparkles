import finance_core/time.{type Date}
import gleam/option.{type Option, None, Some}

/// Inclusive effective-date interval. `None` means no declared end date.
pub opaque type Interval {
  Interval(start: Date, end: Option(Date))
}

pub type IntervalError {
  EndBeforeStart
}

pub fn new(
  start start: Date,
  end end: Option(Date),
) -> Result(Interval, IntervalError) {
  case end {
    Some(end_date) ->
      case date_number(end_date) < date_number(start) {
        True -> Error(EndBeforeStart)
        False -> Ok(Interval(start, end))
      }
    None -> Ok(Interval(start, end))
  }
}

pub fn start(value: Interval) -> Date {
  value.start
}

pub fn end(value: Interval) -> Option(Date) {
  value.end
}

pub fn contains(value: Interval, date: Date) -> Bool {
  let candidate = date_number(date)
  candidate >= date_number(value.start)
  && case value.end {
    None -> True
    Some(end) -> candidate <= date_number(end)
  }
}

fn date_number(value: Date) -> Int {
  let #(year, month, day) = time.date_parts(value)
  year * 10_000 + month * 100 + day
}
