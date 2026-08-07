import finance_core/time.{type Instant}
import finance_provenance/identity.{type Sha256}
import finance_replay/event.{type Event}
import finance_replay/fold.{type Effect, type State}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type Budget {
  Budget(
    max_events: Int,
    max_bytes: Int,
    max_wall_time_milliseconds: Int,
    max_sessions: Int,
  )
}

pub type ScriptItem {
  ScriptItem(
    event: Event,
    encoded_bytes: Int,
    elapsed_milliseconds: Int,
    session_increment: Int,
  )
}

pub type Cancellation {
  Continue
  CancelBefore(replay_clock: Int, cancelled_at: Instant, cancelled_by: String)
}

pub type Stop {
  InputExhausted
  BudgetTruncated(reason: String, continuation_replay_clock: Int)
  Cancelled(
    cancelled_at: Instant,
    cancelled_by: String,
    continuation_replay_clock: Int,
  )
}

pub opaque type RunResult {
  RunResult(
    state: State,
    stop: Stop,
    processed_events: Int,
    processed_bytes: Int,
    elapsed_milliseconds: Int,
    processed_sessions: Int,
    omitted_events: Int,
    effects: List(Effect),
  )
}

pub type ScriptError {
  InvalidBudget(field: String)
  InvalidScriptCost(event_id: String, field: String)
  FoldFailure(fold.FoldError)
}

pub fn run(
  run_id: String,
  run_definition_hash: Sha256,
  script: List(ScriptItem),
  budget: Budget,
  cancellation: Cancellation,
) -> Result(RunResult, ScriptError) {
  use _ <- result.try(validate_budget(budget))
  use _ <- result.try(validate_script(script))
  run_loop(
    script,
    fold.empty(run_id, run_definition_hash),
    budget,
    cancellation,
    0,
    0,
    0,
    0,
    [],
  )
}

fn run_loop(
  remaining: List(ScriptItem),
  state: State,
  budget: Budget,
  cancellation: Cancellation,
  processed_events: Int,
  processed_bytes: Int,
  elapsed_milliseconds: Int,
  processed_sessions: Int,
  reversed_effects: List(Effect),
) -> Result(RunResult, ScriptError) {
  case remaining {
    [] ->
      Ok(RunResult(
        state,
        InputExhausted,
        processed_events,
        processed_bytes,
        elapsed_milliseconds,
        processed_sessions,
        0,
        list.reverse(reversed_effects),
      ))
    [ScriptItem(next_event, bytes, elapsed, sessions), ..rest] ->
      case cancellation_before(cancellation, next_event) {
        Some(stop) ->
          Ok(RunResult(
            state,
            stop,
            processed_events,
            processed_bytes,
            elapsed_milliseconds,
            processed_sessions,
            list.length(remaining),
            list.reverse(reversed_effects),
          ))
        None -> {
          let Budget(max_events, max_bytes, max_wall, max_sessions) = budget
          let budget_stop = case
            processed_events + 1 > max_events,
            processed_bytes + bytes > max_bytes,
            elapsed_milliseconds + elapsed > max_wall,
            processed_sessions + sessions > max_sessions
          {
            True, _, _, _ -> Some("max_events")
            _, True, _, _ -> Some("max_bytes")
            _, _, True, _ -> Some("max_wall_time")
            _, _, _, True -> Some("max_sessions")
            False, False, False, False -> None
          }
          case budget_stop {
            Some(reason) ->
              Ok(RunResult(
                state,
                BudgetTruncated(reason, event.replay_clock(next_event)),
                processed_events,
                processed_bytes,
                elapsed_milliseconds,
                processed_sessions,
                list.length(remaining),
                list.reverse(reversed_effects),
              ))
            None ->
              case fold.append(state, next_event) {
                Error(error) -> Error(FoldFailure(error))
                Ok(#(next_state, _, effects)) ->
                  run_loop(
                    rest,
                    next_state,
                    budget,
                    cancellation,
                    processed_events + 1,
                    processed_bytes + bytes,
                    elapsed_milliseconds + elapsed,
                    processed_sessions + sessions,
                    list.append(list.reverse(effects), reversed_effects),
                  )
              }
          }
        }
      }
  }
}

fn cancellation_before(value: Cancellation, next_event: Event) -> Option(Stop) {
  case value {
    Continue -> None
    CancelBefore(replay_clock, at, by) ->
      case event.replay_clock(next_event) >= replay_clock {
        True -> Some(Cancelled(at, by, event.replay_clock(next_event)))
        False -> None
      }
  }
}

fn validate_budget(value: Budget) -> Result(Nil, ScriptError) {
  let Budget(events, bytes, wall_time, sessions) = value
  case events <= 0, bytes <= 0, wall_time <= 0, sessions <= 0 {
    True, _, _, _ -> Error(InvalidBudget("max_events"))
    _, True, _, _ -> Error(InvalidBudget("max_bytes"))
    _, _, True, _ -> Error(InvalidBudget("max_wall_time_milliseconds"))
    _, _, _, True -> Error(InvalidBudget("max_sessions"))
    False, False, False, False -> Ok(Nil)
  }
}

fn validate_script(values: List(ScriptItem)) -> Result(Nil, ScriptError) {
  case values {
    [] -> Ok(Nil)
    [ScriptItem(value, bytes, elapsed, sessions), ..rest] ->
      case bytes < 0, elapsed < 0, sessions < 0 {
        True, _, _ ->
          Error(InvalidScriptCost(event.event_id(value), "encoded_bytes"))
        _, True, _ ->
          Error(InvalidScriptCost(event.event_id(value), "elapsed_milliseconds"))
        _, _, True ->
          Error(InvalidScriptCost(event.event_id(value), "session_increment"))
        False, False, False -> validate_script(rest)
      }
  }
}

pub fn state(value: RunResult) -> State {
  value.state
}

pub fn stop(value: RunResult) -> Stop {
  value.stop
}

pub fn processed_events(value: RunResult) -> Int {
  value.processed_events
}

pub fn omitted_events(value: RunResult) -> Int {
  value.omitted_events
}
