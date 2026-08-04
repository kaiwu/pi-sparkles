import finance_core/time.{type Instant}
import finance_series/series.{type Datum, type Series, type SeriesError}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Group adjacent points by a caller-supplied bucket timestamp, then aggregate
/// each group. Trading calendars and timezone rules stay injected.
pub fn resample(
  series series_value: Series(value),
  bucket_start bucket_start: fn(Instant) -> Instant,
  with aggregate: fn(List(series.Point(value))) -> Datum(mapped),
) -> Result(Series(mapped), SeriesError) {
  case group(series.to_list(series_value), bucket_start, None, [], []) {
    Error(error) -> Error(error)
    Ok(groups) ->
      groups
      |> list.map(fn(group) {
        let #(at, points) = group
        series.Point(at, aggregate(points))
      })
      |> series.new
  }
}

fn group(
  points: List(series.Point(value)),
  bucket_start: fn(Instant) -> Instant,
  current_bucket: Option(Instant),
  current_reversed: List(series.Point(value)),
  groups_reversed: List(#(Instant, List(series.Point(value)))),
) -> Result(List(#(Instant, List(series.Point(value)))), SeriesError) {
  case points, current_bucket {
    [], None -> Ok(list.reverse(groups_reversed))
    [], Some(bucket) ->
      Ok(
        list.reverse([
          #(bucket, list.reverse(current_reversed)),
          ..groups_reversed
        ]),
      )
    [point, ..rest], None ->
      group(
        rest,
        bucket_start,
        Some(bucket_start(point.at)),
        [point],
        groups_reversed,
      )
    [point, ..rest], Some(bucket) -> {
      let next_bucket = bucket_start(point.at)
      let current_milliseconds = time.unix_milliseconds(bucket)
      let next_milliseconds = time.unix_milliseconds(next_bucket)
      case
        next_milliseconds == current_milliseconds,
        next_milliseconds < current_milliseconds
      {
        True, _ ->
          group(
            rest,
            bucket_start,
            Some(bucket),
            [point, ..current_reversed],
            groups_reversed,
          )
        _, True -> Error(series.InvalidBucketOrder(bucket, next_bucket))
        False, False ->
          group(rest, bucket_start, Some(next_bucket), [point], [
            #(bucket, list.reverse(current_reversed)),
            ..groups_reversed
          ])
      }
    }
  }
}
