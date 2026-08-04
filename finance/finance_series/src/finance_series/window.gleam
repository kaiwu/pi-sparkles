import finance_core/time.{type Instant}
import finance_series/series.{type Datum, type Series, type SeriesError}
import gleam/list

pub type WindowMode {
  FullOnly
  IncludePartial
}

pub type Window(value) {
  Window(
    starts_at: Instant,
    ends_at: Instant,
    points: List(series.Point(value)),
  )
}

pub fn windows(
  series series_value: Series(value),
  size size: Int,
  mode mode: WindowMode,
) -> Result(List(Window(value)), SeriesError) {
  case size > 0 {
    False -> Error(series.InvalidWindowSize)
    True -> Ok(build_windows(series.to_list(series_value), size, mode, 1, []))
  }
}

/// Transform each window into a datum at the window end timestamp.
///
/// The transform is pure and may return a missing datum. A fallible transform
/// can use `Result` as its output value and be sequenced by its caller.
pub fn rolling(
  series series_value: Series(value),
  size size: Int,
  mode mode: WindowMode,
  with transform: fn(Window(value)) -> Datum(mapped),
) -> Result(Series(mapped), SeriesError) {
  case windows(series_value, size, mode) {
    Error(error) -> Error(error)
    Ok(windows) ->
      windows
      |> list.map(fn(window) { series.Point(window.ends_at, transform(window)) })
      |> series.new
  }
}

fn build_windows(
  points: List(series.Point(value)),
  size: Int,
  mode: WindowMode,
  ending_position: Int,
  windows_reversed: List(Window(value)),
) -> List(Window(value)) {
  case ending_position > list.length(points) {
    True -> list.reverse(windows_reversed)
    False -> {
      let window_size = case mode, ending_position < size {
        IncludePartial, True -> ending_position
        _, _ -> size
      }
      case mode == FullOnly && ending_position < size {
        True ->
          build_windows(
            points,
            size,
            mode,
            ending_position + 1,
            windows_reversed,
          )
        False -> {
          let selected =
            points
            |> list.drop(ending_position - window_size)
            |> list.take(window_size)
          let assert [first, ..] = selected
          let assert Ok(last) = list.last(selected)
          build_windows(points, size, mode, ending_position + 1, [
            Window(first.at, last.at, selected),
            ..windows_reversed
          ])
        }
      }
    }
  }
}
