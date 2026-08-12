import gleam/list
import gleam/option.{type Option, None, Some}

pub opaque type Queue(value) {
  Queue(capacity: Int, count: Int, front: List(value), back: List(value))
}

pub type QueueError {
  NonPositiveCapacity
  Full
}

pub fn new(capacity capacity: Int) -> Result(Queue(value), QueueError) {
  case capacity > 0 {
    True -> Ok(Queue(capacity, 0, [], []))
    False -> Error(NonPositiveCapacity)
  }
}

pub fn enqueue(
  queue: Queue(value),
  value: value,
) -> Result(Queue(value), QueueError) {
  let Queue(capacity, count, front, back) = queue
  case count < capacity {
    True -> Ok(Queue(capacity, count + 1, front, [value, ..back]))
    False -> Error(Full)
  }
}

pub fn dequeue(queue: Queue(value)) -> #(Queue(value), Option(value)) {
  let Queue(capacity, count, front, back) = queue
  case front {
    [next, ..rest] -> #(Queue(capacity, count - 1, rest, back), Some(next))
    [] ->
      case list.reverse(back) {
        [] -> #(queue, None)
        [next, ..rest] -> #(Queue(capacity, count - 1, rest, []), Some(next))
      }
  }
}

/// Remove the earliest queued value matching `predicate` while preserving the
/// order of every other value.
pub fn take_first(
  queue: Queue(value),
  predicate: fn(value) -> Bool,
) -> #(Queue(value), Option(value)) {
  let Queue(capacity, count, _, _) = queue
  let #(remaining, taken) =
    queue
    |> to_list
    |> take_from_front(predicate, [])
  let next_count = case taken {
    Some(_) -> count - 1
    None -> count
  }
  #(Queue(capacity, next_count, remaining, []), taken)
}

pub fn to_list(queue: Queue(value)) -> List(value) {
  let Queue(_, _, front, back) = queue
  list.append(front, list.reverse(back))
}

pub fn size(queue: Queue(value)) -> Int {
  let Queue(_, count, _, _) = queue
  count
}

pub fn capacity(queue: Queue(value)) -> Int {
  let Queue(capacity, _, _, _) = queue
  capacity
}

pub fn is_empty(queue: Queue(value)) -> Bool {
  size(queue) == 0
}

fn take_from_front(
  remaining: List(value),
  predicate: fn(value) -> Bool,
  before_reversed: List(value),
) -> #(List(value), Option(value)) {
  case remaining {
    [] -> #(list.reverse(before_reversed), None)
    [candidate, ..rest] ->
      case predicate(candidate) {
        True -> #(
          list.append(list.reverse(before_reversed), rest),
          Some(candidate),
        )
        False ->
          take_from_front(rest, predicate, [candidate, ..before_reversed])
      }
  }
}
