import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode as dynamic_decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pi_sparkles_day_workbench/decode as input_decode

pub const maximum_transitions = 100

const maximum_payload_bytes = 20_000

const maximum_references = 50

pub type Stage {
  Preparation
  Acquiring
  Ready
  PlanDeclared
  Monitoring
  EntryIntent
  ExitIntent
  Closeout
  Review
}

pub type Record {
  Record(
    revision: Int,
    transition_id: String,
    idempotency_key: String,
    event_kind: String,
    origin: String,
    occurred_at_unix_ms: Int,
    payload_hash: String,
    evidence_references: List(String),
    execution_receipt_references: List(String),
    from_stage: Stage,
    to_stage: Stage,
  )
}

pub type State {
  State(
    workflow_id: String,
    branch_id: String,
    revision: Int,
    stage: Stage,
    records: List(Record),
  )
}

pub fn transition(input: input_decode.TransitionInput) -> Result(Json, String) {
  let input_decode.TransitionInput(
    current_payload,
    current_hash,
    workflow_id,
    branch_id,
    transition_id,
    idempotency_key,
    event_kind,
    origin,
    occurred_at,
    payload,
    payload_hash,
    evidence_references,
    execution_references,
  ) = input
  use _ <- result.try(validate_text("workflowId", workflow_id, 200))
  use _ <- result.try(validate_text("branchId", branch_id, 200))
  use _ <- result.try(validate_text("transitionId", transition_id, 200))
  use _ <- result.try(validate_text("idempotencyKey", idempotency_key, 200))
  use _ <- result.try(case occurred_at >= 0 {
    True -> Ok(Nil)
    False -> Error("occurredAtUnixMilliseconds must be non-negative")
  })
  use _ <- result.try(case string.byte_size(payload) <= maximum_payload_bytes {
    True -> Ok(Nil)
    False -> Error("transition payload exceeds 20000 bytes")
  })
  use normalized_payload_hash <- result.try(verify_hash(
    "payloadHash",
    payload,
    payload_hash,
  ))
  use _ <- result.try(validate_references(
    "evidenceReferences",
    evidence_references,
  ))
  use _ <- result.try(validate_references(
    "executionReceiptReferences",
    execution_references,
  ))
  use prior <- result.try(decode_prior(
    current_payload,
    current_hash,
    workflow_id,
    branch_id,
    event_kind,
  ))
  case prior {
    None ->
      initialize(
        workflow_id,
        branch_id,
        transition_id,
        idempotency_key,
        event_kind,
        origin,
        occurred_at,
        normalized_payload_hash,
        evidence_references,
        execution_references,
      )
    Some(state) ->
      advance(
        state,
        transition_id,
        idempotency_key,
        event_kind,
        origin,
        occurred_at,
        normalized_payload_hash,
        evidence_references,
        execution_references,
      )
  }
}

pub fn encode(state: State) -> String {
  state_json(state) |> json.to_string
}

fn initialize(
  workflow_id: String,
  branch_id: String,
  transition_id: String,
  idempotency_key: String,
  event_kind: String,
  origin: String,
  occurred_at: Int,
  payload_hash: String,
  evidence: List(String),
  execution: List(String),
) -> Result(Json, String) {
  use _ <- result.try(case event_kind == "initialize_preparation" {
    True -> Ok(Nil)
    False -> Error("a new workflow requires initialize_preparation")
  })
  use _ <- result.try(validate_origin(event_kind, origin))
  let record =
    Record(
      1,
      transition_id,
      idempotency_key,
      event_kind,
      origin,
      occurred_at,
      payload_hash,
      evidence,
      execution,
      Preparation,
      Preparation,
    )
  output(State(workflow_id, branch_id, 1, Preparation, [record]), False, record)
}

fn advance(
  state: State,
  transition_id: String,
  idempotency_key: String,
  event_kind: String,
  origin: String,
  occurred_at: Int,
  payload_hash: String,
  evidence: List(String),
  execution: List(String),
) -> Result(Json, String) {
  use _ <- result.try(case list.length(state.records) < maximum_transitions {
    True -> Ok(Nil)
    False -> Error("workflow transition count reached 100")
  })
  use _ <- result.try(case list.last(state.records) {
    Ok(last) if occurred_at < last.occurred_at_unix_ms ->
      Error("transition time must not precede the retained transition log")
    _ -> Ok(Nil)
  })
  case find_by_key(state.records, idempotency_key) {
    Some(existing) ->
      case
        record_matches(
          existing,
          transition_id,
          event_kind,
          origin,
          occurred_at,
          payload_hash,
          evidence,
          execution,
        )
      {
        True -> output(state, True, existing)
        False -> Error("idempotencyKey conflicts with a retained transition")
      }
    None -> {
      use _ <- result.try(
        case
          list.any(state.records, fn(record) {
            record.transition_id == transition_id
          })
        {
          True ->
            Error("transitionId already exists with another idempotency key")
          False -> Ok(Nil)
        },
      )
      use _ <- result.try(validate_origin(event_kind, origin))
      use next <- result.try(next_stage(
        state.stage,
        event_kind,
        origin,
        evidence,
      ))
      let record =
        Record(
          state.revision + 1,
          transition_id,
          idempotency_key,
          event_kind,
          origin,
          occurred_at,
          payload_hash,
          evidence,
          execution,
          state.stage,
          next,
        )
      output(
        State(
          ..state,
          revision: state.revision + 1,
          stage: next,
          records: list.append(state.records, [record]),
        ),
        False,
        record,
      )
    }
  }
}

fn next_stage(
  current: Stage,
  event_kind: String,
  origin: String,
  evidence: List(String),
) -> Result(Stage, String) {
  case current, event_kind {
    Preparation, "begin_acquisition" -> Ok(Acquiring)
    Acquiring, "evidence_available" -> mechanical(Ready, origin, evidence)
    Ready, "declare_plan" -> Ok(PlanDeclared)
    PlanDeclared, "modify_plan" -> Ok(PlanDeclared)
    PlanDeclared, "cancel_plan" -> Ok(Ready)
    PlanDeclared, "begin_monitoring" -> Ok(Monitoring)
    Monitoring, "declare_entry_intent" -> Ok(EntryIntent)
    Monitoring, "declare_exit_intent" -> Ok(ExitIntent)
    EntryIntent, "cancel_intent" | ExitIntent, "cancel_intent" -> Ok(Monitoring)
    Ready, "session_close_approaching"
    | PlanDeclared, "session_close_approaching"
    | Monitoring, "session_close_approaching"
    | EntryIntent, "session_close_approaching"
    | ExitIntent, "session_close_approaching"
    -> mechanical(Closeout, origin, evidence)
    Preparation, "declare_closeout"
    | Acquiring, "declare_closeout"
    | Ready, "declare_closeout"
    | PlanDeclared, "declare_closeout"
    | Monitoring, "declare_closeout"
    | EntryIntent, "declare_closeout"
    | ExitIntent, "declare_closeout"
    -> Ok(Closeout)
    PlanDeclared, "declare_abort"
    | Monitoring, "declare_abort"
    | EntryIntent, "declare_abort"
    | ExitIntent, "declare_abort"
    -> Ok(Closeout)
    Closeout, "session_ended" -> mechanical(Review, origin, evidence)
    Closeout, "declare_review" -> Ok(Review)
    Review, "record_review" -> Ok(Review)
    _, "confirm_entry"
    | _, "confirm_exit"
    | _, "submit_order"
    | _, "cancel_order"
    | _, "replace_order"
    | _, "force_closeout"
    -> Error("order or account mutation remains behind CG-LIVE")
    _, _ -> Error("eventKind is not valid from the supplied workflow stage")
  }
}

fn mechanical(
  next: Stage,
  origin: String,
  evidence: List(String),
) -> Result(Stage, String) {
  case origin == "mechanical_fact", evidence != [] {
    True, True -> Ok(next)
    False, _ -> Error("mechanical transition requires origin=mechanical_fact")
    _, False -> Error("mechanical transition requires evidenceReferences")
  }
}

fn validate_origin(event_kind: String, origin: String) -> Result(Nil, String) {
  let mechanical_kind =
    list.contains(
      [
        "evidence_available",
        "session_close_approaching",
        "session_ended",
      ],
      event_kind,
    )
  case mechanical_kind, origin {
    True, "mechanical_fact" -> Ok(Nil)
    True, _ -> Error("mechanical eventKind requires origin=mechanical_fact")
    False, "llm_authored" | False, "user_authored" -> Ok(Nil)
    False, "mechanical_fact" ->
      Error("LLM/user transition cannot use origin=mechanical_fact")
    _, _ ->
      Error("origin must be llm_authored, user_authored, or mechanical_fact")
  }
}

fn decode_prior(
  payload: Option(String),
  supplied_hash: Option(String),
  workflow_id: String,
  branch_id: String,
  event_kind: String,
) -> Result(Option(State), String) {
  case payload, supplied_hash {
    None, None if event_kind == "initialize_preparation" -> Ok(None)
    None, None -> Error("current state is required after initialization")
    Some(_), None | None, Some(_) ->
      Error("currentStatePayload and currentStateHash must appear together")
    Some(payload), Some(supplied_hash) -> {
      use _ <- result.try(case string.byte_size(payload) <= 200_000 {
        True -> Ok(Nil)
        False -> Error("currentStatePayload exceeds 200000 bytes")
      })
      use _ <- result.try(verify_hash(
        "currentStateHash",
        payload,
        supplied_hash,
      ))
      use state <- result.try(
        json.parse(payload, state_decoder())
        |> result.map_error(fn(_) { "currentStatePayload is invalid" }),
      )
      use _ <- result.try(case encode(state) == payload {
        True -> Ok(Nil)
        False -> Error("currentStatePayload is not canonical state JSON")
      })
      use _ <- result.try(validate_state(state))
      use _ <- result.try(
        case state.workflow_id == workflow_id, state.branch_id == branch_id {
          True, True -> Ok(Nil)
          False, _ -> Error("workflowId does not match current state")
          _, False -> Error("branchId does not match current state")
        },
      )
      Ok(Some(state))
    }
  }
}

fn validate_state(state: State) -> Result(Nil, String) {
  use _ <- result.try(validate_text(
    "retained workflowId",
    state.workflow_id,
    200,
  ))
  use _ <- result.try(validate_text("retained branchId", state.branch_id, 200))
  let count = list.length(state.records)
  use _ <- result.try(case count > 0, count <= maximum_transitions {
    False, _ -> Error("current workflow state has no transition history")
    _, False -> Error("current workflow state exceeds 100 transitions")
    True, True -> Ok(Nil)
  })
  use _ <- result.try(case state.revision == count {
    True -> Ok(Nil)
    False -> Error("current workflow revision does not match its history")
  })
  use _ <- result.try(validate_unique_history(state.records))
  case state.records {
    [] -> Error("current workflow state has no transition history")
    [first, ..rest] -> {
      use _ <- result.try(validate_record_fields(first))
      use _ <- result.try(
        case
          first.revision == 1,
          first.event_kind == "initialize_preparation",
          first.from_stage == Preparation,
          first.to_stage == Preparation,
          first.origin == "llm_authored" || first.origin == "user_authored"
        {
          True, True, True, True, True -> Ok(Nil)
          _, _, _, _, _ ->
            Error("current workflow initialization record is invalid")
        },
      )
      use final_stage <- result.try(validate_record_tail(
        rest,
        Preparation,
        first.occurred_at_unix_ms,
        2,
      ))
      case final_stage == state.stage {
        True -> Ok(Nil)
        False -> Error("current workflow stage does not match its history")
      }
    }
  }
}

fn validate_record_tail(
  records: List(Record),
  current: Stage,
  previous_time: Int,
  expected_revision: Int,
) -> Result(Stage, String) {
  case records {
    [] -> Ok(current)
    [record, ..rest] -> {
      use _ <- result.try(validate_record_fields(record))
      use _ <- result.try(
        case
          record.revision == expected_revision,
          record.from_stage == current,
          record.occurred_at_unix_ms >= previous_time
        {
          True, True, True -> Ok(Nil)
          False, _, _ -> Error("current workflow history has a revision gap")
          _, False, _ -> Error("current workflow history has a stage gap")
          _, _, False ->
            Error("current workflow history moves backward in time")
        },
      )
      use lawful_stage <- result.try(next_stage(
        current,
        record.event_kind,
        record.origin,
        record.evidence_references,
      ))
      use _ <- result.try(case lawful_stage == record.to_stage {
        True -> Ok(Nil)
        False ->
          Error("current workflow history contains an unlawful transition")
      })
      validate_record_tail(
        rest,
        record.to_stage,
        record.occurred_at_unix_ms,
        expected_revision + 1,
      )
    }
  }
}

fn validate_record_fields(record: Record) -> Result(Nil, String) {
  use _ <- result.try(validate_text(
    "retained transitionId",
    record.transition_id,
    200,
  ))
  use _ <- result.try(validate_text(
    "retained idempotencyKey",
    record.idempotency_key,
    200,
  ))
  use _ <- result.try(case record.occurred_at_unix_ms >= 0 {
    True -> Ok(Nil)
    False -> Error("current workflow history contains a negative time")
  })
  use _ <- result.try(
    identity.sha256(record.payload_hash)
    |> result.map(fn(_) { Nil })
    |> result.map_error(fn(_) {
      "current workflow history contains an invalid payload hash"
    }),
  )
  use _ <- result.try(validate_references(
    "retained evidenceReferences",
    record.evidence_references,
  ))
  validate_references(
    "retained executionReceiptReferences",
    record.execution_receipt_references,
  )
}

fn validate_unique_history(records: List(Record)) -> Result(Nil, String) {
  let transition_ids = list.map(records, fn(record) { record.transition_id })
  let idempotency_keys =
    list.map(records, fn(record) { record.idempotency_key })
  case
    list.length(list.unique(transition_ids)) == list.length(transition_ids),
    list.length(list.unique(idempotency_keys)) == list.length(idempotency_keys)
  {
    True, True -> Ok(Nil)
    False, _ -> Error("current workflow history repeats a transitionId")
    _, False -> Error("current workflow history repeats an idempotencyKey")
  }
}

fn output(
  state: State,
  idempotent: Bool,
  applied: Record,
) -> Result(Json, String) {
  let payload = encode(state)
  use content_hash <- result.try(
    hash.text(payload)
    |> result.map_error(fn(_) { "next workflow state could not be hashed" }),
  )
  Ok(
    json.object([
      #("schemaVersion", json.string("pi_day_transition_result_v1")),
      #("idempotent", json.bool(idempotent)),
      #("workflowId", json.string(state.workflow_id)),
      #("branchId", json.string(state.branch_id)),
      #("revision", json.int(state.revision)),
      #("state", stage_json(state.stage)),
      #("appliedTransition", record_json(applied)),
      #("nextStatePayload", json.string(payload)),
      #("nextStateHash", json.string(identity.sha256_value(content_hash))),
      #(
        "storage",
        json.object([
          #("kind", json.string("caller_retained_stateless")),
          #("survivesReload", json.bool(False)),
          #("writesPerformed", json.bool(False)),
        ]),
      ),
      #(
        "availableOperations",
        json.array(available_operations(state.stage), json.string),
      ),
      #("decisionOwner", json.string("llm_or_user")),
      #(
        "meaning",
        json.string(
          "workflow information state only; Ready means evidence_available, never ready_to_trade",
        ),
      ),
      #(
        "forbiddenClaims",
        json.array(
          [
            "plan_or_risk_approval",
            "ready_to_trade",
            "order_authorization_or_mutation",
            "automatic_closeout",
            "recommendation_or_next_action",
          ],
          json.string,
        ),
      ),
    ]),
  )
}

fn state_json(state: State) -> Json {
  json.object([
    #("schemaVersion", json.string("pi_day_workflow_state_v1")),
    #("workflowId", json.string(state.workflow_id)),
    #("branchId", json.string(state.branch_id)),
    #("revision", json.int(state.revision)),
    #("stage", json.string(stage_name(state.stage))),
    #("records", json.array(state.records, record_json)),
  ])
}

fn record_json(record: Record) -> Json {
  json.object([
    #("revision", json.int(record.revision)),
    #("transitionId", json.string(record.transition_id)),
    #("idempotencyKey", json.string(record.idempotency_key)),
    #("eventKind", json.string(record.event_kind)),
    #("origin", json.string(record.origin)),
    #("occurredAtUnixMilliseconds", json.int(record.occurred_at_unix_ms)),
    #("payloadHash", json.string(record.payload_hash)),
    #("evidenceReferences", json.array(record.evidence_references, json.string)),
    #(
      "executionReceiptReferences",
      json.array(record.execution_receipt_references, json.string),
    ),
    #("fromStage", json.string(stage_name(record.from_stage))),
    #("toStage", json.string(stage_name(record.to_stage))),
  ])
}

fn stage_json(stage: Stage) -> Json {
  json.object([
    #("name", json.string(stage_name(stage))),
    #("meaning", json.string(stage_meaning(stage))),
  ])
}

fn stage_name(stage: Stage) -> String {
  case stage {
    Preparation -> "preparation"
    Acquiring -> "acquiring"
    Ready -> "ready"
    PlanDeclared -> "plan_declared"
    Monitoring -> "monitoring"
    EntryIntent -> "entry_intent"
    ExitIntent -> "exit_intent"
    Closeout -> "closeout"
    Review -> "review"
  }
}

fn stage_meaning(stage: Stage) -> String {
  case stage {
    Preparation ->
      "caller is preparing exact universe, strategy, and risk references"
    Acquiring ->
      "caller-declared evidence acquisition is in progress outside this plugin"
    Ready -> "evidence_available mechanical state; not ready_to_trade"
    PlanDeclared ->
      "LLM/user-authored non-executable plan declaration is referenced"
    Monitoring -> "LLM/user declared monitoring; no automatic alert or decision"
    EntryIntent -> "LLM/user declared entry intent; no order authorization"
    ExitIntent -> "LLM/user declared exit intent; no order authorization"
    Closeout -> "session closeout information state; no forced order"
    Review -> "post-session review information state; no process verdict"
  }
}

fn available_operations(stage: Stage) -> List(String) {
  case stage {
    Preparation -> ["begin_acquisition", "declare_closeout"]
    Acquiring -> ["evidence_available", "declare_closeout"]
    Ready -> ["declare_plan", "session_close_approaching", "declare_closeout"]
    PlanDeclared -> [
      "modify_plan",
      "cancel_plan",
      "begin_monitoring",
      "declare_abort",
      "session_close_approaching",
      "declare_closeout",
    ]
    Monitoring -> [
      "declare_entry_intent",
      "declare_exit_intent",
      "declare_abort",
      "session_close_approaching",
      "declare_closeout",
    ]
    EntryIntent | ExitIntent -> [
      "cancel_intent",
      "declare_abort",
      "session_close_approaching",
      "declare_closeout",
    ]
    Closeout -> ["session_ended", "declare_review"]
    Review -> ["record_review"]
  }
}

fn state_decoder() -> dynamic_decode.Decoder(State) {
  use schema <- dynamic_decode.field("schemaVersion", dynamic_decode.string)
  use workflow_id <- dynamic_decode.field("workflowId", dynamic_decode.string)
  use branch_id <- dynamic_decode.field("branchId", dynamic_decode.string)
  use revision <- dynamic_decode.field("revision", dynamic_decode.int)
  use stage <- dynamic_decode.field("stage", stage_decoder())
  use records <- dynamic_decode.field(
    "records",
    dynamic_decode.list(of: record_decoder()),
  )
  case schema == "pi_day_workflow_state_v1" {
    False ->
      dynamic_decode.failure(
        State(workflow_id, branch_id, revision, stage, records),
        "unsupported workflow schema",
      )
    True ->
      dynamic_decode.success(State(
        workflow_id,
        branch_id,
        revision,
        stage,
        records,
      ))
  }
}

fn record_decoder() -> dynamic_decode.Decoder(Record) {
  use revision <- dynamic_decode.field("revision", dynamic_decode.int)
  use transition_id <- dynamic_decode.field(
    "transitionId",
    dynamic_decode.string,
  )
  use key <- dynamic_decode.field("idempotencyKey", dynamic_decode.string)
  use event_kind <- dynamic_decode.field("eventKind", dynamic_decode.string)
  use origin <- dynamic_decode.field("origin", dynamic_decode.string)
  use occurred <- dynamic_decode.field(
    "occurredAtUnixMilliseconds",
    dynamic_decode.int,
  )
  use payload_hash <- dynamic_decode.field("payloadHash", dynamic_decode.string)
  use evidence <- dynamic_decode.field(
    "evidenceReferences",
    dynamic_decode.list(of: dynamic_decode.string),
  )
  use execution <- dynamic_decode.field(
    "executionReceiptReferences",
    dynamic_decode.list(of: dynamic_decode.string),
  )
  use from_stage <- dynamic_decode.field("fromStage", stage_decoder())
  use to_stage <- dynamic_decode.field("toStage", stage_decoder())
  dynamic_decode.success(Record(
    revision,
    transition_id,
    key,
    event_kind,
    origin,
    occurred,
    payload_hash,
    evidence,
    execution,
    from_stage,
    to_stage,
  ))
}

fn stage_decoder() -> dynamic_decode.Decoder(Stage) {
  dynamic_decode.string
  |> dynamic_decode.then(fn(value) {
    case value {
      "preparation" -> dynamic_decode.success(Preparation)
      "acquiring" -> dynamic_decode.success(Acquiring)
      "ready" -> dynamic_decode.success(Ready)
      "plan_declared" -> dynamic_decode.success(PlanDeclared)
      "monitoring" -> dynamic_decode.success(Monitoring)
      "entry_intent" -> dynamic_decode.success(EntryIntent)
      "exit_intent" -> dynamic_decode.success(ExitIntent)
      "closeout" -> dynamic_decode.success(Closeout)
      "review" -> dynamic_decode.success(Review)
      _ -> dynamic_decode.failure(Preparation, "unsupported workflow stage")
    }
  })
}

fn find_by_key(records: List(Record), key: String) -> Option(Record) {
  case list.find(records, fn(record) { record.idempotency_key == key }) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn record_matches(
  record: Record,
  transition_id: String,
  event_kind: String,
  origin: String,
  occurred_at: Int,
  payload_hash: String,
  evidence: List(String),
  execution: List(String),
) -> Bool {
  record.transition_id == transition_id
  && record.event_kind == event_kind
  && record.origin == origin
  && record.occurred_at_unix_ms == occurred_at
  && record.payload_hash == payload_hash
  && record.evidence_references == evidence
  && record.execution_receipt_references == execution
}

fn verify_hash(
  name: String,
  payload: String,
  supplied: String,
) -> Result(String, String) {
  use expected <- result.try(
    identity.sha256(supplied)
    |> result.map_error(fn(_) { name <> " must be a SHA-256 hex value" }),
  )
  use actual <- result.try(
    hash.text(payload)
    |> result.map_error(fn(_) { name <> " payload could not be hashed" }),
  )
  case expected == actual {
    True -> Ok(identity.sha256_value(actual))
    False -> Error(name <> " does not match its payload")
  }
}

fn validate_text(
  name: String,
  value: String,
  maximum: Int,
) -> Result(Nil, String) {
  case value == "", string.byte_size(value) > maximum {
    True, _ -> Error(name <> " must not be blank")
    _, True -> Error(name <> " exceeds its byte budget")
    False, False -> Ok(Nil)
  }
}

fn validate_references(
  name: String,
  values: List(String),
) -> Result(Nil, String) {
  use _ <- result.try(case list.length(values) <= maximum_references {
    True -> Ok(Nil)
    False -> Error(name <> " exceeds 50 entries")
  })
  use _ <- result.try(
    values
    |> list.try_each(fn(value) {
      identity.sha256(value)
      |> result.map(fn(_) { Nil })
      |> result.map_error(fn(_) { name <> " contains a non-SHA-256 value" })
    }),
  )
  case list.length(list.unique(values)) == list.length(values) {
    True -> Ok(Nil)
    False -> Error(name <> " contains duplicates")
  }
}
