import gleam/int
import gleam/string

/// Immutable domain state. Pi callbacks store the latest value in a small
/// effect-shell cell; every transition in this module remains pure.
pub type State {
  State(
    active: Bool,
    value: Int,
    start_reason: String,
    shutdown_reason: String,
    cleanup_count: Int,
    last_event: String,
    error: String,
  )
}

pub type IncrementError {
  Inactive
}

pub fn initial() -> State {
  State(
    active: False,
    value: 0,
    start_reason: "none",
    shutdown_reason: "none",
    cleanup_count: 0,
    last_event: "none",
    error: "none",
  )
}

pub fn restore(state: State, value: Int, reason: String) -> State {
  State(
    ..state,
    active: True,
    value: value,
    start_reason: reason,
    shutdown_reason: "none",
    last_event: "session_start:" <> reason,
    error: "none",
  )
}

pub fn invalidate(state: State, reason: String) -> State {
  State(..state, active: False, error: reason, last_event: "restore_error")
}

pub fn observe(state: State, event: String) -> State {
  State(..state, last_event: event)
}

pub fn increment(state: State) -> Result(#(State, Int), IncrementError) {
  case state.active {
    False -> Error(Inactive)
    True -> {
      let value = state.value + 1
      Ok(#(
        State(..state, value: value, last_event: "counter_incremented"),
        value,
      ))
    }
  }
}

pub fn cleanup(state: State, reason: String) -> State {
  let cleanup_count = case state.active {
    True -> state.cleanup_count + 1
    False -> state.cleanup_count
  }
  State(
    ..state,
    active: False,
    cleanup_count: cleanup_count,
    shutdown_reason: reason,
    last_event: "session_shutdown:" <> reason,
  )
}

pub fn describe(state: State) -> String {
  [
    "active=" <> bool_name(state.active),
    "value=" <> int.to_string(state.value),
    "start=" <> state.start_reason,
    "shutdown=" <> state.shutdown_reason,
    "cleanups=" <> int.to_string(state.cleanup_count),
    "last=" <> state.last_event,
    "error=" <> state.error,
  ]
  |> string.join(" ")
}

fn bool_name(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
