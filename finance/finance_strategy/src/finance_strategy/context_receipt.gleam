import finance_core/identifier
import finance_core/source.{type SourceRef}
import finance_core/time.{type Instant, type Timezone}
import finance_listing/listing.{type Key}
import finance_provenance/hash
import finance_provenance/identity.{type EvidenceId, type Sha256}
import finance_track
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string

pub const schema_version = 1

/// An information state copied from an upstream source or caller.
///
/// None of these constructors says whether the information is sufficient or
/// what an LLM should do with it.
pub type Information(value) {
  Known(value)
  Unknown(reason: String)
  NotObtained(reason: String)
  Conflicting(alternatives: List(value), reason: String)
}

/// One exact source-declared classification. `label` is never inferred here.
pub opaque type Classification {
  Classification(
    scheme: String,
    label: String,
    as_of: Instant,
    retrieved_at: Instant,
    timezone: Timezone,
    source: SourceRef,
    source_receipt: Sha256,
  )
}

/// One event exactly as named and timed by its supplied source.
pub opaque type CatalystEvent {
  CatalystEvent(
    event_id: String,
    category: String,
    headline: String,
    source_status: String,
    occurrence_time: Information(Instant),
    published_at: Information(Instant),
    timezone: Timezone,
    source: SourceRef,
    source_receipt: Sha256,
    lineage_receipts: List(Sha256),
  )
}

/// The exact query scope and returned event population.
///
/// `Known(CatalystSnapshot(_, []))` means that this supplied query returned no
/// rows. It does not mean that no catalyst exists.
pub opaque type CatalystSnapshot {
  CatalystSnapshot(query_scope: String, events: List(CatalystEvent))
}

/// Exact clocks captured for one caller-named workflow task.
///
/// No age, freshness, lateness, deadline, or next-operation label is derived.
pub opaque type TaskTimeObservation {
  TaskTimeObservation(
    task_id: String,
    stage: String,
    requested_at: Instant,
    context_as_of: Information(Instant),
    source_cutoff: Information(Instant),
    attached_at: Instant,
    timezone: Timezone,
    evidence_roots: List(EvidenceId),
  )
}

/// One exact field copied from a universe provider or caller row.
pub opaque type SourceField {
  SourceField(name: String, value: String)
}

/// One exact source row from a caller-named point-in-time universe query.
///
/// Membership and reasons are copied labels. This type does not qualify,
/// rank, select, or recommend the listing.
pub opaque type UniverseCandidateObservation {
  UniverseCandidateObservation(
    universe_id: String,
    definition_version: String,
    query_scope: String,
    source_row_id: String,
    source_declared_membership: String,
    source_declared_reasons: List(String),
    source_fields: List(SourceField),
    as_of: Instant,
    source_cutoff: Instant,
    retrieved_at: Instant,
    timezone: Timezone,
    source: SourceRef,
    source_receipt: Sha256,
    universe_receipt: Sha256,
    evidence_roots: List(EvidenceId),
  )
}

pub type Family {
  SectorRegime
  Catalyst
  TaskTime
  UniverseCandidate
}

/// Content-bound information for the LLM. The payload contains no verdict,
/// score, recommendation, selected operation, or trade field.
pub opaque type Receipt {
  Receipt(family: Family, payload: Json, canonical_content_hash: Sha256)
}

pub type ContextError {
  InvalidText(field: String)
  InvalidInformation(field: String)
  EmptyTaskTimes
  HashFailure
}

pub fn classification(
  scheme scheme_value: String,
  label label_value: String,
  as_of as_of_value: Instant,
  retrieved_at retrieved_at_value: Instant,
  timezone timezone_value: Timezone,
  source source_value: SourceRef,
  source_receipt source_receipt_value: Sha256,
) -> Result(Classification, ContextError) {
  use _ <- result.try(valid_text(scheme_value, "classification.scheme"))
  use _ <- result.try(valid_text(label_value, "classification.label"))
  Ok(Classification(
    scheme_value,
    label_value,
    as_of_value,
    retrieved_at_value,
    timezone_value,
    source_value,
    source_receipt_value,
  ))
}

pub fn catalyst_event(
  event_id event_id_value: String,
  category category_value: String,
  headline headline_value: String,
  source_status source_status_value: String,
  occurrence_time occurrence_time_value: Information(Instant),
  published_at published_at_value: Information(Instant),
  timezone timezone_value: Timezone,
  source source_value: SourceRef,
  source_receipt source_receipt_value: Sha256,
  lineage_receipts lineage_receipt_values: List(Sha256),
) -> Result(CatalystEvent, ContextError) {
  use _ <- result.try(valid_text(event_id_value, "catalyst.event_id"))
  use _ <- result.try(valid_text(category_value, "catalyst.category"))
  use _ <- result.try(valid_text(headline_value, "catalyst.headline"))
  use _ <- result.try(valid_text(source_status_value, "catalyst.source_status"))
  use _ <- result.try(validate_information(
    occurrence_time_value,
    "catalyst.occurrence_time",
  ))
  use _ <- result.try(validate_information(
    published_at_value,
    "catalyst.published_at",
  ))
  Ok(CatalystEvent(
    event_id_value,
    category_value,
    headline_value,
    source_status_value,
    occurrence_time_value,
    published_at_value,
    timezone_value,
    source_value,
    source_receipt_value,
    lineage_receipt_values,
  ))
}

pub fn catalyst_snapshot(
  query_scope query_scope_value: String,
  events event_values: List(CatalystEvent),
) -> Result(CatalystSnapshot, ContextError) {
  use _ <- result.try(valid_text(query_scope_value, "catalyst.query_scope"))
  Ok(CatalystSnapshot(query_scope_value, event_values))
}

pub fn task_time_observation(
  task_id task_id_value: String,
  stage stage_value: String,
  requested_at requested_at_value: Instant,
  context_as_of context_as_of_value: Information(Instant),
  source_cutoff source_cutoff_value: Information(Instant),
  attached_at attached_at_value: Instant,
  timezone timezone_value: Timezone,
  evidence_roots evidence_root_values: List(EvidenceId),
) -> Result(TaskTimeObservation, ContextError) {
  use _ <- result.try(valid_text(task_id_value, "task_time.task_id"))
  use _ <- result.try(valid_text(stage_value, "task_time.stage"))
  use _ <- result.try(validate_information(
    context_as_of_value,
    "task_time.context_as_of",
  ))
  use _ <- result.try(validate_information(
    source_cutoff_value,
    "task_time.source_cutoff",
  ))
  Ok(TaskTimeObservation(
    task_id_value,
    stage_value,
    requested_at_value,
    context_as_of_value,
    source_cutoff_value,
    attached_at_value,
    timezone_value,
    evidence_root_values,
  ))
}

pub fn source_field(
  name name_value: String,
  value value_value: String,
) -> Result(SourceField, ContextError) {
  use _ <- result.try(valid_text(name_value, "universe.source_field.name"))
  use _ <- result.try(valid_text(value_value, "universe.source_field.value"))
  Ok(SourceField(name_value, value_value))
}

pub fn universe_candidate_observation(
  universe_id universe_id_value: String,
  definition_version definition_version_value: String,
  query_scope query_scope_value: String,
  source_row_id source_row_id_value: String,
  source_declared_membership source_declared_membership_value: String,
  source_declared_reasons source_declared_reason_values: List(String),
  source_fields source_field_values: List(SourceField),
  as_of as_of_value: Instant,
  source_cutoff source_cutoff_value: Instant,
  retrieved_at retrieved_at_value: Instant,
  timezone timezone_value: Timezone,
  source source_value: SourceRef,
  source_receipt source_receipt_value: Sha256,
  universe_receipt universe_receipt_value: Sha256,
  evidence_roots evidence_root_values: List(EvidenceId),
) -> Result(UniverseCandidateObservation, ContextError) {
  use _ <- result.try(valid_text(universe_id_value, "universe.universe_id"))
  use _ <- result.try(valid_text(
    definition_version_value,
    "universe.definition_version",
  ))
  use _ <- result.try(valid_text(query_scope_value, "universe.query_scope"))
  use _ <- result.try(valid_text(source_row_id_value, "universe.source_row_id"))
  use _ <- result.try(valid_text(
    source_declared_membership_value,
    "universe.source_declared_membership",
  ))
  use _ <- result.try(validate_texts(
    source_declared_reason_values,
    "universe.source_declared_reasons",
  ))
  Ok(UniverseCandidateObservation(
    universe_id_value,
    definition_version_value,
    query_scope_value,
    source_row_id_value,
    source_declared_membership_value,
    source_declared_reason_values,
    source_field_values,
    as_of_value,
    source_cutoff_value,
    retrieved_at_value,
    timezone_value,
    source_value,
    source_receipt_value,
    universe_receipt_value,
    evidence_root_values,
  ))
}

pub fn sector_regime_receipt(
  listing listing_value: Key,
  sector sector_value: Information(Classification),
  regime regime_value: Information(Classification),
  observed_at observed_at_value: Instant,
  evidence_roots evidence_root_values: List(EvidenceId),
  limitations limitation_values: List(String),
) -> Result(Receipt, ContextError) {
  use _ <- result.try(validate_information(sector_value, "sector"))
  use _ <- result.try(validate_information(regime_value, "regime"))
  use _ <- result.try(validate_texts(limitation_values, "limitations"))
  new_receipt(
    SectorRegime,
    "pi-sparkles/sector-regime-observation",
    listing_value,
    [
      #("sector", information_json(sector_value, classification_json)),
      #("regime", information_json(regime_value, classification_json)),
      #(
        "observed_at_unix_ms",
        observed_at_value |> time.unix_milliseconds |> json.int,
      ),
      #("evidence_roots", roots_json(evidence_root_values)),
      #("limitations", json.array(limitation_values, json.string)),
    ],
  )
}

pub fn catalyst_receipt(
  listing listing_value: Key,
  snapshot snapshot_value: Information(CatalystSnapshot),
  observed_at observed_at_value: Instant,
  evidence_roots evidence_root_values: List(EvidenceId),
  limitations limitation_values: List(String),
) -> Result(Receipt, ContextError) {
  use _ <- result.try(validate_information(snapshot_value, "catalyst.snapshot"))
  use _ <- result.try(validate_texts(limitation_values, "limitations"))
  new_receipt(Catalyst, "pi-sparkles/catalyst-observation", listing_value, [
    #("snapshot", information_json(snapshot_value, catalyst_snapshot_json)),
    #(
      "observed_at_unix_ms",
      observed_at_value |> time.unix_milliseconds |> json.int,
    ),
    #("evidence_roots", roots_json(evidence_root_values)),
    #("limitations", json.array(limitation_values, json.string)),
  ])
}

pub fn task_time_receipt(
  listing listing_value: Key,
  observations observation_values: List(TaskTimeObservation),
  limitations limitation_values: List(String),
) -> Result(Receipt, ContextError) {
  case observation_values {
    [] -> Error(EmptyTaskTimes)
    _ -> {
      use _ <- result.try(validate_texts(limitation_values, "limitations"))
      new_receipt(TaskTime, "pi-sparkles/task-time-observation", listing_value, [
        #(
          "observations",
          json.array(observation_values, task_time_observation_json),
        ),
        #("limitations", json.array(limitation_values, json.string)),
      ])
    }
  }
}

pub fn universe_candidate_receipt(
  listing listing_value: Key,
  observation observation_value: Information(UniverseCandidateObservation),
  attached_at attached_at_value: Instant,
  limitations limitation_values: List(String),
) -> Result(Receipt, ContextError) {
  use _ <- result.try(validate_information(
    observation_value,
    "universe.observation",
  ))
  use _ <- result.try(validate_texts(limitation_values, "limitations"))
  new_receipt(
    UniverseCandidate,
    "pi-sparkles/universe-candidate-observation",
    listing_value,
    [
      #(
        "observation",
        information_json(observation_value, universe_candidate_json),
      ),
      #(
        "attached_at_unix_ms",
        attached_at_value |> time.unix_milliseconds |> json.int,
      ),
      #("limitations", json.array(limitation_values, json.string)),
    ],
  )
}

pub fn family(value: Receipt) -> Family {
  value.family
}

pub fn schema(value: Receipt) -> String {
  case value.family {
    SectorRegime -> "finance_strategy/sector_regime_observation_receipt"
    Catalyst -> "finance_strategy/catalyst_observation_receipt"
    TaskTime -> "finance_strategy/task_time_observation_receipt"
    UniverseCandidate ->
      "finance_strategy/universe_candidate_observation_receipt"
  }
}

pub fn payload_json(value: Receipt) -> Json {
  value.payload
}

pub fn payload_text(value: Receipt) -> String {
  value.payload |> json.to_string
}

pub fn canonical_content_hash(value: Receipt) -> Sha256 {
  value.canonical_content_hash
}

pub fn encode(value: Receipt) -> String {
  json.object([
    #("payload", value.payload),
    #(
      "canonical_content_hash",
      value.canonical_content_hash
        |> identity.sha256_value
        |> json.string,
    ),
  ])
  |> json.to_string
}

pub fn verify(value: Receipt) -> Bool {
  case value.payload |> json.to_string |> hash.text {
    Ok(actual) -> actual == value.canonical_content_hash
    Error(_) -> False
  }
}

fn new_receipt(
  family_value: Family,
  payload_schema: String,
  listing_value: Key,
  fields: List(#(String, Json)),
) -> Result(Receipt, ContextError) {
  let payload =
    json.object([
      #("schema", json.string(payload_schema)),
      #("schema_version", json.int(schema_version)),
      #("listing", listing_json(listing_value)),
      ..fields
    ])
  case payload |> json.to_string |> hash.text {
    Ok(content_hash) -> Ok(Receipt(family_value, payload, content_hash))
    Error(_) -> Error(HashFailure)
  }
}

fn classification_json(value: Classification) -> Json {
  json.object([
    #("scheme", json.string(value.scheme)),
    #("source_declared_label", json.string(value.label)),
    #("as_of_unix_ms", value.as_of |> time.unix_milliseconds |> json.int),
    #(
      "retrieved_at_unix_ms",
      value.retrieved_at |> time.unix_milliseconds |> json.int,
    ),
    #("timezone", value.timezone |> time.timezone_name |> json.string),
    #("source", source_json(value.source)),
    #(
      "source_receipt",
      value.source_receipt |> identity.sha256_value |> json.string,
    ),
  ])
}

fn catalyst_snapshot_json(value: CatalystSnapshot) -> Json {
  json.object([
    #("query_scope", json.string(value.query_scope)),
    #("events", json.array(value.events, catalyst_event_json)),
  ])
}

fn catalyst_event_json(value: CatalystEvent) -> Json {
  json.object([
    #("event_id", json.string(value.event_id)),
    #("category", json.string(value.category)),
    #("headline", json.string(value.headline)),
    #("source_status", json.string(value.source_status)),
    #("occurrence_time", information_json(value.occurrence_time, instant_json)),
    #("published_at", information_json(value.published_at, instant_json)),
    #("timezone", value.timezone |> time.timezone_name |> json.string),
    #("source", source_json(value.source)),
    #(
      "source_receipt",
      value.source_receipt |> identity.sha256_value |> json.string,
    ),
    #("lineage_receipts", json.array(value.lineage_receipts, sha_json)),
  ])
}

fn task_time_observation_json(value: TaskTimeObservation) -> Json {
  json.object([
    #("task_id", json.string(value.task_id)),
    #("stage", json.string(value.stage)),
    #(
      "requested_at_unix_ms",
      value.requested_at |> time.unix_milliseconds |> json.int,
    ),
    #("context_as_of", information_json(value.context_as_of, instant_json)),
    #("source_cutoff", information_json(value.source_cutoff, instant_json)),
    #(
      "attached_at_unix_ms",
      value.attached_at |> time.unix_milliseconds |> json.int,
    ),
    #("timezone", value.timezone |> time.timezone_name |> json.string),
    #("evidence_roots", roots_json(value.evidence_roots)),
  ])
}

fn universe_candidate_json(value: UniverseCandidateObservation) -> Json {
  json.object([
    #("universe_id", json.string(value.universe_id)),
    #("definition_version", json.string(value.definition_version)),
    #("query_scope", json.string(value.query_scope)),
    #("source_row_id", json.string(value.source_row_id)),
    #(
      "source_declared_membership",
      json.string(value.source_declared_membership),
    ),
    #(
      "source_declared_reasons",
      json.array(value.source_declared_reasons, json.string),
    ),
    #("source_fields", json.array(value.source_fields, source_field_json)),
    #("as_of_unix_ms", value.as_of |> time.unix_milliseconds |> json.int),
    #(
      "source_cutoff_unix_ms",
      value.source_cutoff |> time.unix_milliseconds |> json.int,
    ),
    #(
      "retrieved_at_unix_ms",
      value.retrieved_at |> time.unix_milliseconds |> json.int,
    ),
    #("timezone", value.timezone |> time.timezone_name |> json.string),
    #("source", source_json(value.source)),
    #(
      "source_receipt",
      value.source_receipt |> identity.sha256_value |> json.string,
    ),
    #(
      "universe_receipt",
      value.universe_receipt |> identity.sha256_value |> json.string,
    ),
    #("evidence_roots", roots_json(value.evidence_roots)),
  ])
}

fn source_field_json(value: SourceField) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("value", json.string(value.value)),
  ])
}

fn information_json(
  value: Information(a),
  encode_value: fn(a) -> Json,
) -> Json {
  case value {
    Known(value) ->
      json.object([
        #("state", json.string("known")),
        #("value", encode_value(value)),
      ])
    Unknown(reason) -> reason_json("unknown", reason)
    NotObtained(reason) -> reason_json("not_obtained", reason)
    Conflicting(alternatives, reason) ->
      json.object([
        #("state", json.string("conflicting")),
        #("alternatives", json.array(alternatives, encode_value)),
        #("reason", json.string(reason)),
      ])
  }
}

fn listing_json(value: Key) -> Json {
  json.object([
    #("track", value |> listing.track |> finance_track.name |> json.string),
    #(
      "instrument_id",
      value
        |> listing.instrument_id
        |> identifier.instrument_id_value
        |> json.string,
    ),
    #(
      "symbol",
      value |> listing.symbol |> identifier.symbol_value |> json.string,
    ),
    #("mic", value |> listing.mic |> identifier.mic_value |> json.string),
  ])
}

fn source_json(value: SourceRef) -> Json {
  json.object([
    #("provider", value |> source.provider |> json.string),
    #("reference", value |> source.reference |> json.string),
    #("kind", value |> source.kind |> source_kind_name |> json.string),
  ])
}

fn source_kind_name(value: source.SourceKind) -> String {
  case value {
    source.Official -> "official"
    source.Exchange -> "exchange"
    source.Regulator -> "regulator"
    source.LicensedVendor -> "licensed_vendor"
    source.UserSupplied -> "user_supplied"
    source.Synthetic -> "synthetic"
    source.Other(kind) -> kind
  }
}

fn roots_json(values: List(EvidenceId)) -> Json {
  json.array(values, fn(value) {
    value |> identity.evidence_id_value |> json.string
  })
}

fn sha_json(value: Sha256) -> Json {
  value |> identity.sha256_value |> json.string
}

fn instant_json(value: Instant) -> Json {
  value |> time.unix_milliseconds |> json.int
}

fn reason_json(state: String, reason: String) -> Json {
  json.object([
    #("state", json.string(state)),
    #("reason", json.string(reason)),
  ])
}

fn validate_information(
  value: Information(a),
  field: String,
) -> Result(Nil, ContextError) {
  case value {
    Known(_) -> Ok(Nil)
    Unknown(reason) | NotObtained(reason) -> valid_text(reason, field)
    Conflicting([], _) -> Error(InvalidInformation(field))
    Conflicting(_, reason) -> valid_text(reason, field)
  }
}

fn validate_texts(
  values: List(String),
  field: String,
) -> Result(Nil, ContextError) {
  case list.all(values, is_valid_text) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn valid_text(value: String, field: String) -> Result(Nil, ContextError) {
  case is_valid_text(value) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn is_valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
