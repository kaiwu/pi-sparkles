import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type Budgets {
  Budgets(
    maximum_events: Int,
    maximum_bytes: Int,
    maximum_queued_events: Int,
    maximum_reconnects: Int,
    maximum_session_milliseconds: Int,
    operation_timeout_milliseconds: Int,
    cleanup_timeout_milliseconds: Int,
  )
}

pub type Phase {
  Idle
  Subscribing
  Active
  RecoveringSubscription
  RecoveringBackfill
  Unsubscribing
  FailingCleanup(reason: String)
  Closed
  Failed(reason: String)
}

pub type RecoveryOutcome {
  OverlapProved
  UnrecoverableGap(reason: String)
  RecoveryUnavailable(reason: String)
}

pub type CleanupStatus {
  CleanupConfirmed
  CleanupUnconfirmed
  CleanupNotRequired
}

pub type StreamEvent {
  Start(now_unix_milliseconds: Int)
  SubscriptionAcknowledged(generation: Int, now_unix_milliseconds: Int)
  BatchReceived(
    generation: Int,
    event_count: Int,
    byte_count: Int,
    last_sequence: Option(String),
    now_unix_milliseconds: Int,
  )
  QueueConsumed(event_count: Int, now_unix_milliseconds: Int)
  Disconnected(generation: Int, reason: String, now_unix_milliseconds: Int)
  RecoveryCompleted(
    generation: Int,
    outcome: RecoveryOutcome,
    now_unix_milliseconds: Int,
  )
  StopRequested(now_unix_milliseconds: Int)
  UnsubscribeAcknowledged(generation: Int, now_unix_milliseconds: Int)
  ProviderFailed(generation: Int, reason: String, now_unix_milliseconds: Int)
  Tick(now_unix_milliseconds: Int)
}

pub type Effect {
  Subscribe(stream_key: String, generation: Int)
  RequestRecovery(
    stream_key: String,
    generation: Int,
    last_sequence: Option(String),
  )
  AcceptBatch(generation: Int, event_count: Int, byte_count: Int)
  Unsubscribe(stream_key: String, generation: Int)
  Complete(cleanup: CleanupStatus)
  ReportFailure(reason: String, cleanup: CleanupStatus)
}

pub opaque type State {
  State(
    stream_key: String,
    budgets: Budgets,
    phase: Phase,
    generation: Int,
    started_at_unix_milliseconds: Option(Int),
    phase_started_at_unix_milliseconds: Option(Int),
    last_transition_unix_milliseconds: Option(Int),
    total_events: Int,
    total_bytes: Int,
    queued_events: Int,
    queue_high_water: Int,
    reconnect_count: Int,
    stale_completion_count: Int,
    last_sequence: Option(String),
    cleanup_requested: Bool,
  )
}

pub opaque type Transition {
  Transition(state: State, effects: List(Effect))
}

pub type StreamError {
  InvalidField(field: String, reason: String)
  InvalidTransition(phase: String, event: String)
  NonmonotonicClock(previous: Int, received: Int)
}

const maximum_safe_unix_milliseconds = 9_007_199_254_740_991

pub fn budgets(
  maximum_events maximum_events: Int,
  maximum_bytes maximum_bytes: Int,
  maximum_queued_events maximum_queued_events: Int,
  maximum_reconnects maximum_reconnects: Int,
  maximum_session_milliseconds maximum_session_milliseconds: Int,
  operation_timeout_milliseconds operation_timeout_milliseconds: Int,
  cleanup_timeout_milliseconds cleanup_timeout_milliseconds: Int,
) -> Result(Budgets, StreamError) {
  use _ <- result.try(bounded_positive("maximumEvents", maximum_events, 10_000))
  use _ <- result.try(bounded_positive(
    "maximumBytes",
    maximum_bytes,
    10_000_000,
  ))
  use _ <- result.try(bounded_positive(
    "maximumQueuedEvents",
    maximum_queued_events,
    10_000,
  ))
  use _ <- result.try(case maximum_reconnects >= 0 && maximum_reconnects <= 3 {
    True -> Ok(Nil)
    False ->
      Error(InvalidField("maximumReconnects", "must be between zero and three"))
  })
  use _ <- result.try(bounded_positive(
    "maximumSessionMilliseconds",
    maximum_session_milliseconds,
    28_800_000,
  ))
  use _ <- result.try(bounded_positive(
    "operationTimeoutMilliseconds",
    operation_timeout_milliseconds,
    30_000,
  ))
  use _ <- result.try(bounded_positive(
    "cleanupTimeoutMilliseconds",
    cleanup_timeout_milliseconds,
    30_000,
  ))
  Ok(Budgets(
    maximum_events,
    maximum_bytes,
    maximum_queued_events,
    maximum_reconnects,
    maximum_session_milliseconds,
    operation_timeout_milliseconds,
    cleanup_timeout_milliseconds,
  ))
}

pub fn initial(
  stream_key: String,
  budgets: Budgets,
) -> Result(State, StreamError) {
  use _ <- result.try(valid_text("streamKey", stream_key, 1, 500))
  Ok(State(
    stream_key,
    budgets,
    Idle,
    0,
    None,
    None,
    None,
    0,
    0,
    0,
    0,
    0,
    0,
    None,
    False,
  ))
}

pub fn transition(
  state: State,
  event: StreamEvent,
) -> Result(Transition, StreamError) {
  let now = event_time(event)
  use _ <- result.try(valid_instant(now))
  use _ <- result.try(monotonic_time(state, now))
  case event {
    Start(_) -> start(state, now)
    SubscriptionAcknowledged(generation, _) ->
      subscription_acknowledged(state, generation, now)
    BatchReceived(generation, event_count, byte_count, last_sequence, _) ->
      batch_received(
        state,
        generation,
        event_count,
        byte_count,
        last_sequence,
        now,
      )
    QueueConsumed(event_count, _) -> queue_consumed(state, event_count, now)
    Disconnected(generation, reason, _) ->
      disconnected(state, generation, reason, now)
    RecoveryCompleted(generation, outcome, _) ->
      recovery_completed(state, generation, outcome, now)
    StopRequested(_) -> stop_requested(state, now)
    UnsubscribeAcknowledged(generation, _) ->
      unsubscribe_acknowledged(state, generation, now)
    ProviderFailed(generation, reason, _) ->
      provider_failed(state, generation, reason, now)
    Tick(_) -> tick(state, now)
  }
}

pub fn transition_state(value: Transition) -> State {
  value.state
}

pub fn transition_effects(value: Transition) -> List(Effect) {
  value.effects
}

pub fn phase(value: State) -> Phase {
  value.phase
}

pub fn generation(value: State) -> Int {
  value.generation
}

pub fn total_events(value: State) -> Int {
  value.total_events
}

pub fn total_bytes(value: State) -> Int {
  value.total_bytes
}

pub fn queued_events(value: State) -> Int {
  value.queued_events
}

pub fn queue_high_water(value: State) -> Int {
  value.queue_high_water
}

pub fn reconnect_count(value: State) -> Int {
  value.reconnect_count
}

pub fn stale_completion_count(value: State) -> Int {
  value.stale_completion_count
}

pub fn last_sequence(value: State) -> Option(String) {
  value.last_sequence
}

pub fn cleanup_requested(value: State) -> Bool {
  value.cleanup_requested
}

pub fn phase_name(value: Phase) -> String {
  case value {
    Idle -> "idle"
    Subscribing -> "subscribing"
    Active -> "active"
    RecoveringSubscription -> "recovering_subscription"
    RecoveringBackfill -> "recovering_backfill"
    Unsubscribing -> "unsubscribing"
    FailingCleanup(_) -> "failing_cleanup"
    Closed -> "closed"
    Failed(_) -> "failed"
  }
}

pub fn event_name(value: StreamEvent) -> String {
  case value {
    Start(_) -> "start"
    SubscriptionAcknowledged(_, _) -> "subscription_acknowledged"
    BatchReceived(_, _, _, _, _) -> "batch_received"
    QueueConsumed(_, _) -> "queue_consumed"
    Disconnected(_, _, _) -> "disconnected"
    RecoveryCompleted(_, _, _) -> "recovery_completed"
    StopRequested(_) -> "stop_requested"
    UnsubscribeAcknowledged(_, _) -> "unsubscribe_acknowledged"
    ProviderFailed(_, _, _) -> "provider_failed"
    Tick(_) -> "tick"
  }
}

pub fn error_message(value: StreamError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid transaction-tape stream field " <> field <> ": " <> reason
    InvalidTransition(phase, event) ->
      "Invalid transaction-tape stream transition " <> phase <> " + " <> event
    NonmonotonicClock(previous, received) ->
      "Transaction-tape stream clock moved backwards from "
      <> int.to_string(previous)
      <> " to "
      <> int.to_string(received)
  }
}

fn start(state: State, now: Int) -> Result(Transition, StreamError) {
  case state.phase {
    Idle -> {
      let next =
        State(
          ..state,
          phase: Subscribing,
          generation: 1,
          started_at_unix_milliseconds: Some(now),
          phase_started_at_unix_milliseconds: Some(now),
          last_transition_unix_milliseconds: Some(now),
        )
      Ok(Transition(next, [Subscribe(state.stream_key, 1)]))
    }
    _ -> invalid(state, Start(now))
  }
}

fn subscription_acknowledged(
  state: State,
  generation: Int,
  now: Int,
) -> Result(Transition, StreamError) {
  case stale(state, generation, now) {
    Some(value) -> Ok(Transition(value, []))
    None ->
      case state.phase {
        Subscribing -> Ok(Transition(update_phase(state, Active, now), []))
        RecoveringSubscription ->
          Ok(
            Transition(update_phase(state, RecoveringBackfill, now), [
              RequestRecovery(
                state.stream_key,
                state.generation,
                state.last_sequence,
              ),
            ]),
          )
        Active | Unsubscribing | FailingCleanup(_) | Closed | Failed(_) ->
          Ok(Transition(late_completion(state, now), []))
        _ -> invalid(state, SubscriptionAcknowledged(generation, now))
      }
  }
}

fn batch_received(
  state: State,
  generation: Int,
  event_count: Int,
  byte_count: Int,
  last_sequence: Option(String),
  now: Int,
) -> Result(Transition, StreamError) {
  case stale(state, generation, now) {
    Some(value) -> Ok(Transition(value, []))
    None ->
      case state.phase {
        Active -> {
          use _ <- result.try(case event_count > 0 {
            True -> Ok(Nil)
            False -> Error(InvalidField("batch.eventCount", "must be positive"))
          })
          use _ <- result.try(case byte_count >= 0 {
            True -> Ok(Nil)
            False ->
              Error(InvalidField("batch.byteCount", "must be non-negative"))
          })
          use _ <- result.try(valid_optional_sequence(last_sequence))
          let next_events = state.total_events + event_count
          let next_bytes = state.total_bytes + byte_count
          let next_queue = state.queued_events + event_count
          let reason = case
            next_events > state.budgets.maximum_events,
            next_bytes > state.budgets.maximum_bytes,
            next_queue > state.budgets.maximum_queued_events
          {
            True, _, _ -> "event_budget_exceeded"
            _, True, _ -> "byte_budget_exceeded"
            _, _, True -> "queue_budget_exceeded"
            False, False, False -> ""
          }
          case reason {
            "" -> {
              let retained_sequence = case last_sequence {
                Some(_) -> last_sequence
                None -> state.last_sequence
              }
              let next =
                State(
                  ..state,
                  total_events: next_events,
                  total_bytes: next_bytes,
                  queued_events: next_queue,
                  queue_high_water: int.max(state.queue_high_water, next_queue),
                  last_sequence: retained_sequence,
                  last_transition_unix_milliseconds: Some(now),
                )
              Ok(
                Transition(next, [
                  AcceptBatch(generation, event_count, byte_count),
                ]),
              )
            }
            reason -> begin_failure_cleanup(state, reason, now)
          }
        }
        Unsubscribing | FailingCleanup(_) | Closed | Failed(_) ->
          Ok(Transition(late_completion(state, now), []))
        _ ->
          invalid(
            state,
            BatchReceived(
              generation,
              event_count,
              byte_count,
              last_sequence,
              now,
            ),
          )
      }
  }
}

fn queue_consumed(
  state: State,
  event_count: Int,
  now: Int,
) -> Result(Transition, StreamError) {
  case state.phase, event_count >= 0 && event_count <= state.queued_events {
    Active, True ->
      Ok(
        Transition(
          State(
            ..state,
            queued_events: state.queued_events - event_count,
            last_transition_unix_milliseconds: Some(now),
          ),
          [],
        ),
      )
    Active, False ->
      Error(InvalidField(
        "queueConsumed.eventCount",
        "must be within the queued count",
      ))
    _, _ -> invalid(state, QueueConsumed(event_count, now))
  }
}

fn disconnected(
  state: State,
  generation: Int,
  reason: String,
  now: Int,
) -> Result(Transition, StreamError) {
  use _ <- result.try(valid_text("disconnect.reason", reason, 1, 500))
  case stale(state, generation, now) {
    Some(value) -> Ok(Transition(value, []))
    None ->
      case state.phase {
        Active ->
          case state.reconnect_count < state.budgets.maximum_reconnects {
            True -> {
              let next_generation = state.generation + 1
              let next =
                State(
                  ..state,
                  phase: RecoveringSubscription,
                  generation: next_generation,
                  reconnect_count: state.reconnect_count + 1,
                  phase_started_at_unix_milliseconds: Some(now),
                  last_transition_unix_milliseconds: Some(now),
                )
              Ok(
                Transition(next, [Subscribe(state.stream_key, next_generation)]),
              )
            }
            False -> {
              let failure = "reconnect_budget_exhausted:" <> reason
              let next =
                State(
                  ..state,
                  phase: Failed(failure),
                  phase_started_at_unix_milliseconds: Some(now),
                  last_transition_unix_milliseconds: Some(now),
                )
              Ok(Transition(next, [ReportFailure(failure, CleanupNotRequired)]))
            }
          }
        Unsubscribing | FailingCleanup(_) | Closed | Failed(_) ->
          Ok(Transition(late_completion(state, now), []))
        _ -> invalid(state, Disconnected(generation, reason, now))
      }
  }
}

fn recovery_completed(
  state: State,
  generation: Int,
  outcome: RecoveryOutcome,
  now: Int,
) -> Result(Transition, StreamError) {
  case stale(state, generation, now) {
    Some(value) -> Ok(Transition(value, []))
    None ->
      case state.phase, outcome {
        RecoveringBackfill, OverlapProved ->
          Ok(Transition(update_phase(state, Active, now), []))
        RecoveringBackfill, UnrecoverableGap(reason) -> {
          use _ <- result.try(valid_text("recovery.reason", reason, 1, 500))
          begin_failure_cleanup(state, "unrecoverable_gap:" <> reason, now)
        }
        RecoveringBackfill, RecoveryUnavailable(reason) -> {
          use _ <- result.try(valid_text("recovery.reason", reason, 1, 500))
          begin_failure_cleanup(state, "recovery_unavailable:" <> reason, now)
        }
        Active, _
        | Unsubscribing, _
        | FailingCleanup(_), _
        | Closed, _
        | Failed(_), _
        -> Ok(Transition(late_completion(state, now), []))
        _, _ -> invalid(state, RecoveryCompleted(generation, outcome, now))
      }
  }
}

fn stop_requested(state: State, now: Int) -> Result(Transition, StreamError) {
  case state.phase {
    Idle ->
      Ok(
        Transition(
          State(
            ..state,
            phase: Closed,
            phase_started_at_unix_milliseconds: Some(now),
            last_transition_unix_milliseconds: Some(now),
          ),
          [Complete(CleanupNotRequired)],
        ),
      )
    Subscribing | Active | RecoveringSubscription | RecoveringBackfill -> {
      let next =
        State(
          ..state,
          phase: Unsubscribing,
          phase_started_at_unix_milliseconds: Some(now),
          last_transition_unix_milliseconds: Some(now),
          cleanup_requested: True,
        )
      Ok(Transition(next, [Unsubscribe(state.stream_key, state.generation)]))
    }
    Unsubscribing | FailingCleanup(_) | Closed | Failed(_) ->
      Ok(
        Transition(
          State(..state, last_transition_unix_milliseconds: Some(now)),
          [],
        ),
      )
  }
}

fn unsubscribe_acknowledged(
  state: State,
  generation: Int,
  now: Int,
) -> Result(Transition, StreamError) {
  case stale(state, generation, now) {
    Some(value) -> Ok(Transition(value, []))
    None ->
      case state.phase {
        Unsubscribing -> {
          let next = update_phase(state, Closed, now)
          Ok(Transition(next, [Complete(CleanupConfirmed)]))
        }
        FailingCleanup(reason) -> {
          let next = update_phase(state, Failed(reason), now)
          Ok(Transition(next, [ReportFailure(reason, CleanupConfirmed)]))
        }
        Closed | Failed(_) -> Ok(Transition(late_completion(state, now), []))
        _ -> invalid(state, UnsubscribeAcknowledged(generation, now))
      }
  }
}

fn provider_failed(
  state: State,
  generation: Int,
  reason: String,
  now: Int,
) -> Result(Transition, StreamError) {
  use _ <- result.try(valid_text("providerFailure.reason", reason, 1, 500))
  case stale(state, generation, now) {
    Some(value) -> Ok(Transition(value, []))
    None ->
      case state.phase {
        Subscribing | Active | RecoveringSubscription | RecoveringBackfill ->
          begin_failure_cleanup(state, "provider_failure:" <> reason, now)
        Unsubscribing | FailingCleanup(_) | Closed | Failed(_) ->
          Ok(Transition(late_completion(state, now), []))
        _ -> invalid(state, ProviderFailed(generation, reason, now))
      }
  }
}

fn tick(state: State, now: Int) -> Result(Transition, StreamError) {
  let session_expired = case state.started_at_unix_milliseconds {
    Some(started) -> now - started > state.budgets.maximum_session_milliseconds
    None -> False
  }
  let phase_elapsed = case state.phase_started_at_unix_milliseconds {
    Some(started) -> now - started
    None -> 0
  }
  case state.phase, session_expired {
    Subscribing, True
    | Active, True
    | RecoveringSubscription, True
    | RecoveringBackfill, True
    -> begin_failure_cleanup(state, "session_budget_exceeded", now)
    Subscribing, False
      if phase_elapsed > state.budgets.operation_timeout_milliseconds
    -> begin_failure_cleanup(state, "subscribe_timeout", now)
    RecoveringSubscription, False
      if phase_elapsed > state.budgets.operation_timeout_milliseconds
    -> begin_failure_cleanup(state, "reconnect_timeout", now)
    RecoveringBackfill, False
      if phase_elapsed > state.budgets.operation_timeout_milliseconds
    -> begin_failure_cleanup(state, "recovery_timeout", now)
    Unsubscribing, _
      if phase_elapsed > state.budgets.cleanup_timeout_milliseconds
    -> {
      let next = update_phase(state, Closed, now)
      Ok(Transition(next, [Complete(CleanupUnconfirmed)]))
    }
    FailingCleanup(reason), _
      if phase_elapsed > state.budgets.cleanup_timeout_milliseconds
    -> {
      let next = update_phase(state, Failed(reason), now)
      Ok(Transition(next, [ReportFailure(reason, CleanupUnconfirmed)]))
    }
    _, _ ->
      Ok(
        Transition(
          State(..state, last_transition_unix_milliseconds: Some(now)),
          [],
        ),
      )
  }
}

fn begin_failure_cleanup(
  state: State,
  reason: String,
  now: Int,
) -> Result(Transition, StreamError) {
  let next =
    State(
      ..state,
      phase: FailingCleanup(reason),
      phase_started_at_unix_milliseconds: Some(now),
      last_transition_unix_milliseconds: Some(now),
      cleanup_requested: True,
    )
  Ok(Transition(next, [Unsubscribe(state.stream_key, state.generation)]))
}

fn stale(state: State, generation: Int, now: Int) -> Option(State) {
  case generation == state.generation {
    True -> None
    False ->
      Some(
        State(
          ..state,
          stale_completion_count: state.stale_completion_count + 1,
          last_transition_unix_milliseconds: Some(now),
        ),
      )
  }
}

fn late_completion(state: State, now: Int) -> State {
  State(
    ..state,
    stale_completion_count: state.stale_completion_count + 1,
    last_transition_unix_milliseconds: Some(now),
  )
}

fn update_phase(state: State, phase: Phase, now: Int) -> State {
  State(
    ..state,
    phase: phase,
    phase_started_at_unix_milliseconds: Some(now),
    last_transition_unix_milliseconds: Some(now),
  )
}

fn invalid(state: State, event: StreamEvent) -> Result(value, StreamError) {
  Error(InvalidTransition(phase_name(state.phase), event_name(event)))
}

fn event_time(value: StreamEvent) -> Int {
  case value {
    Start(now)
    | SubscriptionAcknowledged(_, now)
    | BatchReceived(_, _, _, _, now)
    | QueueConsumed(_, now)
    | Disconnected(_, _, now)
    | RecoveryCompleted(_, _, now)
    | StopRequested(now)
    | UnsubscribeAcknowledged(_, now)
    | ProviderFailed(_, _, now)
    | Tick(now) -> now
  }
}

fn monotonic_time(state: State, now: Int) -> Result(Nil, StreamError) {
  case state.last_transition_unix_milliseconds {
    Some(previous) if now < previous -> Error(NonmonotonicClock(previous, now))
    _ -> Ok(Nil)
  }
}

fn valid_instant(value: Int) -> Result(Nil, StreamError) {
  case value >= 0 && value <= maximum_safe_unix_milliseconds {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "nowUnixMilliseconds",
        "must be a non-negative JavaScript-safe integer",
      ))
  }
}

fn valid_optional_sequence(value: Option(String)) -> Result(Nil, StreamError) {
  case value {
    None -> Ok(Nil)
    Some(value) -> valid_text("batch.lastSequence", value, 1, 500)
  }
}

fn bounded_positive(
  field: String,
  value: Int,
  maximum: Int,
) -> Result(Nil, StreamError) {
  case value > 0 && value <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "must be positive and at most " <> int.to_string(maximum),
      ))
  }
}

fn valid_text(
  field: String,
  value: String,
  minimum: Int,
  maximum: Int,
) -> Result(Nil, StreamError) {
  case
    string.length(value) >= minimum
    && string.length(value) <= maximum
    && string.trim(value) == value
    && !string.contains(value, "\n")
    && !string.contains(value, "\r")
    && !string.contains(value, "\t")
  {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "outside bounded plain-text policy"))
  }
}
