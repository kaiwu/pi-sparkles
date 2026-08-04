import gleam/list
import gleam/option.{type Option, None, Some}

pub opaque type Queue(value) {
  Queue(capacity: Int, waiting: List(value))
}

pub type QueueError {
  NonPositiveCapacity
  Full
}

pub fn new(capacity capacity: Int) -> Result(Queue(value), QueueError) {
  case capacity > 0 {
    True -> Ok(Queue(capacity, []))
    False -> Error(NonPositiveCapacity)
  }
}

pub fn enqueue(
  queue: Queue(value),
  value: value,
) -> Result(Queue(value), QueueError) {
  let Queue(capacity, waiting) = queue
  case list.length(waiting) < capacity {
    True -> Ok(Queue(capacity, [value, ..waiting]))
    False -> Error(Full)
  }
}

pub fn dequeue(queue: Queue(value)) -> #(Queue(value), Option(value)) {
  let Queue(capacity, waiting) = queue
  case list.reverse(waiting) {
    [] -> #(queue, None)
    [next, ..rest] -> #(Queue(capacity, list.reverse(rest)), Some(next))
  }
}

/// Remove the earliest queued value matching `predicate` while preserving the
/// order of every other value.
pub fn take_first(
  queue: Queue(value),
  predicate: fn(value) -> Bool,
) -> #(Queue(value), Option(value)) {
  let Queue(capacity, waiting) = queue
  let #(remaining, taken) =
    waiting
    |> list.reverse
    |> take_from_front(predicate, [])
  #(Queue(capacity, list.reverse(remaining)), taken)
}

pub fn to_list(queue: Queue(value)) -> List(value) {
  let Queue(_, waiting) = queue
  list.reverse(waiting)
}

pub fn size(queue: Queue(value)) -> Int {
  let Queue(_, waiting) = queue
  list.length(waiting)
}

pub fn capacity(queue: Queue(value)) -> Int {
  let Queue(capacity, _) = queue
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
