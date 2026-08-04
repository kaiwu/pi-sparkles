import finance_core/time.{type Instant}
import finance_series/series.{type Datum, type Series}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type Join {
  Inner
  Left
  Right
  Full
}

pub type Aligned(left, right) {
  Aligned(at: Instant, left: Option(Datum(left)), right: Option(Datum(right)))
}

/// Merge two validated timelines without changing either input.
pub fn align(
  left: Series(left),
  right: Series(right),
  join join_policy: Join,
) -> List(Aligned(left, right)) {
  merge(series.to_list(left), series.to_list(right), join_policy, [])
}

fn merge(
  left: List(series.Point(left)),
  right: List(series.Point(right)),
  join_policy: Join,
  aligned_reversed: List(Aligned(left, right)),
) -> List(Aligned(left, right)) {
  case left, right {
    [], [] -> list.reverse(aligned_reversed)
    [left, ..left_rest], [] ->
      case includes_left(join_policy) {
        True ->
          merge(left_rest, [], join_policy, [
            Aligned(left.at, Some(left.datum), None),
            ..aligned_reversed
          ])
        False -> list.reverse(aligned_reversed)
      }
    [], [right, ..right_rest] ->
      case includes_right(join_policy) {
        True ->
          merge([], right_rest, join_policy, [
            Aligned(right.at, None, Some(right.datum)),
            ..aligned_reversed
          ])
        False -> list.reverse(aligned_reversed)
      }
    [left, ..left_rest], [right, ..right_rest] -> {
      let left_at = time.unix_milliseconds(left.at)
      let right_at = time.unix_milliseconds(right.at)
      case left_at == right_at, left_at < right_at {
        True, _ ->
          merge(left_rest, right_rest, join_policy, [
            Aligned(left.at, Some(left.datum), Some(right.datum)),
            ..aligned_reversed
          ])
        _, True ->
          case includes_left(join_policy) {
            True ->
              merge(left_rest, [right, ..right_rest], join_policy, [
                Aligned(left.at, Some(left.datum), None),
                ..aligned_reversed
              ])
            False ->
              merge(
                left_rest,
                [right, ..right_rest],
                join_policy,
                aligned_reversed,
              )
          }
        False, False ->
          case includes_right(join_policy) {
            True ->
              merge([left, ..left_rest], right_rest, join_policy, [
                Aligned(right.at, None, Some(right.datum)),
                ..aligned_reversed
              ])
            False ->
              merge(
                [left, ..left_rest],
                right_rest,
                join_policy,
                aligned_reversed,
              )
          }
      }
    }
  }
}

fn includes_left(join_policy: Join) -> Bool {
  join_policy == Left || join_policy == Full
}

fn includes_right(join_policy: Join) -> Bool {
  join_policy == Right || join_policy == Full
}
