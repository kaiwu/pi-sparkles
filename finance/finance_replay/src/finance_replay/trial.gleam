import finance_core/time.{type Instant}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/fact.{type Fact}
import finance_replay/wire
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type AuthorKind {
  Llm
  User
  Imported(source: String)
}

pub type Privacy {
  Private
  ResearchContext
  Exportable
}

pub type ParameterValue {
  ParameterValue(
    name: String,
    exact_value: String,
    author: AuthorKind,
    source_receipt: Fact(Sha256),
  )
}

pub opaque type Definition {
  Definition(
    trial_id: String,
    parent_trial_id: Option(String),
    batch_id: Option(String),
    run_definition_hash: Sha256,
    parameter_values: List(ParameterValue),
    trial_rationale: Fact(String),
    partition_ref: Sha256,
    model_refs: List(Sha256),
    seed: Fact(String),
    metric_refs: List(Sha256),
    budget_refs: List(Sha256),
    author_kind: AuthorKind,
    declared_time: Instant,
    privacy: Privacy,
    digest: Sha256,
  )
}

pub type Status {
  Completed
  Failed(reason: String)
  Cancelled(at: Instant, by: String)
  Truncated(reason: String)
  DuplicateOf(existing_trial_id: String)
  Unperformed(reason: String)
}

pub opaque type LedgerEvent {
  LedgerEvent(
    ledger_event_id: String,
    trial: Definition,
    status: Status,
    start_time: Instant,
    end_time: Fact(Instant),
    output_receipt_hashes: List(Sha256),
    error_facts: List(String),
    effect_receipt_hash: Sha256,
    idempotency_key: String,
    semantic_content_hash: Sha256,
    canonical_content_hash: Sha256,
  )
}

pub opaque type Ledger {
  Ledger(
    revision: Int,
    events_reversed: List(LedgerEvent),
    events_by_id: Dict(String, LedgerEvent),
    events_by_idempotency: Dict(String, LedgerEvent),
  )
}

pub type Counts {
  Counts(
    total: Int,
    completed: Int,
    failed: Int,
    cancelled: Int,
    truncated: Int,
    duplicate: Int,
    unperformed: Int,
  )
}

pub type AppendOutcome {
  Stored(event: LedgerEvent)
  AlreadyStored(event: LedgerEvent)
}

pub type TrialError {
  InvalidText(field: String)
  DuplicateParameter(String)
  DuplicateReceipt(field: String, hash: String)
  TooManyValues(field: String, received: Int, maximum: Int)
}

pub type LedgerError {
  DuplicateLedgerEventId(String)
  IdempotencyConflict(
    key: String,
    original_event_id: String,
    original_semantic_hash: String,
    received_semantic_hash: String,
  )
  RevisionExhausted
}

pub const maximum_values = 1000

pub const maximum_revision = 1_000_000

pub fn definition(
  trial_id: String,
  parent_trial_id: Option(String),
  batch_id: Option(String),
  run_definition_hash: Sha256,
  parameter_values: List(ParameterValue),
  trial_rationale: Fact(String),
  partition_ref: Sha256,
  model_refs: List(Sha256),
  seed: Fact(String),
  metric_refs: List(Sha256),
  budget_refs: List(Sha256),
  author_kind: AuthorKind,
  declared_time: Instant,
  privacy: Privacy,
) -> Result(Definition, TrialError) {
  use _ <- result.try(validate_text(trial_id, "trial_id"))
  use _ <- result.try(validate_optional_text(parent_trial_id, "parent_trial_id"))
  use _ <- result.try(validate_optional_text(batch_id, "batch_id"))
  use _ <- result.try(validate_author(author_kind))
  use _ <- result.try(validate_parameters(parameter_values, []))
  use _ <- result.try(validate_receipts("model_refs", model_refs, []))
  use _ <- result.try(validate_receipts("metric_refs", metric_refs, []))
  use _ <- result.try(validate_receipts("budget_refs", budget_refs, []))
  use _ <- result.try(validate_count("parameter_values", parameter_values))
  use _ <- result.try(validate_count("model_refs", model_refs))
  use _ <- result.try(validate_count("metric_refs", metric_refs))
  use _ <- result.try(validate_count("budget_refs", budget_refs))
  let payload =
    definition_payload(
      trial_id,
      parent_trial_id,
      batch_id,
      run_definition_hash,
      parameter_values,
      trial_rationale,
      partition_ref,
      model_refs,
      seed,
      metric_refs,
      budget_refs,
      author_kind,
      declared_time,
      privacy,
    )
  let assert Ok(digest) = payload |> json.to_string |> hash.text
  Ok(Definition(
    trial_id,
    parent_trial_id,
    batch_id,
    run_definition_hash,
    parameter_values,
    trial_rationale,
    partition_ref,
    model_refs,
    seed,
    metric_refs,
    budget_refs,
    author_kind,
    declared_time,
    privacy,
    digest,
  ))
}

pub fn ledger_event(
  ledger_event_id: String,
  trial: Definition,
  status: Status,
  start_time: Instant,
  end_time: Fact(Instant),
  output_receipt_hashes: List(Sha256),
  error_facts: List(String),
  effect_receipt_hash: Sha256,
  idempotency_key: String,
) -> Result(LedgerEvent, TrialError) {
  use _ <- result.try(validate_text(ledger_event_id, "ledger_event_id"))
  use _ <- result.try(validate_text(idempotency_key, "idempotency_key"))
  use _ <- result.try(validate_status(status))
  use _ <- result.try(
    validate_receipts("output_receipt_hashes", output_receipt_hashes, []),
  )
  use _ <- result.try(validate_texts(error_facts, "error_fact"))
  use _ <- result.try(validate_count(
    "output_receipt_hashes",
    output_receipt_hashes,
  ))
  use _ <- result.try(validate_count("error_facts", error_facts))
  let semantic_payload =
    ledger_semantic_payload(
      trial,
      status,
      start_time,
      end_time,
      output_receipt_hashes,
      error_facts,
      effect_receipt_hash,
    )
  let assert Ok(semantic_hash) = semantic_payload |> json.to_string |> hash.text
  let canonical_payload =
    ledger_payload(
      ledger_event_id,
      trial,
      status,
      start_time,
      end_time,
      output_receipt_hashes,
      error_facts,
      effect_receipt_hash,
      idempotency_key,
      semantic_hash,
    )
  let assert Ok(canonical_hash) =
    canonical_payload |> json.to_string |> hash.text
  Ok(LedgerEvent(
    ledger_event_id,
    trial,
    status,
    start_time,
    end_time,
    output_receipt_hashes,
    error_facts,
    effect_receipt_hash,
    idempotency_key,
    semantic_hash,
    canonical_hash,
  ))
}

pub fn empty() -> Ledger {
  Ledger(0, [], dict.new(), dict.new())
}

pub fn append(
  ledger: Ledger,
  new_event: LedgerEvent,
) -> Result(#(Ledger, AppendOutcome), LedgerError) {
  case dict.get(ledger.events_by_idempotency, new_event.idempotency_key) {
    Ok(existing) ->
      case existing.semantic_content_hash == new_event.semantic_content_hash {
        True -> Ok(#(ledger, AlreadyStored(existing)))
        False ->
          Error(IdempotencyConflict(
            new_event.idempotency_key,
            existing.ledger_event_id,
            identity.sha256_value(existing.semantic_content_hash),
            identity.sha256_value(new_event.semantic_content_hash),
          ))
      }
    Error(_) ->
      case dict.has_key(ledger.events_by_id, new_event.ledger_event_id) {
        True -> Error(DuplicateLedgerEventId(new_event.ledger_event_id))
        False ->
          case ledger.revision >= maximum_revision {
            True -> Error(RevisionExhausted)
            False ->
              Ok(#(
                Ledger(
                  ledger.revision + 1,
                  [new_event, ..ledger.events_reversed],
                  dict.insert(
                    ledger.events_by_id,
                    new_event.ledger_event_id,
                    new_event,
                  ),
                  dict.insert(
                    ledger.events_by_idempotency,
                    new_event.idempotency_key,
                    new_event,
                  ),
                ),
                Stored(new_event),
              ))
          }
      }
  }
}

pub fn append_many(
  ledger: Ledger,
  events: List(LedgerEvent),
) -> Result(#(Ledger, List(AppendOutcome)), LedgerError) {
  append_many_loop(events, ledger, [])
}

fn append_many_loop(
  remaining: List(LedgerEvent),
  current: Ledger,
  reversed: List(AppendOutcome),
) -> Result(#(Ledger, List(AppendOutcome)), LedgerError) {
  case remaining {
    [] -> Ok(#(current, list.reverse(reversed)))
    [next, ..rest] -> {
      use #(next_ledger, outcome) <- result.try(append(current, next))
      append_many_loop(rest, next_ledger, [outcome, ..reversed])
    }
  }
}

pub fn counts(value: Ledger) -> Counts {
  count_loop(value.events_reversed, Counts(0, 0, 0, 0, 0, 0, 0))
}

fn count_loop(values: List(LedgerEvent), counts: Counts) -> Counts {
  case values {
    [] -> counts
    [next, ..rest] -> {
      let Counts(
        total,
        completed,
        failed,
        cancelled,
        truncated,
        duplicate,
        unperformed,
      ) = counts
      let next_counts = case next.status {
        Completed ->
          Counts(
            total + 1,
            completed + 1,
            failed,
            cancelled,
            truncated,
            duplicate,
            unperformed,
          )
        Failed(_) ->
          Counts(
            total + 1,
            completed,
            failed + 1,
            cancelled,
            truncated,
            duplicate,
            unperformed,
          )
        Cancelled(_, _) ->
          Counts(
            total + 1,
            completed,
            failed,
            cancelled + 1,
            truncated,
            duplicate,
            unperformed,
          )
        Truncated(_) ->
          Counts(
            total + 1,
            completed,
            failed,
            cancelled,
            truncated + 1,
            duplicate,
            unperformed,
          )
        DuplicateOf(_) ->
          Counts(
            total + 1,
            completed,
            failed,
            cancelled,
            truncated,
            duplicate + 1,
            unperformed,
          )
        Unperformed(_) ->
          Counts(
            total + 1,
            completed,
            failed,
            cancelled,
            truncated,
            duplicate,
            unperformed + 1,
          )
      }
      count_loop(rest, next_counts)
    }
  }
}

/// All caller-supplied parameter values remain visible. This function does not
/// rank, select, or label any value.
pub fn parameter_values_seen(value: Ledger) -> List(ParameterValue) {
  value
  |> events
  |> list.flat_map(fn(value) { value.trial.parameter_values })
}

pub fn cursor(value: Ledger) -> Sha256 {
  let payload =
    json.object([
      #("revision", json.int(value.revision)),
      #(
        "ordered_ledger_event_hashes",
        json.array(events(value), fn(value) {
          wire.sha_json(value.canonical_content_hash)
        }),
      ),
    ])
  let assert Ok(value_hash) = payload |> json.to_string |> hash.text
  value_hash
}

pub fn definition_json(value: Definition) -> json.Json {
  json.object([
    #(
      "payload",
      definition_payload(
        value.trial_id,
        value.parent_trial_id,
        value.batch_id,
        value.run_definition_hash,
        value.parameter_values,
        value.trial_rationale,
        value.partition_ref,
        value.model_refs,
        value.seed,
        value.metric_refs,
        value.budget_refs,
        value.author_kind,
        value.declared_time,
        value.privacy,
      ),
    ),
    #("canonical_content_hash", wire.sha_json(value.digest)),
  ])
}

pub fn ledger_event_json(value: LedgerEvent) -> json.Json {
  json.object([
    #(
      "payload",
      ledger_payload(
        value.ledger_event_id,
        value.trial,
        value.status,
        value.start_time,
        value.end_time,
        value.output_receipt_hashes,
        value.error_facts,
        value.effect_receipt_hash,
        value.idempotency_key,
        value.semantic_content_hash,
      ),
    ),
    #("canonical_content_hash", wire.sha_json(value.canonical_content_hash)),
  ])
}

fn definition_payload(
  trial_id: String,
  parent_trial_id: Option(String),
  batch_id: Option(String),
  run_definition_hash: Sha256,
  parameter_values: List(ParameterValue),
  trial_rationale: Fact(String),
  partition_ref: Sha256,
  model_refs: List(Sha256),
  seed: Fact(String),
  metric_refs: List(Sha256),
  budget_refs: List(Sha256),
  author_kind: AuthorKind,
  declared_time: Instant,
  privacy: Privacy,
) -> json.Json {
  json.object([
    #("schema", json.string("finance_replay_trial_definition")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("trial_id", json.string(trial_id)),
    #("parent_trial_id", json.nullable(parent_trial_id, json.string)),
    #("batch_id", json.nullable(batch_id, json.string)),
    #("run_definition_hash", wire.sha_json(run_definition_hash)),
    #("parameter_values", json.array(parameter_values, parameter_json)),
    #("trial_rationale", fact.to_json(trial_rationale, json.string)),
    #("partition_ref", wire.sha_json(partition_ref)),
    #("model_refs", json.array(model_refs, wire.sha_json)),
    #("seed", fact.to_json(seed, json.string)),
    #("metric_refs", json.array(metric_refs, wire.sha_json)),
    #("budget_refs", json.array(budget_refs, wire.sha_json)),
    #("author_kind", author_json(author_kind)),
    #("declared_time", wire.instant_json(declared_time)),
    #("privacy", privacy |> privacy_name |> json.string),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

fn parameter_json(value: ParameterValue) -> json.Json {
  let ParameterValue(name, exact_value, author, source) = value
  json.object([
    #("name", json.string(name)),
    #("exact_value", json.string(exact_value)),
    #("author", author_json(author)),
    #("source_receipt", fact.to_json(source, wire.sha_json)),
  ])
}

fn author_json(value: AuthorKind) -> json.Json {
  case value {
    Llm -> json.object([#("kind", json.string("llm"))])
    User -> json.object([#("kind", json.string("user"))])
    Imported(source) ->
      json.object([
        #("kind", json.string("imported")),
        #("source", json.string(source)),
      ])
  }
}

fn ledger_semantic_payload(
  trial: Definition,
  status: Status,
  start_time: Instant,
  end_time: Fact(Instant),
  output_receipt_hashes: List(Sha256),
  error_facts: List(String),
  effect_receipt_hash: Sha256,
) -> json.Json {
  json.object([
    #("trial_definition_hash", wire.sha_json(trial.digest)),
    #("status", status_json(status)),
    #("start_time", wire.instant_json(start_time)),
    #("end_time", fact.to_json(end_time, wire.instant_json)),
    #("output_receipt_hashes", json.array(output_receipt_hashes, wire.sha_json)),
    #("error_facts", json.array(error_facts, json.string)),
    #("effect_receipt_hash", wire.sha_json(effect_receipt_hash)),
  ])
}

fn ledger_payload(
  ledger_event_id: String,
  trial: Definition,
  status: Status,
  start_time: Instant,
  end_time: Fact(Instant),
  output_receipt_hashes: List(Sha256),
  error_facts: List(String),
  effect_receipt_hash: Sha256,
  idempotency_key: String,
  semantic_content_hash: Sha256,
) -> json.Json {
  let semantic =
    ledger_semantic_payload(
      trial,
      status,
      start_time,
      end_time,
      output_receipt_hashes,
      error_facts,
      effect_receipt_hash,
    )
  json.object([
    #("schema", json.string("finance_replay_trial_ledger_event")),
    #("schema_version", json.int(1)),
    #("ledger_event_id", json.string(ledger_event_id)),
    #("trial_event", semantic),
    #("idempotency_key", json.string(idempotency_key)),
    #("semantic_content_hash", wire.sha_json(semantic_content_hash)),
  ])
}

fn status_json(value: Status) -> json.Json {
  case value {
    Completed -> json.object([#("state", json.string("completed"))])
    Failed(reason) -> status_reason_json("failed", reason)
    Truncated(reason) -> status_reason_json("truncated", reason)
    Unperformed(reason) -> status_reason_json("unperformed", reason)
    DuplicateOf(existing) ->
      json.object([
        #("state", json.string("duplicate_of")),
        #("existing_trial_id", json.string(existing)),
      ])
    Cancelled(at, by) ->
      json.object([
        #("state", json.string("cancelled")),
        #("at", wire.instant_json(at)),
        #("by", json.string(by)),
      ])
  }
}

fn status_reason_json(state: String, reason: String) -> json.Json {
  json.object([
    #("state", json.string(state)),
    #("reason", json.string(reason)),
  ])
}

fn validate_parameters(
  values: List(ParameterValue),
  seen: List(String),
) -> Result(Nil, TrialError) {
  case values {
    [] -> Ok(Nil)
    [ParameterValue(name, exact_value, author, _), ..rest] -> {
      use _ <- result.try(validate_text(name, "parameter_name"))
      use _ <- result.try(validate_text(exact_value, "parameter_value"))
      use _ <- result.try(validate_author(author))
      case list.contains(seen, name) {
        True -> Error(DuplicateParameter(name))
        False -> validate_parameters(rest, [name, ..seen])
      }
    }
  }
}

fn validate_author(value: AuthorKind) -> Result(Nil, TrialError) {
  case value {
    Imported(source) -> validate_text(source, "import_source")
    _ -> Ok(Nil)
  }
}

fn validate_status(value: Status) -> Result(Nil, TrialError) {
  case value {
    Completed -> Ok(Nil)
    Failed(reason) -> validate_text(reason, "failure_reason")
    Truncated(reason) -> validate_text(reason, "truncation_reason")
    Unperformed(reason) -> validate_text(reason, "unperformed_reason")
    DuplicateOf(existing) -> validate_text(existing, "existing_trial_id")
    Cancelled(_, by) -> validate_text(by, "cancelled_by")
  }
}

fn validate_optional_text(
  value: Option(String),
  field: String,
) -> Result(Nil, TrialError) {
  case value {
    None -> Ok(Nil)
    Some(value) -> validate_text(value, field)
  }
}

fn validate_text(value: String, field: String) -> Result(Nil, TrialError) {
  case wire.valid_text(value, 4096) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn validate_texts(
  values: List(String),
  field: String,
) -> Result(Nil, TrialError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(validate_text(value, field))
      validate_texts(rest, field)
    }
  }
}

fn validate_receipts(
  field: String,
  values: List(Sha256),
  seen: List(String),
) -> Result(Nil, TrialError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      let text = identity.sha256_value(value)
      case list.contains(seen, text) {
        True -> Error(DuplicateReceipt(field, text))
        False -> validate_receipts(field, rest, [text, ..seen])
      }
    }
  }
}

fn validate_count(field: String, values: List(a)) -> Result(Nil, TrialError) {
  let count = list.length(values)
  case count > maximum_values {
    True -> Error(TooManyValues(field, count, maximum_values))
    False -> Ok(Nil)
  }
}

fn privacy_name(value: Privacy) -> String {
  case value {
    Private -> "private"
    ResearchContext -> "research_context"
    Exportable -> "exportable"
  }
}

pub fn definition_hash(value: Definition) -> Sha256 {
  value.digest
}

pub fn trial_id(value: Definition) -> String {
  value.trial_id
}

pub fn event_id(value: LedgerEvent) -> String {
  value.ledger_event_id
}

pub fn revision(value: Ledger) -> Int {
  value.revision
}

pub fn events(value: Ledger) -> List(LedgerEvent) {
  list.reverse(value.events_reversed)
}
