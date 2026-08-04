import finance_core/observation.{type MissingReason}
import finance_core/time.{type Instant}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type Datum(value) {
  Present(value: value)
  Missing(reason: MissingReason)
}

pub type Point(value) {
  Point(at: Instant, datum: Datum(value))
}

pub opaque type Series(value) {
  Series(points: List(Point(value)))
}

pub type MissingPolicy {
  Preserve
  Drop
  ForwardFill
  Reject
}

pub type SeriesError {
  DuplicateTimestamp(at: Instant)
  OutOfOrder(previous: Instant, current: Instant)
  MissingRejected(at: Instant, reason: MissingReason)
  InvalidWindowSize
  InvalidBucketOrder(previous: Instant, current: Instant)
}

/// Construct a series whose timestamps are strictly increasing.
///
/// Empty series are valid so pure filtering and inner joins stay total.
pub fn new(points: List(Point(value))) -> Result(Series(value), SeriesError) {
  case validate_order(points) {
    Ok(Nil) -> Ok(Series(points))
    Error(error) -> Error(error)
  }
}

pub fn from_present(
  points: List(#(Instant, value)),
) -> Result(Series(value), SeriesError) {
  points
  |> list.map(fn(pair) { Point(pair.0, Present(pair.1)) })
  |> new
}

pub fn to_list(series: Series(value)) -> List(Point(value)) {
  series.points
}

pub fn length(series: Series(value)) -> Int {
  list.length(series.points)
}

pub fn is_empty(series: Series(value)) -> Bool {
  list.is_empty(series.points)
}

pub fn map(
  series: Series(value),
  with transform: fn(value) -> mapped,
) -> Series(mapped) {
  Series(
    list.map(series.points, fn(point) {
      Point(point.at, case point.datum {
        Present(value) -> Present(transform(value))
        Missing(reason) -> Missing(reason)
      })
    }),
  )
}

pub fn indexed_map(
  series: Series(value),
  with transform: fn(Instant, Datum(value)) -> Datum(mapped),
) -> Series(mapped) {
  Series(
    list.map(series.points, fn(point) {
      Point(point.at, transform(point.at, point.datum))
    }),
  )
}

pub fn present_values(series: Series(value)) -> List(#(Instant, value)) {
  series.points
  |> list.filter_map(fn(point) {
    case point.datum {
      Present(value) -> Ok(#(point.at, value))
      Missing(_) -> Error(Nil)
    }
  })
}

pub fn missing_count(series: Series(value)) -> Int {
  series.points
  |> list.filter(fn(point) {
    case point.datum {
      Missing(_) -> True
      Present(_) -> False
    }
  })
  |> list.length
}

/// Apply one explicit missing-value policy.
///
/// `ForwardFill` preserves leading missing observations until a present value
/// exists; it never invents a value before the first observation.
pub fn resolve_missing(
  series: Series(value),
  policy: MissingPolicy,
) -> Result(Series(value), SeriesError) {
  case policy {
    Preserve -> Ok(series)
    Drop ->
      series.points
      |> list.filter(fn(point) {
        case point.datum {
          Present(_) -> True
          Missing(_) -> False
        }
      })
      |> Series
      |> Ok
    Reject ->
      case reject_missing(series.points) {
        Ok(Nil) -> Ok(series)
        Error(error) -> Error(error)
      }
    ForwardFill -> Ok(Series(forward_fill(series.points, None, [])))
  }
}

fn validate_order(points: List(Point(value))) -> Result(Nil, SeriesError) {
  case points {
    [] | [_] -> Ok(Nil)
    [previous, current, ..rest] -> {
      let previous_milliseconds = time.unix_milliseconds(previous.at)
      let current_milliseconds = time.unix_milliseconds(current.at)
      case
        current_milliseconds == previous_milliseconds,
        current_milliseconds < previous_milliseconds
      {
        True, _ -> Error(DuplicateTimestamp(current.at))
        _, True -> Error(OutOfOrder(previous.at, current.at))
        False, False -> validate_order([current, ..rest])
      }
    }
  }
}

fn reject_missing(points: List(Point(value))) -> Result(Nil, SeriesError) {
  case points {
    [] -> Ok(Nil)
    [Point(at, Missing(reason)), ..] -> Error(MissingRejected(at, reason))
    [_, ..rest] -> reject_missing(rest)
  }
}

fn forward_fill(
  points: List(Point(value)),
  previous: Option(value),
  filled_reversed: List(Point(value)),
) -> List(Point(value)) {
  case points {
    [] -> list.reverse(filled_reversed)
    [Point(_at, Present(value)) as point, ..rest] ->
      forward_fill(rest, Some(value), [point, ..filled_reversed])
    [Point(at, Missing(reason)), ..rest] -> {
      let point = case previous {
        Some(value) -> Point(at, Present(value))
        None -> Point(at, Missing(reason))
      }
      forward_fill(rest, previous, [point, ..filled_reversed])
    }
  }
}
