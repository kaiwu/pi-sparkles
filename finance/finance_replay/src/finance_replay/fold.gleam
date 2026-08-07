import finance_core/time.{type Instant}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/event.{type Event}
import finance_replay/fact.{type Fact, Known}
import finance_replay/wire
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type Status {
  Open
  Completed
  Truncated
  Cancelled
}

pub type OrderingFact {
  OrderedPair(left_event_id: String, right_event_id: String)
  AmbiguousOrdering(
    left_event_id: String,
    right_event_id: String,
    reason: String,
    alternatives: List(String),
  )
}

pub opaque type State {
  State(
    run_id: String,
    run_definition_hash: Sha256,
    revision: Int,
    events: List(Event),
    status: Status,
    ordering_facts: List(OrderingFact),
  )
}

pub type Effect {
  PersistEvent(event: Event)
  TerminalFact(status: Status, event_id: String)
}

pub type AppendOutcome {
  Stored(event: Event)
  AlreadyStored(event: Event)
}

pub type FoldError {
  RunMismatch(expected: String, received: String)
  DuplicateEventId(String)
  IdempotencyConflict(
    idempotency_key: String,
    original_event_id: String,
    original_semantic_hash: String,
    received_semantic_hash: String,
  )
  ReplayClockMovedBackward(previous: Int, received: Int)
  KnownTimeMovedBackward(previous_event_id: String, received_event_id: String)
  RevisionExhausted
}

pub opaque type Checkpoint {
  Checkpoint(
    checkpoint_id: String,
    run_definition_hash: Sha256,
    last_event_id: Fact(String),
    last_event_time: Fact(Instant),
    state_hash: Sha256,
    position_ledger_hash: Fact(Sha256),
    random_stream_state: Fact(String),
    created_at: Instant,
    digest: Sha256,
  )
}

pub type CheckpointError {
  InvalidCheckpointId
  CheckpointDefinitionMismatch(expected: String, received: String)
  CheckpointStateMismatch(expected: String, received: String)
}

pub const maximum_revision = 1_000_000

pub fn empty(run_id: String, run_definition_hash: Sha256) -> State {
  State(run_id, run_definition_hash, 0, [], Open, [])
}

pub fn append(
  state state_value: State,
  event new_event: Event,
) -> Result(#(State, AppendOutcome, List(Effect)), FoldError) {
  use _ <- result.try(validate_run(state_value, new_event))
  case
    find_by_idempotency(state_value.events, event.idempotency_key(new_event))
  {
    Some(existing) ->
      case
        event.semantic_content_hash(existing)
        == event.semantic_content_hash(new_event)
      {
        True -> Ok(#(state_value, AlreadyStored(existing), []))
        False ->
          Error(IdempotencyConflict(
            event.idempotency_key(new_event),
            event.event_id(existing),
            existing
              |> event.semantic_content_hash
              |> identity.sha256_value,
            new_event
              |> event.semantic_content_hash
              |> identity.sha256_value,
          ))
      }
    None ->
      case find_by_event_id(state_value.events, event.event_id(new_event)) {
        Some(_) -> Error(DuplicateEventId(event.event_id(new_event)))
        None -> append_fresh(state_value, new_event)
      }
  }
}

fn append_fresh(
  state_value: State,
  new_event: Event,
) -> Result(#(State, AppendOutcome, List(Effect)), FoldError) {
  case state_value.revision >= maximum_revision {
    True -> Error(RevisionExhausted)
    False -> {
      use new_ordering <- result.try(ordering_against_last(
        state_value.events,
        new_event,
      ))
      let next_status = status_after(state_value.status, event.kind(new_event))
      let effects = case next_status == state_value.status {
        True -> [PersistEvent(new_event)]
        False -> [
          PersistEvent(new_event),
          TerminalFact(next_status, event.event_id(new_event)),
        ]
      }
      let next =
        State(
          state_value.run_id,
          state_value.run_definition_hash,
          state_value.revision + 1,
          list.append(state_value.events, [new_event]),
          next_status,
          list.append(state_value.ordering_facts, new_ordering),
        )
      Ok(#(next, Stored(new_event), effects))
    }
  }
}

/// The batch fold uses exactly the same transition as incremental appends.
pub fn append_many(
  state state_value: State,
  events new_events: List(Event),
) -> Result(#(State, List(AppendOutcome), List(Effect)), FoldError) {
  append_many_loop(new_events, state_value, [], [])
}

fn append_many_loop(
  remaining: List(Event),
  current: State,
  reversed_outcomes: List(AppendOutcome),
  reversed_effects: List(Effect),
) -> Result(#(State, List(AppendOutcome), List(Effect)), FoldError) {
  case remaining {
    [] ->
      Ok(#(
        current,
        list.reverse(reversed_outcomes),
        list.reverse(reversed_effects),
      ))
    [next, ..rest] -> {
      use #(next_state, outcome, effects) <- result.try(append(current, next))
      append_many_loop(
        rest,
        next_state,
        [outcome, ..reversed_outcomes],
        list.append(list.reverse(effects), reversed_effects),
      )
    }
  }
}

fn validate_run(
  state_value: State,
  new_event: Event,
) -> Result(Nil, FoldError) {
  case state_value.run_id == event.run_id(new_event) {
    True -> Ok(Nil)
    False -> Error(RunMismatch(state_value.run_id, event.run_id(new_event)))
  }
}

fn ordering_against_last(
  previous: List(Event),
  received: Event,
) -> Result(List(OrderingFact), FoldError) {
  case list.last(previous) {
    Error(_) -> Ok([])
    Ok(last) ->
      case event.replay_clock(received) < event.replay_clock(last) {
        True ->
          Error(ReplayClockMovedBackward(
            event.replay_clock(last),
            event.replay_clock(received),
          ))
        False -> compare_times(last, received)
      }
  }
}

fn compare_times(
  left: Event,
  right: Event,
) -> Result(List(OrderingFact), FoldError) {
  case event.event_time(left), event.event_time(right) {
    Known(left_time), Known(right_time) -> {
      let left_millis = time.unix_milliseconds(left_time)
      let right_millis = time.unix_milliseconds(right_time)
      case left_millis > right_millis {
        True ->
          Error(KnownTimeMovedBackward(
            event.event_id(left),
            event.event_id(right),
          ))
        False if left_millis < right_millis ->
          Ok([OrderedPair(event.event_id(left), event.event_id(right))])
        False -> compare_availability(left, right)
      }
    }
    _, _ ->
      Ok([
        AmbiguousOrdering(
          event.event_id(left),
          event.event_id(right),
          "event_time is not known for both events",
          [
            event.event_id(left) <> " before " <> event.event_id(right),
            event.event_id(right) <> " before " <> event.event_id(left),
          ],
        ),
      ])
  }
}

fn compare_availability(
  left: Event,
  right: Event,
) -> Result(List(OrderingFact), FoldError) {
  case event.availability_time(left), event.availability_time(right) {
    Known(left_time), Known(right_time) -> {
      let left_millis = time.unix_milliseconds(left_time)
      let right_millis = time.unix_milliseconds(right_time)
      case left_millis > right_millis {
        True ->
          Error(KnownTimeMovedBackward(
            event.event_id(left),
            event.event_id(right),
          ))
        False -> Ok([OrderedPair(event.event_id(left), event.event_id(right))])
      }
    }
    _, _ ->
      Ok([
        AmbiguousOrdering(
          event.event_id(left),
          event.event_id(right),
          "equal event_time and availability_time is not known for both events",
          [
            event.event_id(left) <> " before " <> event.event_id(right),
            event.event_id(right) <> " before " <> event.event_id(left),
          ],
        ),
      ])
  }
}

fn status_after(previous: Status, kind: event.Kind) -> Status {
  case kind {
    event.RunCompleted -> Completed
    event.RunTruncated -> Truncated
    event.RunCancelled -> Cancelled
    event.RunResumed -> Open
    _ -> previous
  }
}

fn find_by_idempotency(values: List(Event), key: String) -> Option(Event) {
  case values {
    [] -> None
    [value, ..rest] ->
      case event.idempotency_key(value) == key {
        True -> Some(value)
        False -> find_by_idempotency(rest, key)
      }
  }
}

fn find_by_event_id(values: List(Event), id: String) -> Option(Event) {
  case values {
    [] -> None
    [value, ..rest] ->
      case event.event_id(value) == id {
        True -> Some(value)
        False -> find_by_event_id(rest, id)
      }
  }
}

pub fn semantic_hash(value: State) -> Sha256 {
  let payload =
    json.object([
      #("run_id", json.string(value.run_id)),
      #("run_definition_hash", wire.sha_json(value.run_definition_hash)),
      #(
        "ordered_event_semantic_hashes",
        json.array(value.events, fn(value) {
          value |> event.semantic_content_hash |> wire.sha_json
        }),
      ),
      #("status", value.status |> status_name |> json.string),
    ])
  let assert Ok(value_hash) = payload |> json.to_string |> hash.text
  value_hash
}

pub fn checkpoint(
  checkpoint_id: String,
  state_value: State,
  position_ledger_hash: Fact(Sha256),
  random_stream_state: Fact(String),
  created_at: Instant,
) -> Result(Checkpoint, CheckpointError) {
  case wire.valid_text(checkpoint_id, 512) {
    False -> Error(InvalidCheckpointId)
    True -> {
      let last_event_id = case list.last(state_value.events) {
        Ok(value) -> Known(event.event_id(value))
        Error(_) -> fact.NotObtained("run has no replay events")
      }
      let last_event_time = case list.last(state_value.events) {
        Ok(value) -> event.event_time(value)
        Error(_) -> fact.NotObtained("run has no replay events")
      }
      let state_hash = semantic_hash(state_value)
      let payload =
        checkpoint_payload(
          checkpoint_id,
          state_value.run_definition_hash,
          last_event_id,
          last_event_time,
          state_hash,
          position_ledger_hash,
          random_stream_state,
          created_at,
        )
      let assert Ok(digest) = payload |> json.to_string |> hash.text
      Ok(Checkpoint(
        checkpoint_id,
        state_value.run_definition_hash,
        last_event_id,
        last_event_time,
        state_hash,
        position_ledger_hash,
        random_stream_state,
        created_at,
        digest,
      ))
    }
  }
}

fn checkpoint_payload(
  checkpoint_id: String,
  definition_hash: Sha256,
  last_event_id: Fact(String),
  last_event_time: Fact(Instant),
  state_hash: Sha256,
  position_ledger_hash: Fact(Sha256),
  random_stream_state: Fact(String),
  created_at: Instant,
) -> json.Json {
  json.object([
    #("schema", json.string("finance_replay_checkpoint")),
    #("schema_version", json.int(1)),
    #("checkpoint_id", json.string(checkpoint_id)),
    #("run_definition_hash", wire.sha_json(definition_hash)),
    #("last_event_id", fact.to_json(last_event_id, json.string)),
    #("last_event_time", fact.to_json(last_event_time, wire.instant_json)),
    #("state_hash", wire.sha_json(state_hash)),
    #("position_ledger_hash", fact.to_json(position_ledger_hash, wire.sha_json)),
    #("random_stream_state", fact.to_json(random_stream_state, json.string)),
    #("created_at", wire.instant_json(created_at)),
  ])
}

pub fn checkpoint_json(value: Checkpoint) -> json.Json {
  json.object([
    #(
      "payload",
      checkpoint_payload(
        value.checkpoint_id,
        value.run_definition_hash,
        value.last_event_id,
        value.last_event_time,
        value.state_hash,
        value.position_ledger_hash,
        value.random_stream_state,
        value.created_at,
      ),
    ),
    #("canonical_content_hash", wire.sha_json(value.digest)),
  ])
}

pub fn resume(
  value: Checkpoint,
  current: State,
) -> Result(State, CheckpointError) {
  case value.run_definition_hash == current.run_definition_hash {
    False ->
      Error(CheckpointDefinitionMismatch(
        identity.sha256_value(value.run_definition_hash),
        identity.sha256_value(current.run_definition_hash),
      ))
    True -> {
      let current_hash = semantic_hash(current)
      case value.state_hash == current_hash {
        True -> Ok(current)
        False ->
          Error(CheckpointStateMismatch(
            identity.sha256_value(value.state_hash),
            identity.sha256_value(current_hash),
          ))
      }
    }
  }
}

pub fn status_name(value: Status) -> String {
  case value {
    Open -> "open"
    Completed -> "completed"
    Truncated -> "truncated"
    Cancelled -> "cancelled"
  }
}

pub fn revision(value: State) -> Int {
  value.revision
}

pub fn status(value: State) -> Status {
  value.status
}

pub fn events(value: State) -> List(Event) {
  value.events
}

pub fn ordering_facts(value: State) -> List(OrderingFact) {
  value.ordering_facts
}

pub fn run_id(value: State) -> String {
  value.run_id
}

pub fn run_definition_hash(value: State) -> Sha256 {
  value.run_definition_hash
}

pub fn checkpoint_hash(value: Checkpoint) -> Sha256 {
  value.digest
}
