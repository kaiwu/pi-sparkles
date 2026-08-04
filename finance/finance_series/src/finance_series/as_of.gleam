import finance_core/time.{type Duration, type Instant}
import finance_series/series.{type Datum, type Series}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type Match(left, right) {
  Match(
    at: Instant,
    left: Datum(left),
    right: Option(Datum(right)),
    matched_at: Option(Instant),
  )
}

/// Left as-of join using the most recent right timestamp at or before each
/// left timestamp. A candidate older than the explicit maximum age is absent.
pub fn join(
  left: Series(left),
  right: Series(right),
  maximum_staleness maximum_staleness: Duration,
) -> List(Match(left, right)) {
  build(
    series.to_list(left),
    series.to_list(right),
    None,
    time.duration_milliseconds(maximum_staleness),
    [],
  )
}

fn build(
  left: List(series.Point(left)),
  right: List(series.Point(right)),
  latest: Option(series.Point(right)),
  maximum_staleness: Int,
  reversed: List(Match(left, right)),
) -> List(Match(left, right)) {
  case left {
    [] -> list.reverse(reversed)
    [left_point, ..rest] -> {
      let #(remaining_right, candidate) = advance(right, latest, left_point.at)
      let #(right_datum, matched_at) =
        accepted(candidate, left_point.at, maximum_staleness)
      build(rest, remaining_right, candidate, maximum_staleness, [
        Match(left_point.at, left_point.datum, right_datum, matched_at),
        ..reversed
      ])
    }
  }
}

fn advance(
  remaining: List(series.Point(value)),
  latest: Option(series.Point(value)),
  at: Instant,
) -> #(List(series.Point(value)), Option(series.Point(value))) {
  case remaining {
    [point, ..rest] ->
      case time.unix_milliseconds(point.at) <= time.unix_milliseconds(at) {
        True -> advance(rest, Some(point), at)
        False -> #(remaining, latest)
      }
    _ -> #(remaining, latest)
  }
}

fn accepted(
  candidate: Option(series.Point(value)),
  at: Instant,
  maximum_staleness: Int,
) -> #(Option(Datum(value)), Option(Instant)) {
  case candidate {
    None -> #(None, None)
    Some(point) -> {
      let age = time.unix_milliseconds(at) - time.unix_milliseconds(point.at)
      case age <= maximum_staleness {
        True -> #(Some(point.datum), Some(point.at))
        False -> #(None, None)
      }
    }
  }
}
