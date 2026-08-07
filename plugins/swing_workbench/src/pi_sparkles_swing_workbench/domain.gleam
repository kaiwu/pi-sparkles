import finance_core/identifier
import finance_core/time
import finance_listing/listing
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_strategy/evidence
import finance_strategy/receipt
import finance_track
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const maximum_facts_per_snapshot = 64

pub const maximum_receipt_references = 64

pub type FactRole {
  Required
  Optional
  Ranking
  Context
}

pub type InformationState {
  Known
  Unknown
  NotObtained
  Conflicting
  DecodeFailure
  Declared
  Unsupported
  Stale
  Late
}

pub type FactInput {
  FactInput(
    fact_id: String,
    role: FactRole,
    state: InformationState,
    detail: String,
    receipt_references: List(Sha256),
  )
}

pub opaque type EvidenceFact {
  EvidenceFact(
    fact_id: String,
    role: FactRole,
    state: InformationState,
    detail: String,
    receipt_references: List(Sha256),
  )
}

pub opaque type CandidateSnapshot {
  CandidateSnapshot(
    workflow_id: String,
    strategy_receipt_hash: Sha256,
    strategy_receipt_payload: String,
    listing_key: String,
    track: finance_track.Track,
    definition_id: String,
    definition_version: String,
    definition_hash: Sha256,
    signal_session: time.Date,
    facts: List(EvidenceFact),
    attached_at: time.Instant,
  )
}

pub type DeclarationOrigin {
  LlmAuthored
  UserAuthored
}

pub opaque type PlanRecord {
  PlanRecord(
    workflow_id: String,
    source_strategy_receipt_hash: Sha256,
    plan_receipt_hash: Sha256,
    plan_payload: String,
    origin: DeclarationOrigin,
    risk_receipt_references: List(Sha256),
    rule_receipt_references: List(Sha256),
    execution_receipt_references: List(Sha256),
    created_at: time.Instant,
  )
}

pub opaque type ReviewRecord {
  ReviewRecord(
    workflow_id: String,
    record_id: String,
    record_kind: String,
    payload_hash: Sha256,
    payload: String,
    plan_receipt_reference: Option(Sha256),
    evidence_references: List(Sha256),
    observed_at: time.Instant,
  )
}

pub type ChangeKind {
  AddedFact
  ChangedFact
  UnchangedFact
  RemovedFact
}

pub type FactChange {
  FactChange(
    fact_id: String,
    kind: ChangeKind,
    previous: Option(EvidenceFact),
    current: Option(EvidenceFact),
  )
}

pub type DomainError {
  InvalidText(field: String)
  InvalidStrategyReceipt
  StrategyReceiptHashMismatch
  TooManyFacts(received: Int, maximum: Int)
  TooManyReceiptReferences(received: Int, maximum: Int)
  DuplicateFactId(fact_id: String)
  PayloadHashMismatch
  EmptyPayload
}

pub fn candidate_snapshot(
  workflow_id workflow_id_value: String,
  strategy_receipt_hash expected_hash: Sha256,
  strategy_receipt_payload payload: String,
  facts fact_inputs: List(FactInput),
  attached_at attached_at_value: time.Instant,
) -> Result(CandidateSnapshot, DomainError) {
  use _ <- result.try(valid_text(workflow_id_value, "workflow_id"))
  case receipt.decode(payload) {
    Error(_) -> Error(InvalidStrategyReceipt)
    Ok(strategy_receipt) -> {
      let canonical = receipt.encode(strategy_receipt)
      let assert Ok(actual_hash) = hash.text(canonical)
      case actual_hash == expected_hash {
        False -> Error(StrategyReceiptHashMismatch)
        True -> {
          use facts <- result.try(build_facts(fact_inputs))
          Ok(CandidateSnapshot(
            workflow_id_value,
            expected_hash,
            canonical,
            strategy_listing_key(strategy_receipt),
            strategy_receipt
              |> receipt.context
              |> evidence.context_listing
              |> listing.track,
            receipt.definition_id(strategy_receipt),
            receipt.definition_version(strategy_receipt),
            receipt.definition_hash(strategy_receipt),
            strategy_receipt
              |> receipt.context
              |> evidence.signal_session,
            facts,
            attached_at_value,
          ))
        }
      }
    }
  }
}

pub fn plan_record(
  workflow_id workflow_id_value: String,
  source_strategy_receipt_hash source_hash: Sha256,
  plan_receipt_hash expected_hash: Sha256,
  plan_payload payload: String,
  origin origin_value: DeclarationOrigin,
  risk_receipt_references risk_references: List(Sha256),
  rule_receipt_references rule_references: List(Sha256),
  execution_receipt_references execution_references: List(Sha256),
  created_at created_at_value: time.Instant,
) -> Result(PlanRecord, DomainError) {
  use _ <- result.try(valid_text(workflow_id_value, "workflow_id"))
  use _ <- result.try(nonempty_payload(payload))
  use _ <- result.try(
    validate_reference_count(list.append(
      risk_references,
      list.append(rule_references, execution_references),
    )),
  )
  use _ <- result.try(verify_payload(payload, expected_hash))
  Ok(PlanRecord(
    workflow_id_value,
    source_hash,
    expected_hash,
    payload,
    origin_value,
    risk_references,
    rule_references,
    execution_references,
    created_at_value,
  ))
}

pub fn review_record(
  workflow_id workflow_id_value: String,
  record_id record_id_value: String,
  record_kind record_kind_value: String,
  payload_hash expected_hash: Sha256,
  payload payload_value: String,
  plan_receipt_reference plan_reference: Option(Sha256),
  evidence_references evidence_values: List(Sha256),
  observed_at observed_at_value: time.Instant,
) -> Result(ReviewRecord, DomainError) {
  use _ <- result.try(valid_text(workflow_id_value, "workflow_id"))
  use _ <- result.try(valid_text(record_id_value, "record_id"))
  use _ <- result.try(valid_text(record_kind_value, "record_kind"))
  use _ <- result.try(nonempty_payload(payload_value))
  use _ <- result.try(validate_reference_count(evidence_values))
  use _ <- result.try(verify_payload(payload_value, expected_hash))
  Ok(ReviewRecord(
    workflow_id_value,
    record_id_value,
    record_kind_value,
    expected_hash,
    payload_value,
    plan_reference,
    evidence_values,
    observed_at_value,
  ))
}

fn build_facts(
  values: List(FactInput),
) -> Result(List(EvidenceFact), DomainError) {
  case list.length(values) > maximum_facts_per_snapshot {
    True -> Error(TooManyFacts(list.length(values), maximum_facts_per_snapshot))
    False -> build_facts_loop(values, [], [])
  }
}

fn build_facts_loop(
  values: List(FactInput),
  seen: List(String),
  reversed: List(EvidenceFact),
) -> Result(List(EvidenceFact), DomainError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [FactInput(id, role, state, detail, references), ..rest] -> {
      use _ <- result.try(valid_text(id, "fact_id"))
      use _ <- result.try(valid_text(detail, "fact_detail"))
      use _ <- result.try(validate_reference_count(references))
      case list.contains(seen, id) {
        True -> Error(DuplicateFactId(id))
        False ->
          build_facts_loop(rest, [id, ..seen], [
            EvidenceFact(id, role, state, detail, references),
            ..reversed
          ])
      }
    }
  }
}

pub fn changes(
  previous: Option(CandidateSnapshot),
  current: CandidateSnapshot,
) -> List(FactChange) {
  case previous {
    None ->
      list.map(current.facts, fn(value) {
        FactChange(value.fact_id, AddedFact, None, Some(value))
      })
    Some(previous) -> {
      let current_changes =
        list.map(current.facts, fn(value) {
          case find_fact(previous.facts, value.fact_id) {
            None -> FactChange(value.fact_id, AddedFact, None, Some(value))
            Some(old) -> {
              let kind = case old == value {
                True -> UnchangedFact
                False -> ChangedFact
              }
              FactChange(value.fact_id, kind, Some(old), Some(value))
            }
          }
        })
      let removed =
        previous.facts
        |> list.filter_map(fn(value) {
          case find_fact(current.facts, value.fact_id) {
            Some(_) -> Error(Nil)
            None ->
              Ok(FactChange(value.fact_id, RemovedFact, Some(value), None))
          }
        })
      list.append(current_changes, removed)
    }
  }
}

fn find_fact(values: List(EvidenceFact), id: String) -> Option(EvidenceFact) {
  case values |> list.find(fn(value) { value.fact_id == id }) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

pub fn workflow_id(value: CandidateSnapshot) -> String {
  value.workflow_id
}

pub fn strategy_receipt_hash(value: CandidateSnapshot) -> Sha256 {
  value.strategy_receipt_hash
}

pub fn strategy_receipt_payload(value: CandidateSnapshot) -> String {
  value.strategy_receipt_payload
}

pub fn facts(value: CandidateSnapshot) -> List(EvidenceFact) {
  value.facts
}

pub fn attached_at(value: CandidateSnapshot) -> time.Instant {
  value.attached_at
}

pub fn listing_key(value: CandidateSnapshot) -> String {
  value.listing_key
}

pub fn track(value: CandidateSnapshot) -> finance_track.Track {
  value.track
}

pub fn definition_id(value: CandidateSnapshot) -> String {
  value.definition_id
}

pub fn definition_version(value: CandidateSnapshot) -> String {
  value.definition_version
}

pub fn definition_hash(value: CandidateSnapshot) -> Sha256 {
  value.definition_hash
}

pub fn signal_session(value: CandidateSnapshot) -> time.Date {
  value.signal_session
}

pub fn placeholder_candidate() -> CandidateSnapshot {
  let assert Ok(digest) =
    identity.sha256(
      "0000000000000000000000000000000000000000000000000000000000000000",
    )
  let assert Ok(session) = time.date(1970, 1, 1)
  CandidateSnapshot(
    "placeholder",
    digest,
    "placeholder",
    "cn|XSHG|000000|placeholder:000000",
    finance_track.Cn,
    "placeholder",
    "0.0.0",
    digest,
    session,
    [],
    placeholder_instant(),
  )
}

pub fn fact_id(value: EvidenceFact) -> String {
  value.fact_id
}

pub fn fact_role(value: EvidenceFact) -> FactRole {
  value.role
}

pub fn information_state(value: EvidenceFact) -> InformationState {
  value.state
}

pub fn fact_detail(value: EvidenceFact) -> String {
  value.detail
}

pub fn fact_receipt_references(value: EvidenceFact) -> List(Sha256) {
  value.receipt_references
}

pub fn plan_workflow_id(value: PlanRecord) -> String {
  value.workflow_id
}

pub fn source_strategy_receipt_hash(value: PlanRecord) -> Sha256 {
  value.source_strategy_receipt_hash
}

pub fn plan_receipt_hash(value: PlanRecord) -> Sha256 {
  value.plan_receipt_hash
}

pub fn plan_payload(value: PlanRecord) -> String {
  value.plan_payload
}

pub fn plan_origin(value: PlanRecord) -> DeclarationOrigin {
  value.origin
}

pub fn risk_receipt_references(value: PlanRecord) -> List(Sha256) {
  value.risk_receipt_references
}

pub fn rule_receipt_references(value: PlanRecord) -> List(Sha256) {
  value.rule_receipt_references
}

pub fn execution_receipt_references(value: PlanRecord) -> List(Sha256) {
  value.execution_receipt_references
}

pub fn plan_created_at(value: PlanRecord) -> time.Instant {
  value.created_at
}

pub fn review_workflow_id(value: ReviewRecord) -> String {
  value.workflow_id
}

pub fn record_id(value: ReviewRecord) -> String {
  value.record_id
}

pub fn record_kind(value: ReviewRecord) -> String {
  value.record_kind
}

pub fn review_payload_hash(value: ReviewRecord) -> Sha256 {
  value.payload_hash
}

pub fn review_payload(value: ReviewRecord) -> String {
  value.payload
}

pub fn plan_receipt_reference(value: ReviewRecord) -> Option(Sha256) {
  value.plan_receipt_reference
}

pub fn review_evidence_references(value: ReviewRecord) -> List(Sha256) {
  value.evidence_references
}

pub fn observed_at(value: ReviewRecord) -> time.Instant {
  value.observed_at
}

pub fn change_fact_id(value: FactChange) -> String {
  let FactChange(id, _, _, _) = value
  id
}

pub fn change_kind(value: FactChange) -> ChangeKind {
  let FactChange(_, kind, _, _) = value
  kind
}

pub fn previous_fact(value: FactChange) -> Option(EvidenceFact) {
  let FactChange(_, _, previous, _) = value
  previous
}

pub fn current_fact(value: FactChange) -> Option(EvidenceFact) {
  let FactChange(_, _, _, current) = value
  current
}

pub fn fact_role_name(value: FactRole) -> String {
  case value {
    Required -> "required"
    Optional -> "optional"
    Ranking -> "ranking"
    Context -> "context"
  }
}

pub fn information_state_name(value: InformationState) -> String {
  case value {
    Known -> "known"
    Unknown -> "unknown"
    NotObtained -> "not_obtained"
    Conflicting -> "conflicting"
    DecodeFailure -> "decode_failure"
    Declared -> "declared"
    Unsupported -> "unsupported"
    Stale -> "stale"
    Late -> "late"
  }
}

pub fn origin_name(value: DeclarationOrigin) -> String {
  case value {
    LlmAuthored -> "llm_authored"
    UserAuthored -> "user_authored"
  }
}

pub fn change_kind_name(value: ChangeKind) -> String {
  case value {
    AddedFact -> "added"
    ChangedFact -> "changed"
    UnchangedFact -> "unchanged"
    RemovedFact -> "removed"
  }
}

fn nonempty_payload(value: String) -> Result(Nil, DomainError) {
  case value == "" {
    True -> Error(EmptyPayload)
    False -> Ok(Nil)
  }
}

fn verify_payload(value: String, expected: Sha256) -> Result(Nil, DomainError) {
  let assert Ok(actual) = hash.text(value)
  case actual == expected {
    True -> Ok(Nil)
    False -> Error(PayloadHashMismatch)
  }
}

fn validate_reference_count(values: List(Sha256)) -> Result(Nil, DomainError) {
  case list.length(values) > maximum_receipt_references {
    True ->
      Error(TooManyReceiptReferences(
        list.length(values),
        maximum_receipt_references,
      ))
    False -> Ok(Nil)
  }
}

fn valid_text(value: String, field: String) -> Result(Nil, DomainError) {
  case
    value != ""
    && string.length(value) <= 200
    && string.trim(value) == value
    && !string.contains(value, "\n")
    && !string.contains(value, "\r")
  {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn strategy_listing_key(value: receipt.StrategyEvidenceReceipt) -> String {
  let key = value |> receipt.context |> evidence.context_listing
  finance_track.name(listing.track(key))
  <> "|"
  <> { key |> listing.mic |> identifier.mic_value }
  <> "|"
  <> { key |> listing.symbol |> identifier.symbol_value }
  <> "|"
  <> { key |> listing.instrument_id |> identifier.instrument_id_value }
}

fn placeholder_instant() -> time.Instant {
  let assert Ok(value) = time.instant(0)
  value
}
