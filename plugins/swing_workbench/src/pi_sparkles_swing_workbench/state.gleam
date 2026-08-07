import finance_core/time
import finance_provenance/hash as provenance_hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import pi_sparkles_swing_workbench/domain.{
  type CandidateSnapshot, type EvidenceFact, type FactChange, type PlanRecord,
  type ReviewRecord,
}

pub const schema_version = 1

const maximum_workflows = 50

const maximum_snapshots_per_workflow = 20

const maximum_reviews_per_workflow = 100

const maximum_revision = 10_000

pub opaque type Workflow {
  Workflow(
    workflow_id: String,
    listing_key: String,
    definition_id: String,
    definition_version: String,
    snapshots: List(CandidateSnapshot),
    plan: Option(PlanRecord),
    reviews: List(ReviewRecord),
  )
}

pub opaque type State {
  State(revision: Int, workflows: List(Workflow))
}

pub type Change {
  CandidateStored(snapshot: CandidateSnapshot, changes: List(FactChange))
  PlanStored(plan: PlanRecord)
  PlanUnchanged(plan: PlanRecord)
  ReviewStored(review: ReviewRecord)
}

pub type MutationEvent {
  CandidateEvent(revision: Int, snapshot: CandidateSnapshot)
  PlanEvent(revision: Int, plan: PlanRecord)
  ReviewEvent(revision: Int, review: ReviewRecord)
}

pub type StateError {
  RevisionExhausted
  TooManyWorkflows
  TooManySnapshots(workflow_id: String)
  TooManyReviews(workflow_id: String)
  WorkflowNotFound(workflow_id: String)
  WorkflowIdentityMismatch(workflow_id: String)
  StrategyReceiptNotAttached
  PlanAlreadyAttached
  PlanReferenceMismatch
  DuplicateReviewId(record_id: String)
}

pub type ReplayError {
  InvalidEventJson
  NonContiguousRevision(expected: Int, received: Int)
  InvalidEvent(StateError)
  EventDidNotMutate
}

pub fn empty() -> State {
  State(0, [])
}

pub fn attach_candidate(
  state: State,
  snapshot: CandidateSnapshot,
) -> Result(#(State, Change), StateError) {
  case find_workflow(state.workflows, domain.workflow_id(snapshot)) {
    None -> {
      case list.length(state.workflows) >= maximum_workflows {
        True -> Error(TooManyWorkflows)
        False -> {
          let workflow =
            Workflow(
              domain.workflow_id(snapshot),
              domain.listing_key(snapshot),
              domain.definition_id(snapshot),
              domain.definition_version(snapshot),
              [snapshot],
              None,
              [],
            )
          next_state(
            state,
            list.append(state.workflows, [workflow]),
            CandidateStored(snapshot, domain.changes(None, snapshot)),
          )
        }
      }
    }
    Some(workflow) -> {
      case
        workflow.listing_key == domain.listing_key(snapshot),
        workflow.definition_id == domain.definition_id(snapshot)
      {
        False, _ | _, False ->
          Error(WorkflowIdentityMismatch(domain.workflow_id(snapshot)))
        True, True ->
          case
            list.length(workflow.snapshots) >= maximum_snapshots_per_workflow
          {
            True -> Error(TooManySnapshots(workflow.workflow_id))
            False -> {
              let prior = case list.last(workflow.snapshots) {
                Ok(value) -> Some(value)
                Error(_) -> None
              }
              let updated =
                Workflow(
                  ..workflow,
                  definition_version: domain.definition_version(snapshot),
                  snapshots: list.append(workflow.snapshots, [snapshot]),
                )
              let workflows = replace_workflow(state.workflows, updated)
              next_state(
                state,
                workflows,
                CandidateStored(snapshot, domain.changes(prior, snapshot)),
              )
            }
          }
      }
    }
  }
}

pub fn attach_plan(
  state: State,
  plan: PlanRecord,
) -> Result(#(State, Change), StateError) {
  case find_workflow(state.workflows, domain.plan_workflow_id(plan)) {
    None -> Error(WorkflowNotFound(domain.plan_workflow_id(plan)))
    Some(workflow) ->
      case workflow.plan {
        Some(existing) ->
          case
            domain.plan_receipt_hash(existing) == domain.plan_receipt_hash(plan)
          {
            True -> Ok(#(state, PlanUnchanged(existing)))
            False -> Error(PlanAlreadyAttached)
          }
        None -> {
          let source_exists =
            list.any(workflow.snapshots, fn(snapshot) {
              domain.strategy_receipt_hash(snapshot)
              == domain.source_strategy_receipt_hash(plan)
            })
          case source_exists {
            False -> Error(StrategyReceiptNotAttached)
            True -> {
              let updated = Workflow(..workflow, plan: Some(plan))
              next_state(
                state,
                replace_workflow(state.workflows, updated),
                PlanStored(plan),
              )
            }
          }
        }
      }
  }
}

pub fn attach_review(
  state: State,
  review: ReviewRecord,
) -> Result(#(State, Change), StateError) {
  case find_workflow(state.workflows, domain.review_workflow_id(review)) {
    None -> Error(WorkflowNotFound(domain.review_workflow_id(review)))
    Some(workflow) -> {
      let duplicate =
        list.any(workflow.reviews, fn(value) {
          domain.record_id(value) == domain.record_id(review)
        })
      case
        duplicate,
        list.length(workflow.reviews) >= maximum_reviews_per_workflow
      {
        True, _ -> Error(DuplicateReviewId(domain.record_id(review)))
        _, True -> Error(TooManyReviews(workflow.workflow_id))
        False, False ->
          case review_plan_matches(workflow.plan, review) {
            False -> Error(PlanReferenceMismatch)
            True -> {
              let updated =
                Workflow(
                  ..workflow,
                  reviews: list.append(workflow.reviews, [review]),
                )
              next_state(
                state,
                replace_workflow(state.workflows, updated),
                ReviewStored(review),
              )
            }
          }
      }
    }
  }
}

fn review_plan_matches(plan: Option(PlanRecord), review: ReviewRecord) -> Bool {
  case domain.plan_receipt_reference(review), plan {
    None, _ -> True
    Some(_), None -> False
    Some(reference), Some(plan) -> reference == domain.plan_receipt_hash(plan)
  }
}

fn next_state(
  state: State,
  workflows: List(Workflow),
  change: Change,
) -> Result(#(State, Change), StateError) {
  case state.revision >= maximum_revision {
    True -> Error(RevisionExhausted)
    False -> Ok(#(State(state.revision + 1, workflows), change))
  }
}

pub fn event_for_candidate(
  state: State,
  snapshot: CandidateSnapshot,
) -> MutationEvent {
  CandidateEvent(state.revision, snapshot)
}

pub fn event_for_plan(state: State, plan: PlanRecord) -> MutationEvent {
  PlanEvent(state.revision, plan)
}

pub fn event_for_review(state: State, review: ReviewRecord) -> MutationEvent {
  ReviewEvent(state.revision, review)
}

pub fn encode_event(value: MutationEvent) -> String {
  value |> event_json |> json.to_string
}

pub fn decode_event(value: String) -> Result(MutationEvent, ReplayError) {
  value
  |> json.parse(event_decoder())
  |> result.map_error(fn(_) { InvalidEventJson })
}

pub fn replay(values: List(String)) -> Result(State, ReplayError) {
  replay_loop(values, empty())
}

fn replay_loop(
  values: List(String),
  state: State,
) -> Result(State, ReplayError) {
  case values {
    [] -> Ok(state)
    [encoded, ..rest] -> {
      use event <- result.try(decode_event(encoded))
      let received = event_revision(event)
      let expected = state.revision + 1
      case received == expected {
        False -> Error(NonContiguousRevision(expected, received))
        True -> {
          let applied = case event {
            CandidateEvent(_, snapshot) -> attach_candidate(state, snapshot)
            PlanEvent(_, plan) -> attach_plan(state, plan)
            ReviewEvent(_, review) -> attach_review(state, review)
          }
          case applied {
            Error(error) -> Error(InvalidEvent(error))
            Ok(#(_next, PlanUnchanged(_))) -> Error(EventDidNotMutate)
            Ok(#(next, _)) -> replay_loop(rest, next)
          }
        }
      }
    }
  }
}

fn event_revision(value: MutationEvent) -> Int {
  case value {
    CandidateEvent(revision, _)
    | PlanEvent(revision, _)
    | ReviewEvent(revision, _) -> revision
  }
}

fn event_json(value: MutationEvent) -> json.Json {
  case value {
    CandidateEvent(revision, snapshot) ->
      json.object([
        #("schema", json.string("pi_sparkles_swing_workbench_event")),
        #("schema_version", json.int(schema_version)),
        #("event_type", json.string("candidate_attached")),
        #("revision", json.int(revision)),
        #("candidate", candidate_json(snapshot)),
      ])
    PlanEvent(revision, plan) ->
      json.object([
        #("schema", json.string("pi_sparkles_swing_workbench_event")),
        #("schema_version", json.int(schema_version)),
        #("event_type", json.string("plan_attached")),
        #("revision", json.int(revision)),
        #("plan", plan_json(plan)),
      ])
    ReviewEvent(revision, review) ->
      json.object([
        #("schema", json.string("pi_sparkles_swing_workbench_event")),
        #("schema_version", json.int(schema_version)),
        #("event_type", json.string("review_attached")),
        #("revision", json.int(revision)),
        #("review", review_json(review)),
      ])
  }
}

fn event_decoder() -> decode.Decoder(MutationEvent) {
  use schema <- decode.field("schema", decode.string)
  use version <- decode.field("schema_version", decode.int)
  use event_type <- decode.field("event_type", decode.string)
  use revision <- decode.field("revision", decode.int)
  case
    schema == "pi_sparkles_swing_workbench_event",
    version == schema_version
  {
    False, _ | _, False ->
      decode.failure(placeholder_event(), "swing workbench event v1")
    True, True ->
      case event_type {
        "candidate_attached" -> {
          use candidate <- decode.field("candidate", candidate_decoder())
          decode.success(CandidateEvent(revision, candidate))
        }
        "plan_attached" -> {
          use plan <- decode.field("plan", plan_decoder())
          decode.success(PlanEvent(revision, plan))
        }
        "review_attached" -> {
          use review <- decode.field("review", review_decoder())
          decode.success(ReviewEvent(revision, review))
        }
        _ -> decode.failure(placeholder_event(), "known swing event type")
      }
  }
}

pub fn candidate_json(value: CandidateSnapshot) -> json.Json {
  json.object([
    #("workflow_id", json.string(domain.workflow_id(value))),
    #(
      "strategy_receipt_hash",
      value
        |> domain.strategy_receipt_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #(
      "strategy_receipt_payload",
      json.string(domain.strategy_receipt_payload(value)),
    ),
    #("facts", value |> domain.facts |> json.array(fact_json)),
    #(
      "attached_at_unix_ms",
      value |> domain.attached_at |> time.unix_milliseconds |> json.int,
    ),
  ])
}

fn candidate_decoder() -> decode.Decoder(CandidateSnapshot) {
  use workflow_id <- decode.field("workflow_id", decode.string)
  use strategy_hash <- decode.field("strategy_receipt_hash", sha_decoder())
  use payload <- decode.field("strategy_receipt_payload", decode.string)
  use facts <- decode.field("facts", decode.list(of: fact_input_decoder()))
  use attached_at <- decode.field("attached_at_unix_ms", instant_decoder())
  case
    domain.candidate_snapshot(
      workflow_id,
      strategy_hash,
      payload,
      facts,
      attached_at,
    )
  {
    Ok(value) -> decode.success(value)
    Error(_) ->
      decode.failure(placeholder_candidate(), "valid candidate snapshot")
  }
}

fn fact_json(value: EvidenceFact) -> json.Json {
  json.object([
    #("fact_id", json.string(domain.fact_id(value))),
    #("role", value |> domain.fact_role |> domain.fact_role_name |> json.string),
    #(
      "state",
      value
        |> domain.information_state
        |> domain.information_state_name
        |> json.string,
    ),
    #("detail", json.string(domain.fact_detail(value))),
    #("receipt_references", hashes_json(domain.fact_receipt_references(value))),
  ])
}

fn fact_input_decoder() -> decode.Decoder(domain.FactInput) {
  use id <- decode.field("fact_id", decode.string)
  use role <- decode.field("role", role_decoder())
  use state <- decode.field("state", information_state_decoder())
  use detail <- decode.field("detail", decode.string)
  use references <- decode.field(
    "receipt_references",
    decode.list(of: sha_decoder()),
  )
  decode.success(domain.FactInput(id, role, state, detail, references))
}

pub fn plan_json(value: PlanRecord) -> json.Json {
  json.object([
    #("workflow_id", json.string(domain.plan_workflow_id(value))),
    #(
      "source_strategy_receipt_hash",
      value
        |> domain.source_strategy_receipt_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #(
      "plan_receipt_hash",
      value |> domain.plan_receipt_hash |> identity.sha256_value |> json.string,
    ),
    #("plan_payload", json.string(domain.plan_payload(value))),
    #(
      "origin",
      value |> domain.plan_origin |> domain.origin_name |> json.string,
    ),
    #(
      "risk_receipt_references",
      hashes_json(domain.risk_receipt_references(value)),
    ),
    #(
      "rule_receipt_references",
      hashes_json(domain.rule_receipt_references(value)),
    ),
    #(
      "execution_receipt_references",
      hashes_json(domain.execution_receipt_references(value)),
    ),
    #(
      "created_at_unix_ms",
      value |> domain.plan_created_at |> time.unix_milliseconds |> json.int,
    ),
  ])
}

fn plan_decoder() -> decode.Decoder(PlanRecord) {
  use workflow_id <- decode.field("workflow_id", decode.string)
  use source_hash <- decode.field("source_strategy_receipt_hash", sha_decoder())
  use plan_hash <- decode.field("plan_receipt_hash", sha_decoder())
  use payload <- decode.field("plan_payload", decode.string)
  use origin <- decode.field("origin", origin_decoder())
  use risk <- decode.field(
    "risk_receipt_references",
    decode.list(of: sha_decoder()),
  )
  use rules <- decode.field(
    "rule_receipt_references",
    decode.list(of: sha_decoder()),
  )
  use execution <- decode.field(
    "execution_receipt_references",
    decode.list(of: sha_decoder()),
  )
  use created_at <- decode.field("created_at_unix_ms", instant_decoder())
  case
    domain.plan_record(
      workflow_id,
      source_hash,
      plan_hash,
      payload,
      origin,
      risk,
      rules,
      execution,
      created_at,
    )
  {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(placeholder_plan(), "valid plan record")
  }
}

pub fn review_json(value: ReviewRecord) -> json.Json {
  json.object([
    #("workflow_id", json.string(domain.review_workflow_id(value))),
    #("record_id", json.string(domain.record_id(value))),
    #("record_kind", json.string(domain.record_kind(value))),
    #(
      "payload_hash",
      value
        |> domain.review_payload_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #("payload", json.string(domain.review_payload(value))),
    #(
      "plan_receipt_reference",
      json.nullable(domain.plan_receipt_reference(value), fn(value) {
        value |> identity.sha256_value |> json.string
      }),
    ),
    #(
      "evidence_references",
      hashes_json(domain.review_evidence_references(value)),
    ),
    #(
      "observed_at_unix_ms",
      value |> domain.observed_at |> time.unix_milliseconds |> json.int,
    ),
  ])
}

fn review_decoder() -> decode.Decoder(ReviewRecord) {
  use workflow_id <- decode.field("workflow_id", decode.string)
  use record_id <- decode.field("record_id", decode.string)
  use record_kind <- decode.field("record_kind", decode.string)
  use payload_hash <- decode.field("payload_hash", sha_decoder())
  use payload <- decode.field("payload", decode.string)
  use plan_reference <- decode.field(
    "plan_receipt_reference",
    decode.optional(sha_decoder()),
  )
  use references <- decode.field(
    "evidence_references",
    decode.list(of: sha_decoder()),
  )
  use observed_at <- decode.field("observed_at_unix_ms", instant_decoder())
  case
    domain.review_record(
      workflow_id,
      record_id,
      record_kind,
      payload_hash,
      payload,
      plan_reference,
      references,
      observed_at,
    )
  {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(placeholder_review(), "valid review record")
  }
}

fn role_decoder() -> decode.Decoder(domain.FactRole) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "required" -> decode.success(domain.Required)
      "optional" -> decode.success(domain.Optional)
      "ranking" -> decode.success(domain.Ranking)
      "context" -> decode.success(domain.Context)
      _ -> decode.failure(domain.Context, "known fact role")
    }
  })
}

fn information_state_decoder() -> decode.Decoder(domain.InformationState) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "known" -> decode.success(domain.Known)
      "unknown" -> decode.success(domain.Unknown)
      "not_obtained" -> decode.success(domain.NotObtained)
      "conflicting" -> decode.success(domain.Conflicting)
      "decode_failure" -> decode.success(domain.DecodeFailure)
      "declared" -> decode.success(domain.Declared)
      "unsupported" -> decode.success(domain.Unsupported)
      "stale" -> decode.success(domain.Stale)
      "late" -> decode.success(domain.Late)
      _ -> decode.failure(domain.Unknown, "known information state")
    }
  })
}

fn origin_decoder() -> decode.Decoder(domain.DeclarationOrigin) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "llm_authored" -> decode.success(domain.LlmAuthored)
      "user_authored" -> decode.success(domain.UserAuthored)
      _ -> decode.failure(domain.LlmAuthored, "known declaration origin")
    }
  })
}

fn sha_decoder() -> decode.Decoder(identity.Sha256) {
  decode.string
  |> decode.then(fn(value) {
    case identity.sha256(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder_sha(), "SHA-256 hex")
    }
  })
}

fn instant_decoder() -> decode.Decoder(time.Instant) {
  decode.int
  |> decode.then(fn(value) {
    case time.instant(value) {
      Ok(value) -> decode.success(value)
      Error(_) ->
        decode.failure(placeholder_instant(), "valid Unix milliseconds")
    }
  })
}

fn hashes_json(values: List(identity.Sha256)) -> json.Json {
  values
  |> list.map(identity.sha256_value)
  |> json.array(json.string)
}

fn find_workflow(values: List(Workflow), id: String) -> Option(Workflow) {
  case values |> list.find(fn(value) { value.workflow_id == id }) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn replace_workflow(
  values: List(Workflow),
  updated: Workflow,
) -> List(Workflow) {
  list.map(values, fn(value) {
    case value.workflow_id == updated.workflow_id {
      True -> updated
      False -> value
    }
  })
}

pub fn revision(value: State) -> Int {
  value.revision
}

pub fn workflows(value: State) -> List(Workflow) {
  value.workflows
}

pub fn selected_workflows(
  state: State,
  selected: Option(String),
) -> Result(List(Workflow), StateError) {
  case selected {
    None -> Ok(state.workflows)
    Some(id) ->
      case find_workflow(state.workflows, id) {
        None -> Error(WorkflowNotFound(id))
        Some(value) -> Ok([value])
      }
  }
}

pub fn workflow_id(value: Workflow) -> String {
  value.workflow_id
}

pub fn listing_key(value: Workflow) -> String {
  value.listing_key
}

pub fn definition_id(value: Workflow) -> String {
  value.definition_id
}

pub fn definition_version(value: Workflow) -> String {
  value.definition_version
}

pub fn snapshots(value: Workflow) -> List(CandidateSnapshot) {
  value.snapshots
}

pub fn latest_snapshot(value: Workflow) -> CandidateSnapshot {
  let assert Ok(snapshot) = list.last(value.snapshots)
  snapshot
}

pub fn prior_snapshot(value: Workflow) -> Option(CandidateSnapshot) {
  let count = list.length(value.snapshots)
  case count < 2 {
    True -> None
    False ->
      case value.snapshots |> list.drop(count - 2) |> list.first {
        Ok(value) -> Some(value)
        Error(_) -> None
      }
  }
}

pub fn plan(value: Workflow) -> Option(PlanRecord) {
  value.plan
}

pub fn reviews(value: Workflow) -> List(ReviewRecord) {
  value.reviews
}

pub fn maximum_workflow_count() -> Int {
  maximum_workflows
}

pub fn maximum_snapshots() -> Int {
  maximum_snapshots_per_workflow
}

pub fn maximum_reviews() -> Int {
  maximum_reviews_per_workflow
}

pub fn maximum_event_revision() -> Int {
  maximum_revision
}

fn placeholder_event() -> MutationEvent {
  CandidateEvent(0, placeholder_candidate())
}

fn placeholder_candidate() -> CandidateSnapshot {
  domain.placeholder_candidate()
}

fn placeholder_plan() -> PlanRecord {
  let payload = "placeholder"
  let assert Ok(payload_hash) = provenance_hash.text(payload)
  let assert Ok(value) =
    domain.plan_record(
      "placeholder",
      placeholder_strategy_hash(),
      payload_hash,
      payload,
      domain.LlmAuthored,
      [],
      [],
      [],
      placeholder_instant(),
    )
  value
}

fn placeholder_review() -> ReviewRecord {
  let payload = "placeholder"
  let assert Ok(payload_hash) = provenance_hash.text(payload)
  let assert Ok(value) =
    domain.review_record(
      "placeholder",
      "placeholder",
      "placeholder",
      payload_hash,
      payload,
      None,
      [],
      placeholder_instant(),
    )
  value
}

fn placeholder_sha() -> identity.Sha256 {
  let assert Ok(value) =
    identity.sha256(
      "0000000000000000000000000000000000000000000000000000000000000000",
    )
  value
}

fn placeholder_instant() -> time.Instant {
  let assert Ok(value) = time.instant(0)
  value
}

fn placeholder_strategy_hash() -> identity.Sha256 {
  let assert Ok(value) = provenance_hash.text("placeholder-strategy")
  value
}
