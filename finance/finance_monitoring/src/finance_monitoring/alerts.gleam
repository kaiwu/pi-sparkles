import finance_provenance/hash
import finance_provenance/identity
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const maximum_events = 10_000

const maximum_safe_integer = 9_007_199_254_740_991

const maximum_safe_seconds = 9_007_199_254_740

pub type AppendOutcome {
  Stored(event_id: String)
  AlreadyStored(event_id: String)
}

pub opaque type State {
  State(
    revision: Int,
    events_reversed: List(Event),
    events_by_id: Dict(String, Event),
    events_by_idempotency: Dict(String, Event),
  )
}

type Event {
  Event(
    revision: Int,
    event_id: String,
    idempotency_key: String,
    monitor_id: String,
    kind: String,
    occurred_at_unix_ms: Int,
    privacy: String,
    parent_event_id: Option(String),
    payload: String,
    payload_hash: String,
    canonical_hash: String,
  )
}

type Scope {
  Scope(
    kind: String,
    track: String,
    listing_ids: List(String),
    mic: String,
    source_scope: List(String),
    event_kinds: List(String),
    portfolio_receipt: Option(String),
  )
}

type Predicate {
  Predicate(kind: String, field: String, operator: String, value: String)
}

type Temporal {
  Temporal(
    freshness_cutoff_seconds: Int,
    start_at_unix_ms: Int,
    end_at_unix_ms: Option(Int),
  )
}

type Dedupe {
  Dedupe(
    kind: String,
    window_seconds: Int,
    cooldown_seconds: Int,
    scope: String,
  )
}

type Budgets {
  Budgets(
    max_events_per_batch: Int,
    max_matches_per_batch: Int,
    max_consecutive_failures: Int,
  )
}

type NotificationAuthorization {
  NotificationAuthorization(
    authorized: Bool,
    authorization_id: String,
    channel: String,
    destination_ref: String,
    maximum_attempts: Int,
  )
}

type Definition {
  Definition(
    schema_version: Int,
    contract_id: String,
    monitor_id: String,
    version: Int,
    owner_kind: String,
    owner_id: String,
    scope: Scope,
    predicate: Predicate,
    temporal: Temporal,
    dedupe: Dedupe,
    budgets: Budgets,
    authorization: NotificationAuthorization,
    retention_policy: String,
    parent_event_id: Option(String),
    source_entitlement_receipts: List(String),
  )
}

type Field {
  Field(name: String, state: String, value: Option(String))
}

type Observation {
  Observation(
    observation_id: String,
    event_identity: String,
    content_hash: String,
    observed_at_unix_ms: Int,
    knowledge_at_unix_ms: Int,
    corrects: Option(String),
    fields: List(Field),
  )
}

type Batch {
  Batch(
    schema_version: Int,
    contract_id: String,
    batch_id: String,
    monitor_id: String,
    evaluated_at_unix_ms: Int,
    observations: List(Observation),
    source_receipts: List(String),
  )
}

type NotificationRecord {
  NotificationRecord(
    monitor_id: String,
    match_id: String,
    authorization_id: String,
    channel: String,
    destination_ref: String,
    attempt: Int,
    status: String,
    provider_receipt: String,
    destination_privacy: String,
  )
}

type EvaluationResult {
  EvaluationResult(
    observation_id: String,
    event_identity: String,
    content_hash: String,
    corrects: Option(String),
    result: String,
    reason: String,
    match_id: Option(String),
    predicate_kind: String,
  )
}

type EvaluationRecord {
  EvaluationRecord(
    batch_id: String,
    monitor_id: String,
    definition_event_id: String,
    definition_content_hash: String,
    evaluated_at_unix_ms: Int,
    observation_count: Int,
    match_count: Int,
    results: List(EvaluationResult),
    source_receipts: List(String),
    source_batch_sha256: String,
    silence_meaning: String,
  )
}

pub type AlertError {
  InvalidJson
  ContentHashMismatch
  InvalidDefinition
  InvalidBatch
  InvalidReceipt(field: String)
  InvalidEvent
  InvalidJournal(line: Int)
  TooManyEvents
  RevisionConflict(current: Int)
  IdempotencyConflict(key: String)
  DuplicateEventId(event_id: String)
  MonitorNotFound(monitor_id: String)
  MonitorDisabled(monitor_id: String)
  DefinitionVersionConflict
  DefinitionParentConflict
  BatchMonitorMismatch
  NotificationNotAuthorized
  NotificationChannelMismatch
  NotificationDestinationMismatch
  NotificationAttemptExceeded
  MatchNotFound(match_id: String)
}

pub fn empty() -> State {
  State(0, [], dict.new(), dict.new())
}

pub fn revision(state: State) -> Int {
  state.revision
}

pub fn define(
  state: State,
  expected_revision: Int,
  event_id: String,
  idempotency_key: String,
  occurred_at_unix_ms: Int,
  privacy: String,
  definition_bytes: String,
  expected_sha256: String,
) -> Result(#(State, AppendOutcome, json.Json), AlertError) {
  use _ <- result.try(require_revision(state, expected_revision))
  use _ <- result.try(verify_hash(definition_bytes, expected_sha256))
  use definition <- result.try(parse_definition(definition_bytes))
  use _ <- result.try(validate_definition(definition))
  use _ <- result.try(validate_definition_lineage(state, definition))
  use event <- result.try(new_event(
    state.revision + 1,
    event_id,
    idempotency_key,
    definition.monitor_id,
    "definition",
    occurred_at_unix_ms,
    privacy,
    definition.parent_event_id,
    definition_bytes,
  ))
  use #(next, outcome) <- result.try(append(state, event))
  Ok(#(next, outcome, definition_json(definition, expected_sha256)))
}

pub fn disable(
  state: State,
  expected_revision: Int,
  event_id: String,
  idempotency_key: String,
  monitor_id: String,
  occurred_at_unix_ms: Int,
  privacy: String,
  reason: String,
) -> Result(#(State, AppendOutcome), AlertError) {
  use _ <- result.try(require_revision(state, expected_revision))
  use definition_event <- result.try(current_definition_event(state, monitor_id))
  use _ <- result.try(
    validate_texts([event_id, idempotency_key, monitor_id, reason]),
  )
  let payload =
    json.object([
      #("monitorId", json.string(monitor_id)),
      #("reason", json.string(reason)),
      #("definitionEventId", json.string(definition_event.event_id)),
    ])
    |> json.to_string
  use event <- result.try(new_event(
    state.revision + 1,
    event_id,
    idempotency_key,
    monitor_id,
    "disabled",
    occurred_at_unix_ms,
    privacy,
    Some(definition_event.event_id),
    payload,
  ))
  append(state, event)
}

pub fn evaluate(
  state: State,
  expected_revision: Int,
  event_id: String,
  idempotency_key: String,
  occurred_at_unix_ms: Int,
  privacy: String,
  batch_bytes: String,
  expected_sha256: String,
) -> Result(#(State, AppendOutcome, json.Json), AlertError) {
  use _ <- result.try(require_revision(state, expected_revision))
  use _ <- result.try(verify_hash(batch_bytes, expected_sha256))
  use batch <- result.try(parse_batch(batch_bytes))
  use _ <- result.try(validate_batch(batch))
  use definition_event <- result.try(current_definition_event(
    state,
    batch.monitor_id,
  ))
  use _ <- result.try(case is_disabled(state, batch.monitor_id) {
    True -> Error(MonitorDisabled(batch.monitor_id))
    False -> Ok(Nil)
  })
  let assert Ok(definition) = parse_definition(definition_event.payload)
  use _ <- result.try(case batch.monitor_id == definition.monitor_id {
    True -> Ok(Nil)
    False -> Error(BatchMonitorMismatch)
  })
  use _ <- result.try(
    case
      list.length(batch.observations) <= definition.budgets.max_events_per_batch
    {
      True -> Ok(Nil)
      False -> Error(InvalidBatch)
    },
  )
  use _ <- result.try(case latest_evaluation_time(state, batch.monitor_id) {
    Some(previous) if batch.evaluated_at_unix_ms < previous ->
      Error(InvalidBatch)
    _ -> Ok(Nil)
  })
  let prior_match_time = latest_match_time(state, batch.monitor_id)
  let seen_observations = observation_times(state, batch.monitor_id)
  let #(rows, match_count, _) =
    evaluate_observations(
      batch.observations,
      definition,
      batch.evaluated_at_unix_ms,
      prior_match_time,
      seen_observations,
      [],
      0,
    )
  let payload_json =
    json.object([
      #("batchId", json.string(batch.batch_id)),
      #("monitorId", json.string(batch.monitor_id)),
      #("definitionEventId", json.string(definition_event.event_id)),
      #("definitionContentHash", json.string(definition_event.payload_hash)),
      #("evaluatedAtUnixMilliseconds", json.int(batch.evaluated_at_unix_ms)),
      #("observationCount", json.int(list.length(batch.observations))),
      #("matchCount", json.int(match_count)),
      #("results", json.array(rows, fn(value) { value })),
      #("sourceReceipts", json.array(batch.source_receipts, json.string)),
      #("sourceBatchSha256", json.string(expected_sha256)),
      #(
        "silenceMeaning",
        json.string("no_supplied_observation_matched_not_all_clear"),
      ),
    ])
  use event <- result.try(new_event(
    state.revision + 1,
    event_id,
    idempotency_key,
    batch.monitor_id,
    "evaluation",
    occurred_at_unix_ms,
    privacy,
    Some(definition_event.event_id),
    json.to_string(payload_json),
  ))
  use #(next, outcome) <- result.try(append(state, event))
  Ok(#(next, outcome, payload_json))
}

pub fn record_notification(
  state: State,
  expected_revision: Int,
  event_id: String,
  idempotency_key: String,
  monitor_id: String,
  match_id: String,
  authorization_id: String,
  channel: String,
  destination_ref: String,
  attempt: Int,
  status: String,
  provider_receipt: String,
  occurred_at_unix_ms: Int,
  privacy: String,
) -> Result(#(State, AppendOutcome, json.Json), AlertError) {
  use _ <- result.try(require_revision(state, expected_revision))
  use _ <- result.try(authorize_notification(
    state,
    monitor_id,
    match_id,
    authorization_id,
    channel,
    destination_ref,
    attempt,
  ))
  use _ <- result.try(
    validate_texts([
      event_id,
      idempotency_key,
      match_id,
      status,
      provider_receipt,
    ]),
  )
  let payload_json =
    json.object([
      #("monitorId", json.string(monitor_id)),
      #("matchId", json.string(match_id)),
      #("authorizationId", json.string(authorization_id)),
      #("channel", json.string(channel)),
      #("destinationRef", json.string(destination_ref)),
      #("attempt", json.int(attempt)),
      #("status", json.string(status)),
      #("providerReceipt", json.string(provider_receipt)),
      #("destinationPrivacy", json.string("opaque_reference_only")),
    ])
  use event <- result.try(new_event(
    state.revision + 1,
    event_id,
    idempotency_key,
    monitor_id,
    "notification",
    occurred_at_unix_ms,
    privacy,
    None,
    json.to_string(payload_json),
  ))
  use #(next, outcome) <- result.try(append(state, event))
  Ok(#(next, outcome, payload_json))
}

/// Validate exact current authorization and a durable match before invoking a
/// notification effect. `record_notification` repeats the proof before write.
pub fn authorize_notification(
  state: State,
  monitor_id: String,
  match_id: String,
  authorization_id: String,
  channel: String,
  destination_ref: String,
  attempt: Int,
) -> Result(Nil, AlertError) {
  use definition_event <- result.try(current_definition_event(state, monitor_id))
  let assert Ok(definition) = parse_definition(definition_event.payload)
  let authorization = definition.authorization
  use _ <- result.try(
    case
      authorization.authorized
      && authorization.authorization_id == authorization_id
    {
      True -> Ok(Nil)
      False -> Error(NotificationNotAuthorized)
    },
  )
  use _ <- result.try(case authorization.channel == channel {
    True -> Ok(Nil)
    False -> Error(NotificationChannelMismatch)
  })
  use _ <- result.try(case authorization.destination_ref == destination_ref {
    True -> Ok(Nil)
    False -> Error(NotificationDestinationMismatch)
  })
  use _ <- result.try(
    case attempt >= 1 && attempt <= authorization.maximum_attempts {
      True -> Ok(Nil)
      False -> Error(NotificationAttemptExceeded)
    },
  )
  case match_exists(state, monitor_id, match_id) {
    True -> Ok(Nil)
    False -> Error(MatchNotFound(match_id))
  }
}

/// Prove that an earlier notification is the exact same request before the
/// shell suppresses a repeated external effect. Reusing the key with any
/// changed event or delivery field is a conflict.
pub fn notification_retry(
  state: State,
  event_id: String,
  idempotency_key: String,
  monitor_id: String,
  match_id: String,
  authorization_id: String,
  channel: String,
  destination_ref: String,
  attempt: Int,
  status: String,
  occurred_at_unix_ms: Int,
  privacy: String,
) -> Result(Bool, AlertError) {
  case dict.get(state.events_by_idempotency, idempotency_key) {
    Error(_) -> Ok(False)
    Ok(event) ->
      case event.kind {
        "notification" ->
          case json.parse(event.payload, notification_record_decoder()) {
            Error(_) -> Error(InvalidEvent)
            Ok(record) ->
              case
                event.event_id == event_id
                && event.monitor_id == monitor_id
                && event.occurred_at_unix_ms == occurred_at_unix_ms
                && event.privacy == privacy
                && record.monitor_id == monitor_id
                && record.match_id == match_id
                && record.authorization_id == authorization_id
                && record.channel == channel
                && record.destination_ref == destination_ref
                && record.attempt == attempt
                && record.status == status
              {
                True -> Ok(True)
                False -> Error(IdempotencyConflict(idempotency_key))
              }
          }
        _ -> Error(IdempotencyConflict(idempotency_key))
      }
  }
}

pub fn inspect(
  state: State,
  monitor_id: String,
  include_private: Bool,
  maximum_event_count: Int,
) -> Result(json.Json, AlertError) {
  use definition_event <- result.try(current_definition_event(state, monitor_id))
  let assert Ok(definition) = parse_definition(definition_event.payload)
  let matching =
    state
    |> events
    |> list.filter(fn(event) {
      event.monitor_id == monitor_id
      && { include_private || event.privacy != "private" }
    })
  let selected = list.take(matching, int.max(0, maximum_event_count))
  let payload =
    json.object([
      #("schemaVersion", json.int(1)),
      #("journalRevision", json.int(state.revision)),
      #("monitorId", json.string(monitor_id)),
      #("disabled", json.bool(is_disabled(state, monitor_id))),
      #(
        "currentDefinition",
        definition_json(definition, definition_event.payload_hash),
      ),
      #("matchedEventCount", json.int(list.length(matching))),
      #("returnedEventCount", json.int(list.length(selected))),
      #(
        "omittedEventCount",
        json.int(list.length(matching) - list.length(selected)),
      ),
      #("events", json.array(selected, event_json)),
      #("persistence", json.string("user_owned_append_only_jsonl_atomic_cas")),
      #(
        "availableOperations",
        json.array(
          ["evaluate", "notify_authorized_match", "disable", "export_jsonl"],
          json.string,
        ),
      ),
    ])
  let assert Ok(receipt) = payload |> json.to_string |> hash.text
  Ok(
    json.object([
      #("monitor", payload),
      #("canonicalContentHash", receipt |> identity.sha256_value |> json.string),
    ]),
  )
}

pub fn encode_state(state: State) -> String {
  case events(state) {
    [] -> ""
    events ->
      events
      |> list.map(encode_event)
      |> string.join(with: "\n")
      |> fn(value) { value <> "\n" }
  }
}

pub fn decode_jsonl(input: String) -> Result(State, AlertError) {
  let lines = case input {
    "" -> []
    _ -> {
      let values = string.split(input, on: "\n")
      case list.last(values) {
        Ok("") -> list.take(values, list.length(values) - 1)
        _ -> values
      }
    }
  }
  decode_lines(lines, empty(), 1)
}

pub fn error_message(error: AlertError) -> String {
  case error {
    InvalidJson -> "Alert packet is not valid versioned JSON"
    ContentHashMismatch -> "Alert packet does not match expectedSha256"
    InvalidDefinition ->
      "Alert monitor definition, predicate, scope, budget, entitlement, retention, or authorization is invalid"
    InvalidBatch ->
      "Alert observation batch identity, bounds, fields, time, or receipts are invalid"
    InvalidReceipt(field) -> "Alert SHA-256 receipt is invalid: " <> field
    InvalidEvent -> "Alert journal event failed canonical validation"
    InvalidJournal(line) ->
      "Alert journal replay failed at line " <> int.to_string(line)
    TooManyEvents -> "Alert journal reached its event budget"
    RevisionConflict(current) ->
      "Alert journal revision conflict; currentRevision="
      <> int.to_string(current)
    IdempotencyConflict(key) -> "Alert idempotency conflict: " <> key
    DuplicateEventId(id) -> "Alert eventId is already used: " <> id
    MonitorNotFound(id) -> "Alert monitor was not found: " <> id
    MonitorDisabled(id) -> "Alert monitor is disabled: " <> id
    DefinitionVersionConflict ->
      "Alert definition version must advance exactly by one"
    DefinitionParentConflict ->
      "Alert definition parent must be the current definition event"
    BatchMonitorMismatch ->
      "Alert batch monitorId does not match the current definition"
    NotificationNotAuthorized ->
      "Notification is not explicitly authorized by the current monitor definition"
    NotificationChannelMismatch ->
      "Notification channel differs from the current authorization"
    NotificationDestinationMismatch ->
      "Notification destinationRef differs from the current authorization"
    NotificationAttemptExceeded ->
      "Notification attempt exceeds the authorized bounded attempts"
    MatchNotFound(id) ->
      "Notification matchId was not found in durable evaluations: " <> id
  }
}

fn append(
  state: State,
  event: Event,
) -> Result(#(State, AppendOutcome), AlertError) {
  case dict.get(state.events_by_idempotency, event.idempotency_key) {
    Ok(existing) ->
      case
        existing.payload_hash == event.payload_hash
        && existing.kind == event.kind
        && existing.event_id == event.event_id
        && existing.monitor_id == event.monitor_id
        && existing.occurred_at_unix_ms == event.occurred_at_unix_ms
        && existing.privacy == event.privacy
        && existing.parent_event_id == event.parent_event_id
      {
        True -> Ok(#(state, AlreadyStored(existing.event_id)))
        False -> Error(IdempotencyConflict(event.idempotency_key))
      }
    Error(_) ->
      case dict.has_key(state.events_by_id, event.event_id) {
        True -> Error(DuplicateEventId(event.event_id))
        False if state.revision >= maximum_events -> Error(TooManyEvents)
        False ->
          Ok(#(
            State(
              state.revision + 1,
              [event, ..state.events_reversed],
              dict.insert(state.events_by_id, event.event_id, event),
              dict.insert(
                state.events_by_idempotency,
                event.idempotency_key,
                event,
              ),
            ),
            Stored(event.event_id),
          ))
      }
  }
}

fn evaluate_observations(
  observations: List(Observation),
  definition: Definition,
  evaluated_at: Int,
  last_match_at: Option(Int),
  seen_observations: Dict(String, Int),
  reversed: List(json.Json),
  match_count: Int,
) -> #(List(json.Json), Int, Dict(String, Int)) {
  case observations {
    [] -> #(list.reverse(reversed), match_count, seen_observations)
    [observation, ..rest] -> {
      let duplicate =
        seen_within_window(
          seen_observations,
          observation.content_hash,
          evaluated_at,
          definition.dedupe.window_seconds,
        )
      let within_cooldown = case last_match_at {
        Some(value) ->
          evaluated_at - value < definition.dedupe.cooldown_seconds * 1000
        None -> False
      }
      let #(result_name, reason, matched) = case duplicate, within_cooldown {
        True, _ -> #(
          "duplicate_suppressed",
          "content_hash_already_recorded",
          False,
        )
        _, True -> #(
          "cooldown_suppressed",
          "caller_defined_monitor_cooldown",
          False,
        )
        False, False -> evaluate_one(observation, definition, evaluated_at)
      }
      let allowed_match =
        matched && match_count < definition.budgets.max_matches_per_batch
      let final_result = case matched, allowed_match {
        True, False -> "match_budget_suppressed"
        _, _ -> result_name
      }
      let match_id = case allowed_match {
        True ->
          Some(
            definition.monitor_id
            <> ":"
            <> observation.observation_id
            <> ":v"
            <> int.to_string(definition.version),
          )
        False -> None
      }
      let row =
        json.object([
          #("observationId", json.string(observation.observation_id)),
          #("eventIdentity", json.string(observation.event_identity)),
          #("contentHash", json.string(observation.content_hash)),
          #("corrects", json.nullable(observation.corrects, json.string)),
          #("result", json.string(final_result)),
          #("reason", json.string(reason)),
          #("matchId", json.nullable(match_id, json.string)),
          #("predicateKind", json.string(definition.predicate.kind)),
        ])
      evaluate_observations(
        rest,
        definition,
        evaluated_at,
        case allowed_match {
          True -> Some(evaluated_at)
          False -> last_match_at
        },
        dict.insert(seen_observations, observation.content_hash, evaluated_at),
        [row, ..reversed],
        case allowed_match {
          True -> match_count + 1
          False -> match_count
        },
      )
    }
  }
}

fn evaluate_one(
  observation: Observation,
  definition: Definition,
  evaluated_at: Int,
) -> #(String, String, Bool) {
  let Temporal(freshness, start_at, end_at) = definition.temporal
  case observation.knowledge_at_unix_ms > evaluated_at {
    True -> #("cannot_evaluate", "future_knowledge_excluded", False)
    False
      if evaluated_at - observation.knowledge_at_unix_ms > freshness * 1000
    -> #("cannot_evaluate", "freshness_cutoff_exceeded", False)
    False if observation.observed_at_unix_ms < start_at -> #(
      "cannot_evaluate",
      "before_monitor_start",
      False,
    )
    False ->
      case end_at {
        Some(value) if observation.observed_at_unix_ms > value -> #(
          "cannot_evaluate",
          "after_monitor_end",
          False,
        )
        _ -> evaluate_field(observation.fields, definition.predicate)
      }
  }
}

fn evaluate_field(
  fields: List(Field),
  predicate: Predicate,
) -> #(String, String, Bool) {
  case list.find(fields, fn(field) { field.name == predicate.field }) {
    Error(_) -> #("cannot_evaluate", "predicate_field_absent", False)
    Ok(field) ->
      case field.state, field.value {
        "known", Some(value) ->
          case predicate.operator {
            "exact_equals" ->
              case value == predicate.value {
                True -> #("matched", "exact_equals_true", True)
                False -> #("no_match", "exact_equals_false", False)
              }
            "string_contains" ->
              case string.contains(value, predicate.value) {
                True -> #("matched", "string_contains_true", True)
                False -> #("no_match", "string_contains_false", False)
              }
            _ -> #("error", "unsupported_predicate_operator", False)
          }
        state, _ -> #("cannot_evaluate", "field_state:" <> state, False)
      }
  }
}

fn seen_within_window(
  seen: Dict(String, Int),
  content_hash: String,
  evaluated_at: Int,
  window_seconds: Int,
) -> Bool {
  case dict.get(seen, content_hash) {
    Ok(previous) -> evaluated_at - previous <= window_seconds * 1000
    Error(_) -> False
  }
}

fn observation_times(state: State, monitor_id: String) -> Dict(String, Int) {
  state
  |> events
  |> list.fold(dict.new(), fn(seen, event) {
    case parsed_evaluation(event) {
      Some(record) if record.monitor_id == monitor_id ->
        list.fold(record.results, seen, fn(index, value) {
          dict.insert(index, value.content_hash, record.evaluated_at_unix_ms)
        })
      _ -> seen
    }
  })
}

fn latest_evaluation_time(state: State, monitor_id: String) -> Option(Int) {
  latest_evaluation_time_loop(state.events_reversed, monitor_id)
}

fn latest_evaluation_time_loop(
  events: List(Event),
  monitor_id: String,
) -> Option(Int) {
  case events {
    [] -> None
    [event, ..rest] ->
      case parsed_evaluation(event) {
        Some(record) if record.monitor_id == monitor_id ->
          Some(record.evaluated_at_unix_ms)
        _ -> latest_evaluation_time_loop(rest, monitor_id)
      }
  }
}

fn latest_match_time(state: State, monitor_id: String) -> Option(Int) {
  latest_match_time_loop(state.events_reversed, monitor_id)
}

fn latest_match_time_loop(
  events: List(Event),
  monitor_id: String,
) -> Option(Int) {
  case events {
    [] -> None
    [event, ..rest] ->
      case parsed_evaluation(event) {
        Some(record) if record.monitor_id == monitor_id ->
          case
            list.any(record.results, fn(value) { value.result == "matched" })
          {
            True -> Some(record.evaluated_at_unix_ms)
            False -> latest_match_time_loop(rest, monitor_id)
          }
        _ -> latest_match_time_loop(rest, monitor_id)
      }
  }
}

fn match_exists(state: State, monitor_id: String, match_id: String) -> Bool {
  state.events_reversed
  |> list.any(fn(event) {
    case parsed_evaluation(event) {
      Some(record) if record.monitor_id == monitor_id ->
        list.any(record.results, fn(value) {
          value.match_id == Some(match_id) && value.result == "matched"
        })
      _ -> False
    }
  })
}

fn parsed_evaluation(event: Event) -> Option(EvaluationRecord) {
  case event.kind, json.parse(event.payload, evaluation_record_decoder()) {
    "evaluation", Ok(record) -> Some(record)
    _, _ -> None
  }
}

fn current_definition_event(
  state: State,
  monitor_id: String,
) -> Result(Event, AlertError) {
  state.events_reversed
  |> list.find(fn(event) {
    event.monitor_id == monitor_id && event.kind == "definition"
  })
  |> result.map_error(fn(_) { MonitorNotFound(monitor_id) })
}

fn is_disabled(state: State, monitor_id: String) -> Bool {
  let definition =
    state.events_reversed
    |> list.find(fn(event) {
      event.monitor_id == monitor_id && event.kind == "definition"
    })
  let disabled =
    state.events_reversed
    |> list.find(fn(event) {
      event.monitor_id == monitor_id && event.kind == "disabled"
    })
  case definition, disabled {
    Ok(definition), Ok(disable_event) ->
      disable_event.revision > definition.revision
    _, _ -> False
  }
}

fn events(state: State) -> List(Event) {
  list.reverse(state.events_reversed)
}

fn validate_definition_lineage(
  state: State,
  definition: Definition,
) -> Result(Nil, AlertError) {
  case current_definition_event(state, definition.monitor_id) {
    Error(_) ->
      case definition.version == 1 && definition.parent_event_id == None {
        True -> Ok(Nil)
        False -> Error(DefinitionVersionConflict)
      }
    Ok(current) -> {
      let assert Ok(previous) = parse_definition(current.payload)
      case
        definition.version == previous.version + 1,
        definition.parent_event_id == Some(current.event_id)
      {
        False, _ -> Error(DefinitionVersionConflict)
        _, False -> Error(DefinitionParentConflict)
        True, True -> Ok(Nil)
      }
    }
  }
}

fn validate_definition(value: Definition) -> Result(Nil, AlertError) {
  let Scope(
    scope_kind,
    track,
    listing_ids,
    mic,
    sources,
    event_kinds,
    portfolio_receipt,
  ) = value.scope
  let Predicate(predicate_kind, field, operator, predicate_value) =
    value.predicate
  let Temporal(freshness, start_at, end_at) = value.temporal
  let Dedupe(dedupe_kind, window, cooldown, cooldown_scope) = value.dedupe
  let Budgets(max_events, max_matches, max_failures) = value.budgets
  let NotificationAuthorization(
    _,
    authorization_id,
    channel,
    destination,
    attempts,
  ) = value.authorization
  use _ <- result.try(
    case
      value.schema_version == 1
      && value.contract_id == "finance_alerts_definition_v1"
      && value.version >= 1
      && value.version <= maximum_safe_integer
    {
      True -> Ok(Nil)
      False -> Error(InvalidDefinition)
    },
  )
  use _ <- result.try(
    validate_texts([
      value.monitor_id, value.owner_kind, value.owner_id, scope_kind, track, mic,
      predicate_kind, field, operator, predicate_value, dedupe_kind,
      cooldown_scope, authorization_id, channel, destination,
      value.retention_policy,
    ]),
  )
  use _ <- result.try(validate_texts(
    listing_ids
    |> list.append(sources)
    |> list.append(event_kinds),
  ))
  use _ <- result.try(case value.parent_event_id {
    Some(id) -> validate_texts([id])
    None -> Ok(Nil)
  })
  use _ <- result.try(unique(listing_ids, "definition_listing_id"))
  use _ <- result.try(unique(sources, "definition_source_scope"))
  use _ <- result.try(unique(event_kinds, "definition_event_kind"))
  use _ <- result.try(
    case
      list.contains(["company", "portfolio"], scope_kind)
      && list.contains(["cn", "hk", "us"], track)
      && predicate_kind == "caller_supplied"
      && list.contains(["exact_equals", "string_contains"], operator)
      && list.length(listing_ids) <= 1000
      && list.length(sources) >= 1
      && list.length(sources) <= 1000
      && list.length(event_kinds) >= 1
      && list.length(event_kinds) <= 1000
      && list.length(value.source_entitlement_receipts) <= 1000
      && dedupe_kind == "by_content_hash"
      && cooldown_scope == "per_monitor"
      && value.retention_policy == "caller_owned_append_only"
      && freshness >= 0
      && freshness <= maximum_safe_seconds
      && start_at >= 0
      && start_at <= maximum_safe_integer
      && end_after_start(end_at, start_at)
      && window >= 0
      && window <= maximum_safe_seconds
      && cooldown >= 0
      && cooldown <= maximum_safe_seconds
      && max_events >= 1
      && max_events <= 10_000
      && max_matches >= 1
      && max_matches <= 1000
      && max_failures >= 1
      && max_failures <= 100
      && attempts >= 1
      && attempts <= 10
    {
      True -> Ok(Nil)
      False -> Error(InvalidDefinition)
    },
  )
  use _ <- result.try(case portfolio_receipt {
    Some(receipt) -> validate_receipt(receipt, "portfolio_receipt")
    None -> Ok(Nil)
  })
  use _ <- result.try(case scope_kind, portfolio_receipt {
    "portfolio", Some(_) -> Ok(Nil)
    "portfolio", None -> Error(InvalidDefinition)
    "company", _ ->
      case list.length(listing_ids) >= 1 {
        True -> Ok(Nil)
        False -> Error(InvalidDefinition)
      }
    _, _ -> Error(InvalidDefinition)
  })
  list.try_each(value.source_entitlement_receipts, fn(receipt) {
    validate_receipt(receipt, "source_entitlement_receipt")
  })
}

fn validate_batch(value: Batch) -> Result(Nil, AlertError) {
  use _ <- result.try(
    case
      value.schema_version == 1
      && value.contract_id == "finance_alerts_batch_v1"
      && list.length(value.observations) <= 10_000
      && list.length(value.source_receipts) >= 1
      && list.length(value.source_receipts) <= 1000
      && safe_integer(value.evaluated_at_unix_ms)
    {
      True -> Ok(Nil)
      False -> Error(InvalidBatch)
    },
  )
  use _ <- result.try(validate_texts([value.batch_id, value.monitor_id]))
  use _ <- result.try(unique(
    list.map(value.observations, fn(observation) { observation.observation_id }),
    "observation_id",
  ))
  use _ <- result.try(
    list.try_each(value.source_receipts, fn(receipt) {
      validate_receipt(receipt, "batch_source_receipt")
    }),
  )
  list.try_each(value.observations, validate_observation)
}

fn validate_observation(value: Observation) -> Result(Nil, AlertError) {
  use _ <- result.try(
    validate_texts([value.observation_id, value.event_identity]),
  )
  use _ <- result.try(validate_receipt(
    value.content_hash,
    value.observation_id <> ".content_hash",
  ))
  use _ <- result.try(
    case
      safe_integer(value.observed_at_unix_ms)
      && safe_integer(value.knowledge_at_unix_ms)
    {
      True -> Ok(Nil)
      False -> Error(InvalidBatch)
    },
  )
  use _ <- result.try(case value.corrects {
    Some(id) -> validate_texts([id])
    None -> Ok(Nil)
  })
  use _ <- result.try(case list.length(value.fields) <= 1000 {
    True -> Ok(Nil)
    False -> Error(InvalidBatch)
  })
  use _ <- result.try(unique(
    list.map(value.fields, fn(field) { field.name }),
    "observation_field",
  ))
  list.try_each(value.fields, fn(field) {
    use _ <- result.try(validate_texts([field.name, field.state]))
    case field.state, field.value {
      "known", Some(value) -> validate_texts([value])
      "known", None -> Error(InvalidBatch)
      state, None
        if state == "unknown"
        || state == "not_obtained"
        || state == "conflicting"
        || state == "decode_failure"
        || state == "unavailable"
      -> Ok(Nil)
      _, _ -> Error(InvalidBatch)
    }
  })
}

fn require_revision(state: State, expected: Int) -> Result(Nil, AlertError) {
  case state.revision == expected {
    True -> Ok(Nil)
    False -> Error(RevisionConflict(state.revision))
  }
}

fn new_event(
  revision: Int,
  event_id: String,
  idempotency_key: String,
  monitor_id: String,
  kind: String,
  occurred_at: Int,
  privacy: String,
  parent: Option(String),
  payload: String,
) -> Result(Event, AlertError) {
  use _ <- result.try(
    validate_texts([event_id, idempotency_key, monitor_id, kind, payload]),
  )
  use _ <- result.try(
    case
      revision >= 1
      && occurred_at >= 0
      && occurred_at <= maximum_safe_integer
      && list.contains(
        ["definition", "disabled", "evaluation", "notification"],
        kind,
      )
      && list.contains(["private", "review_visible", "exportable"], privacy)
    {
      True -> Ok(Nil)
      False -> Error(InvalidEvent)
    },
  )
  let assert Ok(payload_digest) = hash.text(payload)
  let payload_hash = identity.sha256_value(payload_digest)
  let semantic =
    event_semantic_json(
      revision,
      event_id,
      idempotency_key,
      monitor_id,
      kind,
      occurred_at,
      privacy,
      parent,
      payload,
      payload_hash,
    )
  let assert Ok(canonical_digest) = semantic |> json.to_string |> hash.text
  Ok(Event(
    revision,
    event_id,
    idempotency_key,
    monitor_id,
    kind,
    occurred_at,
    privacy,
    parent,
    payload,
    payload_hash,
    identity.sha256_value(canonical_digest),
  ))
}

fn event_semantic_json(
  revision: Int,
  event_id: String,
  idempotency_key: String,
  monitor_id: String,
  kind: String,
  occurred_at: Int,
  privacy: String,
  parent: Option(String),
  payload: String,
  payload_hash: String,
) -> json.Json {
  json.object([
    #("schemaVersion", json.int(1)),
    #("revision", json.int(revision)),
    #("eventId", json.string(event_id)),
    #("idempotencyKey", json.string(idempotency_key)),
    #("monitorId", json.string(monitor_id)),
    #("kind", json.string(kind)),
    #("occurredAtUnixMilliseconds", json.int(occurred_at)),
    #("privacy", json.string(privacy)),
    #("parentEventId", json.nullable(parent, json.string)),
    #("payload", json.string(payload)),
    #("payloadSha256", json.string(payload_hash)),
  ])
}

fn event_json(value: Event) -> json.Json {
  json.object([
    #(
      "event",
      event_semantic_json(
        value.revision,
        value.event_id,
        value.idempotency_key,
        value.monitor_id,
        value.kind,
        value.occurred_at_unix_ms,
        value.privacy,
        value.parent_event_id,
        value.payload,
        value.payload_hash,
      ),
    ),
    #("canonicalContentHash", json.string(value.canonical_hash)),
  ])
}

fn encode_event(value: Event) -> String {
  value |> event_json |> json.to_string
}

fn decode_lines(
  lines: List(String),
  state: State,
  line: Int,
) -> Result(State, AlertError) {
  case lines {
    [] -> Ok(state)
    ["", ..] -> Error(InvalidJournal(line))
    [encoded, ..rest] ->
      case json.parse(encoded, event_decoder()) {
        Error(_) -> Error(InvalidJournal(line))
        Ok(#(event, expected_hash)) ->
          case
            event.revision == state.revision + 1
            && event.canonical_hash == expected_hash
          {
            False -> Error(InvalidJournal(line))
            True ->
              case validate_replayed_event(state, event) {
                Error(_) -> Error(InvalidJournal(line))
                Ok(Nil) ->
                  case append(state, event) {
                    Ok(#(next, Stored(_))) -> decode_lines(rest, next, line + 1)
                    _ -> Error(InvalidJournal(line))
                  }
              }
          }
      }
  }
}

fn validate_replayed_event(
  state: State,
  event: Event,
) -> Result(Nil, AlertError) {
  case event.kind {
    "definition" -> {
      use definition <- result.try(parse_definition(event.payload))
      use _ <- result.try(validate_definition(definition))
      use _ <- result.try(validate_definition_lineage(state, definition))
      case
        definition.monitor_id == event.monitor_id,
        definition.parent_event_id == event.parent_event_id
      {
        True, True -> Ok(Nil)
        _, _ -> Error(InvalidEvent)
      }
    }
    "disabled" -> {
      use record <- result.try(
        json.parse(event.payload, disabled_record_decoder())
        |> result.map_error(fn(_) { InvalidEvent }),
      )
      let #(monitor_id, reason, definition_event_id) = record
      use _ <- result.try(
        validate_texts([monitor_id, reason, definition_event_id]),
      )
      use definition <- result.try(current_definition_event(state, monitor_id))
      case
        monitor_id == event.monitor_id,
        event.parent_event_id == Some(definition_event_id),
        definition.event_id == definition_event_id
      {
        True, True, True -> Ok(Nil)
        _, _, _ -> Error(InvalidEvent)
      }
    }
    "evaluation" -> {
      use record <- result.try(
        json.parse(event.payload, evaluation_record_decoder())
        |> result.map_error(fn(_) { InvalidEvent }),
      )
      use definition_event <- result.try(current_definition_event(
        state,
        record.monitor_id,
      ))
      let assert Ok(definition) = parse_definition(definition_event.payload)
      use _ <- result.try(validate_evaluation_record(record, definition))
      use _ <- result.try(case is_disabled(state, record.monitor_id) {
        True -> Error(MonitorDisabled(record.monitor_id))
        False -> Ok(Nil)
      })
      case
        record.monitor_id == event.monitor_id,
        event.parent_event_id == Some(record.definition_event_id),
        definition_event.event_id == record.definition_event_id,
        definition_event.payload_hash == record.definition_content_hash
      {
        True, True, True, True -> Ok(Nil)
        _, _, _, _ -> Error(InvalidEvent)
      }
    }
    "notification" -> {
      use record <- result.try(
        json.parse(event.payload, notification_record_decoder())
        |> result.map_error(fn(_) { InvalidEvent }),
      )
      use _ <- result.try(
        case
          record.monitor_id == event.monitor_id && event.parent_event_id == None
        {
          True -> Ok(Nil)
          False -> Error(InvalidEvent)
        },
      )
      use _ <- result.try(
        validate_texts([
          record.monitor_id,
          record.match_id,
          record.authorization_id,
          record.channel,
          record.destination_ref,
          record.status,
          record.provider_receipt,
        ]),
      )
      use _ <- result.try(case record.destination_privacy {
        "opaque_reference_only" -> Ok(Nil)
        _ -> Error(InvalidEvent)
      })
      authorize_notification(
        state,
        record.monitor_id,
        record.match_id,
        record.authorization_id,
        record.channel,
        record.destination_ref,
        record.attempt,
      )
    }
    _ -> Error(InvalidEvent)
  }
}

fn validate_evaluation_record(
  record: EvaluationRecord,
  definition: Definition,
) -> Result(Nil, AlertError) {
  use _ <- result.try(
    validate_texts([
      record.batch_id, record.monitor_id, record.definition_event_id,
    ]),
  )
  use _ <- result.try(validate_receipt(
    record.definition_content_hash,
    "evaluation_definition_content_hash",
  ))
  use _ <- result.try(validate_receipt(
    record.source_batch_sha256,
    "evaluation_source_batch_sha256",
  ))
  let actual_matches =
    record.results
    |> list.filter(fn(value) { value.result == "matched" })
    |> list.length
  use _ <- result.try(
    case
      safe_integer(record.evaluated_at_unix_ms)
      && record.observation_count == list.length(record.results)
      && record.observation_count >= 0
      && record.observation_count <= definition.budgets.max_events_per_batch
      && record.match_count == actual_matches
      && record.match_count >= 0
      && record.match_count <= definition.budgets.max_matches_per_batch
      && list.length(record.source_receipts) >= 1
      && record.silence_meaning
      == "no_supplied_observation_matched_not_all_clear"
    {
      True -> Ok(Nil)
      False -> Error(InvalidEvent)
    },
  )
  use _ <- result.try(unique(
    list.map(record.results, fn(value) { value.observation_id }),
    "evaluation_observation_id",
  ))
  use _ <- result.try(
    list.try_each(record.source_receipts, fn(value) {
      validate_receipt(value, "evaluation_source_receipt")
    }),
  )
  list.try_each(record.results, fn(value) {
    validate_evaluation_result(value, definition)
  })
}

fn validate_evaluation_result(
  value: EvaluationResult,
  definition: Definition,
) -> Result(Nil, AlertError) {
  use _ <- result.try(
    validate_texts([
      value.observation_id,
      value.event_identity,
      value.result,
      value.reason,
      value.predicate_kind,
    ]),
  )
  use _ <- result.try(validate_receipt(
    value.content_hash,
    "evaluation_result_content_hash",
  ))
  use _ <- result.try(case value.corrects {
    Some(id) -> validate_texts([id])
    None -> Ok(Nil)
  })
  use _ <- result.try(
    case
      list.contains(
        [
          "matched",
          "no_match",
          "cannot_evaluate",
          "duplicate_suppressed",
          "cooldown_suppressed",
          "match_budget_suppressed",
          "error",
        ],
        value.result,
      )
      && value.predicate_kind == definition.predicate.kind
    {
      True -> Ok(Nil)
      False -> Error(InvalidEvent)
    },
  )
  let expected_match_id =
    definition.monitor_id
    <> ":"
    <> value.observation_id
    <> ":v"
    <> int.to_string(definition.version)
  case value.result, value.match_id {
    "matched", Some(id) if id == expected_match_id -> Ok(Nil)
    "matched", _ -> Error(InvalidEvent)
    _, None -> Ok(Nil)
    _, Some(_) -> Error(InvalidEvent)
  }
}

fn event_decoder() -> decode.Decoder(#(Event, String)) {
  use fields <- decode.field("event", event_fields_decoder())
  use expected <- decode.field("canonicalContentHash", decode.string)
  let #(
    revision,
    event_id,
    idempotency,
    monitor_id,
    kind,
    occurred_at,
    privacy,
    parent,
    payload,
    payload_hash,
  ) = fields
  case
    new_event(
      revision,
      event_id,
      idempotency,
      monitor_id,
      kind,
      occurred_at,
      privacy,
      parent,
      payload,
    )
  {
    Ok(event) ->
      case event.payload_hash == payload_hash {
        True -> decode.success(#(event, expected))
        False -> decode.failure(#(placeholder_event(), ""), "payload hash")
      }
    Error(_) -> decode.failure(#(placeholder_event(), ""), "event")
  }
}

fn event_fields_decoder() -> decode.Decoder(
  #(
    Int,
    String,
    String,
    String,
    String,
    Int,
    String,
    Option(String),
    String,
    String,
  ),
) {
  use schema <- decode.field("schemaVersion", decode.int)
  use revision <- decode.field("revision", decode.int)
  use event_id <- decode.field("eventId", decode.string)
  use idempotency <- decode.field("idempotencyKey", decode.string)
  use monitor_id <- decode.field("monitorId", decode.string)
  use kind <- decode.field("kind", decode.string)
  use occurred <- decode.field("occurredAtUnixMilliseconds", decode.int)
  use privacy <- decode.field("privacy", decode.string)
  use parent <- decode.optional_field(
    "parentEventId",
    None,
    decode.optional(decode.string),
  )
  use payload <- decode.field("payload", decode.string)
  use payload_hash <- decode.field("payloadSha256", decode.string)
  case schema == 1 {
    True ->
      decode.success(#(
        revision,
        event_id,
        idempotency,
        monitor_id,
        kind,
        occurred,
        privacy,
        parent,
        payload,
        payload_hash,
      ))
    False -> decode.failure(#(0, "", "", "", "", 0, "", None, "", ""), "schema")
  }
}

fn placeholder_event() -> Event {
  Event(0, "", "", "", "", 0, "", None, "", "", "")
}

fn parse_definition(input: String) -> Result(Definition, AlertError) {
  json.parse(input, definition_decoder())
  |> result.map_error(fn(_) { InvalidJson })
}

fn parse_batch(input: String) -> Result(Batch, AlertError) {
  json.parse(input, batch_decoder()) |> result.map_error(fn(_) { InvalidJson })
}

fn definition_json(value: Definition, content_hash: String) -> json.Json {
  let Scope(kind, track, listings, mic, sources, event_kinds, portfolio_receipt) =
    value.scope
  let Predicate(predicate_kind, field, operator, predicate_value) =
    value.predicate
  let Temporal(freshness, start_at, end_at) = value.temporal
  let Dedupe(dedupe_kind, window, cooldown, cooldown_scope) = value.dedupe
  let Budgets(max_events, max_matches, max_failures) = value.budgets
  let NotificationAuthorization(
    authorized,
    authorization_id,
    channel,
    destination,
    attempts,
  ) = value.authorization
  json.object([
    #("monitorId", json.string(value.monitor_id)),
    #("version", json.int(value.version)),
    #("contentHash", json.string(content_hash)),
    #("ownerKind", json.string(value.owner_kind)),
    #("ownerId", json.string(value.owner_id)),
    #(
      "scope",
      json.object([
        #("kind", json.string(kind)),
        #("track", json.string(track)),
        #("listingIds", json.array(listings, json.string)),
        #("mic", json.string(mic)),
        #("sourceScope", json.array(sources, json.string)),
        #("eventKinds", json.array(event_kinds, json.string)),
        #("portfolioReceipt", json.nullable(portfolio_receipt, json.string)),
      ]),
    ),
    #(
      "predicate",
      json.object([
        #("kind", json.string(predicate_kind)),
        #("field", json.string(field)),
        #("operator", json.string(operator)),
        #("value", json.string(predicate_value)),
      ]),
    ),
    #(
      "temporal",
      json.object([
        #("freshnessCutoffSeconds", json.int(freshness)),
        #("startAtUnixMilliseconds", json.int(start_at)),
        #("endAtUnixMilliseconds", json.nullable(end_at, json.int)),
      ]),
    ),
    #(
      "dedupe",
      json.object([
        #("kind", json.string(dedupe_kind)),
        #("windowSeconds", json.int(window)),
        #("cooldownSeconds", json.int(cooldown)),
        #("scope", json.string(cooldown_scope)),
      ]),
    ),
    #(
      "budgets",
      json.object([
        #("maxEventsPerBatch", json.int(max_events)),
        #("maxMatchesPerBatch", json.int(max_matches)),
        #("maxConsecutiveFailures", json.int(max_failures)),
      ]),
    ),
    #(
      "notificationAuthorization",
      json.object([
        #("authorized", json.bool(authorized)),
        #("authorizationId", json.string(authorization_id)),
        #("channel", json.string(channel)),
        #("destinationRef", json.string(destination)),
        #("maximumAttempts", json.int(attempts)),
      ]),
    ),
    #("retentionPolicy", json.string(value.retention_policy)),
    #("parentEventId", json.nullable(value.parent_event_id, json.string)),
    #(
      "sourceEntitlementReceipts",
      json.array(value.source_entitlement_receipts, json.string),
    ),
  ])
}

fn definition_decoder() -> decode.Decoder(Definition) {
  use schema <- decode.field("schemaVersion", decode.int)
  use contract <- decode.field("contractId", decode.string)
  use monitor_id <- decode.field("monitorId", decode.string)
  use version <- decode.field("version", decode.int)
  use owner_kind <- decode.field("ownerKind", decode.string)
  use owner_id <- decode.field("ownerId", decode.string)
  use scope <- decode.field("scope", scope_decoder())
  use predicate <- decode.field("predicate", predicate_decoder())
  use temporal <- decode.field("temporal", temporal_decoder())
  use dedupe <- decode.field("dedupe", dedupe_decoder())
  use budgets <- decode.field("budgets", budgets_decoder())
  use authorization <- decode.field(
    "notificationAuthorization",
    authorization_decoder(),
  )
  use retention <- decode.field("retentionPolicy", decode.string)
  use parent <- decode.optional_field(
    "parentEventId",
    None,
    decode.optional(decode.string),
  )
  use entitlements <- decode.field(
    "sourceEntitlementReceipts",
    decode.list(of: decode.string),
  )
  decode.success(Definition(
    schema,
    contract,
    monitor_id,
    version,
    owner_kind,
    owner_id,
    scope,
    predicate,
    temporal,
    dedupe,
    budgets,
    authorization,
    retention,
    parent,
    entitlements,
  ))
}

fn scope_decoder() -> decode.Decoder(Scope) {
  use kind <- decode.field("kind", decode.string)
  use track <- decode.field("track", decode.string)
  use listings <- decode.field("listingIds", decode.list(of: decode.string))
  use mic <- decode.field("mic", decode.string)
  use sources <- decode.field("sourceScope", decode.list(of: decode.string))
  use events <- decode.field("eventKinds", decode.list(of: decode.string))
  use portfolio <- decode.optional_field(
    "portfolioReceipt",
    None,
    decode.optional(decode.string),
  )
  decode.success(Scope(kind, track, listings, mic, sources, events, portfolio))
}

fn predicate_decoder() -> decode.Decoder(Predicate) {
  use kind <- decode.field("kind", decode.string)
  use field <- decode.field("field", decode.string)
  use operator <- decode.field("operator", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(Predicate(kind, field, operator, value))
}

fn temporal_decoder() -> decode.Decoder(Temporal) {
  use freshness <- decode.field("freshnessCutoffSeconds", decode.int)
  use start <- decode.field("startAtUnixMilliseconds", decode.int)
  use end <- decode.optional_field(
    "endAtUnixMilliseconds",
    None,
    decode.optional(decode.int),
  )
  decode.success(Temporal(freshness, start, end))
}

fn dedupe_decoder() -> decode.Decoder(Dedupe) {
  use kind <- decode.field("kind", decode.string)
  use window <- decode.field("windowSeconds", decode.int)
  use cooldown <- decode.field("cooldownSeconds", decode.int)
  use scope <- decode.field("scope", decode.string)
  decode.success(Dedupe(kind, window, cooldown, scope))
}

fn budgets_decoder() -> decode.Decoder(Budgets) {
  use events <- decode.field("maxEventsPerBatch", decode.int)
  use matches <- decode.field("maxMatchesPerBatch", decode.int)
  use failures <- decode.field("maxConsecutiveFailures", decode.int)
  decode.success(Budgets(events, matches, failures))
}

fn authorization_decoder() -> decode.Decoder(NotificationAuthorization) {
  use authorized <- decode.field("authorized", decode.bool)
  use authorization_id <- decode.field("authorizationId", decode.string)
  use channel <- decode.field("channel", decode.string)
  use destination <- decode.field("destinationRef", decode.string)
  use attempts <- decode.field("maximumAttempts", decode.int)
  decode.success(NotificationAuthorization(
    authorized,
    authorization_id,
    channel,
    destination,
    attempts,
  ))
}

fn notification_record_decoder() -> decode.Decoder(NotificationRecord) {
  use monitor_id <- decode.field("monitorId", decode.string)
  use match_id <- decode.field("matchId", decode.string)
  use authorization_id <- decode.field("authorizationId", decode.string)
  use channel <- decode.field("channel", decode.string)
  use destination <- decode.field("destinationRef", decode.string)
  use attempt <- decode.field("attempt", decode.int)
  use status <- decode.field("status", decode.string)
  use provider_receipt <- decode.field("providerReceipt", decode.string)
  use destination_privacy <- decode.field("destinationPrivacy", decode.string)
  decode.success(NotificationRecord(
    monitor_id,
    match_id,
    authorization_id,
    channel,
    destination,
    attempt,
    status,
    provider_receipt,
    destination_privacy,
  ))
}

fn disabled_record_decoder() -> decode.Decoder(#(String, String, String)) {
  use monitor_id <- decode.field("monitorId", decode.string)
  use reason <- decode.field("reason", decode.string)
  use definition_event_id <- decode.field("definitionEventId", decode.string)
  decode.success(#(monitor_id, reason, definition_event_id))
}

fn evaluation_record_decoder() -> decode.Decoder(EvaluationRecord) {
  use batch_id <- decode.field("batchId", decode.string)
  use monitor_id <- decode.field("monitorId", decode.string)
  use definition_event_id <- decode.field("definitionEventId", decode.string)
  use definition_hash <- decode.field("definitionContentHash", decode.string)
  use evaluated_at <- decode.field("evaluatedAtUnixMilliseconds", decode.int)
  use observation_count <- decode.field("observationCount", decode.int)
  use match_count <- decode.field("matchCount", decode.int)
  use results <- decode.field(
    "results",
    decode.list(of: evaluation_result_decoder()),
  )
  use source_receipts <- decode.field(
    "sourceReceipts",
    decode.list(of: decode.string),
  )
  use source_batch_sha256 <- decode.field("sourceBatchSha256", decode.string)
  use silence_meaning <- decode.field("silenceMeaning", decode.string)
  decode.success(EvaluationRecord(
    batch_id,
    monitor_id,
    definition_event_id,
    definition_hash,
    evaluated_at,
    observation_count,
    match_count,
    results,
    source_receipts,
    source_batch_sha256,
    silence_meaning,
  ))
}

fn evaluation_result_decoder() -> decode.Decoder(EvaluationResult) {
  use observation_id <- decode.field("observationId", decode.string)
  use event_identity <- decode.field("eventIdentity", decode.string)
  use content_hash <- decode.field("contentHash", decode.string)
  use corrects <- decode.optional_field(
    "corrects",
    None,
    decode.optional(decode.string),
  )
  use result_name <- decode.field("result", decode.string)
  use reason <- decode.field("reason", decode.string)
  use match_id <- decode.optional_field(
    "matchId",
    None,
    decode.optional(decode.string),
  )
  use predicate_kind <- decode.field("predicateKind", decode.string)
  decode.success(EvaluationResult(
    observation_id,
    event_identity,
    content_hash,
    corrects,
    result_name,
    reason,
    match_id,
    predicate_kind,
  ))
}

fn batch_decoder() -> decode.Decoder(Batch) {
  use schema <- decode.field("schemaVersion", decode.int)
  use contract <- decode.field("contractId", decode.string)
  use batch_id <- decode.field("batchId", decode.string)
  use monitor_id <- decode.field("monitorId", decode.string)
  use evaluated <- decode.field("evaluatedAtUnixMilliseconds", decode.int)
  use observations <- decode.field(
    "observations",
    decode.list(of: observation_decoder()),
  )
  use receipts <- decode.field("sourceReceipts", decode.list(of: decode.string))
  decode.success(Batch(
    schema,
    contract,
    batch_id,
    monitor_id,
    evaluated,
    observations,
    receipts,
  ))
}

fn observation_decoder() -> decode.Decoder(Observation) {
  use id <- decode.field("observationId", decode.string)
  use identity <- decode.field("eventIdentity", decode.string)
  use content_hash <- decode.field("contentHash", decode.string)
  use observed <- decode.field("observedAtUnixMilliseconds", decode.int)
  use knowledge <- decode.field("knowledgeAtUnixMilliseconds", decode.int)
  use corrects <- decode.optional_field(
    "corrects",
    None,
    decode.optional(decode.string),
  )
  use fields <- decode.field("fields", decode.list(of: field_decoder()))
  decode.success(Observation(
    id,
    identity,
    content_hash,
    observed,
    knowledge,
    corrects,
    fields,
  ))
}

fn field_decoder() -> decode.Decoder(Field) {
  use name <- decode.field("name", decode.string)
  use state <- decode.field("state", decode.string)
  use value <- decode.optional_field(
    "value",
    None,
    decode.optional(decode.string),
  )
  decode.success(Field(name, state, value))
}

fn validate_texts(values: List(String)) -> Result(Nil, AlertError) {
  case
    list.all(values, fn(value) {
      value != ""
      && string.trim(value) == value
      && string.length(value) <= 65_536
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidDefinition)
  }
}

fn validate_receipt(value: String, field: String) -> Result(Nil, AlertError) {
  case
    string.length(value) == 64
    && list.all(string.to_graphemes(value), fn(character) {
      string.contains("0123456789abcdef", character)
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidReceipt(field))
  }
}

fn unique(values: List(String), field: String) -> Result(Nil, AlertError) {
  case list.length(values) == list.length(list.unique(values)) {
    True -> Ok(Nil)
    False -> Error(InvalidReceipt("duplicate_" <> field))
  }
}

fn verify_hash(bytes: String, expected: String) -> Result(Nil, AlertError) {
  case hash.text(bytes) {
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
    Error(_) -> Error(ContentHashMismatch)
  }
}

fn end_after_start(end: Option(Int), start: Int) -> Bool {
  case end {
    None -> True
    Some(value) -> value >= start && value <= maximum_safe_integer
  }
}

fn safe_integer(value: Int) -> Bool {
  value >= 0 && value <= maximum_safe_integer
}
