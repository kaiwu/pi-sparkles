import finance_core/time.{type Date}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_track.{type Track}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type PredicateRole {
  Required
  Confirmation
  Ranking
}

/// A provider-neutral dependency named by a strategy definition.
///
/// These are readiness labels, not replacement schemas for the market-owned
/// packages that must eventually produce the underlying evidence.
pub type Requirement {
  ExactIdentity
  CompletedSession
  CompletedDailyData
  AdjustmentProvenance
  SourceRights
  Freshness
  MarketRules
  RiskPolicy
  ExecutionCapability
}

pub opaque type Predicate {
  Predicate(
    id: String,
    role: PredicateRole,
    evidence_key: String,
    description: String,
  )
}

pub opaque type Parameter {
  Parameter(name: String, value: String, unit: String)
}

pub opaque type LifecyclePolicy {
  LifecyclePolicy(
    entry_valid_sessions: Int,
    maximum_holding_sessions: Int,
    monitoring: String,
    trailing_stop_intent: String,
  )
}

pub opaque type Definition {
  Definition(
    id: String,
    version: String,
    hypothesis: String,
    negative_claims: List(String),
    tracks: List(Track),
    valid_from: Date,
    valid_through: Option(Date),
    parameters: List(Parameter),
    predicates: List(Predicate),
    setup_requirements: List(Requirement),
    acceptance_requirements: List(Requirement),
    lifecycle: LifecyclePolicy,
    digest: Sha256,
  )
}

pub type DefinitionError {
  InvalidId
  InvalidVersion
  InvalidHypothesis
  InvalidNegativeClaim
  MissingTrack
  DuplicateTrack
  InvalidValidity
  InvalidPredicate
  DuplicatePredicate(id: String)
  MissingRequiredPredicate
  InvalidParameter
  DuplicateParameter(name: String)
  InvalidLifecycle
  DuplicateRequirement(requirement: Requirement)
}

pub fn predicate(
  id id_value: String,
  role role_value: PredicateRole,
  evidence_key evidence_key_value: String,
  description description_value: String,
) -> Result(Predicate, DefinitionError) {
  case
    valid_identifier(id_value),
    valid_identifier(evidence_key_value),
    valid_text(description_value)
  {
    True, True, True ->
      Ok(Predicate(id_value, role_value, evidence_key_value, description_value))
    _, _, _ -> Error(InvalidPredicate)
  }
}

pub fn parameter(
  name name_value: String,
  value value_value: String,
  unit unit_value: String,
) -> Result(Parameter, DefinitionError) {
  case
    valid_identifier(name_value),
    valid_text(value_value),
    valid_identifier(unit_value)
  {
    True, True, True -> Ok(Parameter(name_value, value_value, unit_value))
    _, _, _ -> Error(InvalidParameter)
  }
}

pub fn lifecycle_policy(
  entry_valid_sessions entry_valid_sessions_value: Int,
  maximum_holding_sessions maximum_holding_sessions_value: Int,
  monitoring monitoring_value: String,
  trailing_stop_intent trailing_stop_intent_value: String,
) -> Result(LifecyclePolicy, DefinitionError) {
  case
    entry_valid_sessions_value > 0,
    maximum_holding_sessions_value > 0,
    valid_identifier(monitoring_value),
    valid_identifier(trailing_stop_intent_value)
  {
    True, True, True, True ->
      Ok(LifecyclePolicy(
        entry_valid_sessions_value,
        maximum_holding_sessions_value,
        monitoring_value,
        trailing_stop_intent_value,
      ))
    _, _, _, _ -> Error(InvalidLifecycle)
  }
}

pub fn new(
  id id_value: String,
  version version_value: String,
  hypothesis hypothesis_value: String,
  negative_claims negative_claim_values: List(String),
  tracks track_values: List(Track),
  valid_from valid_from_value: Date,
  valid_through valid_through_value: Option(Date),
  parameters parameter_values: List(Parameter),
  predicates predicate_values: List(Predicate),
  setup_requirements setup_requirement_values: List(Requirement),
  acceptance_requirements acceptance_requirement_values: List(Requirement),
  lifecycle lifecycle_value: LifecyclePolicy,
) -> Result(Definition, DefinitionError) {
  use _ <- result.try(validate_header(
    id_value,
    version_value,
    hypothesis_value,
    negative_claim_values,
  ))
  use _ <- result.try(validate_tracks(track_values))
  use _ <- result.try(validate_validity(valid_from_value, valid_through_value))
  use _ <- result.try(validate_parameters(parameter_values, []))
  use _ <- result.try(validate_predicates(predicate_values, []))
  use _ <- result.try(validate_requirements(setup_requirement_values, []))
  use _ <- result.try(validate_requirements(acceptance_requirement_values, []))
  let canonical =
    canonical_without_digest(
      id_value,
      version_value,
      hypothesis_value,
      negative_claim_values,
      track_values,
      valid_from_value,
      valid_through_value,
      parameter_values,
      predicate_values,
      setup_requirement_values,
      acceptance_requirement_values,
      lifecycle_value,
    )
  let assert Ok(digest) = hash.text(canonical)
  Ok(Definition(
    id_value,
    version_value,
    hypothesis_value,
    negative_claim_values,
    track_values,
    valid_from_value,
    valid_through_value,
    parameter_values,
    predicate_values,
    setup_requirement_values,
    acceptance_requirement_values,
    lifecycle_value,
    digest,
  ))
}

pub fn id(value: Definition) -> String {
  value.id
}

pub fn version(value: Definition) -> String {
  value.version
}

pub fn hypothesis(value: Definition) -> String {
  value.hypothesis
}

pub fn negative_claims(value: Definition) -> List(String) {
  value.negative_claims
}

pub fn tracks(value: Definition) -> List(Track) {
  value.tracks
}

pub fn valid_from(value: Definition) -> Date {
  value.valid_from
}

pub fn valid_through(value: Definition) -> Option(Date) {
  value.valid_through
}

pub fn parameters(value: Definition) -> List(Parameter) {
  value.parameters
}

pub fn predicates(value: Definition) -> List(Predicate) {
  value.predicates
}

pub fn setup_requirements(value: Definition) -> List(Requirement) {
  value.setup_requirements
}

pub fn acceptance_requirements(value: Definition) -> List(Requirement) {
  value.acceptance_requirements
}

pub fn lifecycle(value: Definition) -> LifecyclePolicy {
  value.lifecycle
}

pub fn digest(value: Definition) -> Sha256 {
  value.digest
}

pub fn effective_on(value: Definition, date: Date) -> Bool {
  date_number(date) >= date_number(value.valid_from)
  && case value.valid_through {
    None -> True
    Some(last) -> date_number(date) <= date_number(last)
  }
}

pub fn canonical_text(value: Definition) -> String {
  canonical_without_digest(
    value.id,
    value.version,
    value.hypothesis,
    value.negative_claims,
    value.tracks,
    value.valid_from,
    value.valid_through,
    value.parameters,
    value.predicates,
    value.setup_requirements,
    value.acceptance_requirements,
    value.lifecycle,
  )
}

pub fn predicate_id(value: Predicate) -> String {
  value.id
}

pub fn predicate_role(value: Predicate) -> PredicateRole {
  value.role
}

pub fn predicate_evidence_key(value: Predicate) -> String {
  value.evidence_key
}

pub fn predicate_description(value: Predicate) -> String {
  value.description
}

pub fn parameter_name(value: Parameter) -> String {
  value.name
}

pub fn parameter_value(value: Parameter) -> String {
  value.value
}

pub fn parameter_unit(value: Parameter) -> String {
  value.unit
}

pub fn entry_valid_sessions(value: LifecyclePolicy) -> Int {
  value.entry_valid_sessions
}

pub fn maximum_holding_sessions(value: LifecyclePolicy) -> Int {
  value.maximum_holding_sessions
}

pub fn monitoring(value: LifecyclePolicy) -> String {
  value.monitoring
}

pub fn trailing_stop_intent(value: LifecyclePolicy) -> String {
  value.trailing_stop_intent
}

pub fn requirement_name(value: Requirement) -> String {
  case value {
    ExactIdentity -> "exact_identity"
    CompletedSession -> "completed_session"
    CompletedDailyData -> "completed_daily_data"
    AdjustmentProvenance -> "adjustment_provenance"
    SourceRights -> "source_rights"
    Freshness -> "freshness"
    MarketRules -> "market_rules"
    RiskPolicy -> "risk_policy"
    ExecutionCapability -> "execution_capability"
  }
}

fn validate_header(
  id: String,
  version: String,
  hypothesis: String,
  negative_claims: List(String),
) -> Result(Nil, DefinitionError) {
  case
    valid_identifier(id),
    valid_version(version),
    valid_text(hypothesis),
    negative_claims != [] && list.all(negative_claims, valid_text)
  {
    False, _, _, _ -> Error(InvalidId)
    _, False, _, _ -> Error(InvalidVersion)
    _, _, False, _ -> Error(InvalidHypothesis)
    _, _, _, False -> Error(InvalidNegativeClaim)
    True, True, True, True -> Ok(Nil)
  }
}

fn validate_tracks(values: List(Track)) -> Result(Nil, DefinitionError) {
  case values {
    [] -> Error(MissingTrack)
    values ->
      case list.length(list.unique(values)) == list.length(values) {
        True -> Ok(Nil)
        False -> Error(DuplicateTrack)
      }
  }
}

fn validate_validity(
  start: Date,
  end: Option(Date),
) -> Result(Nil, DefinitionError) {
  case end {
    None -> Ok(Nil)
    Some(end) ->
      case date_number(end) >= date_number(start) {
        True -> Ok(Nil)
        False -> Error(InvalidValidity)
      }
  }
}

fn validate_parameters(
  values: List(Parameter),
  seen: List(String),
) -> Result(Nil, DefinitionError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case list.contains(seen, value.name) {
        True -> Error(DuplicateParameter(value.name))
        False -> validate_parameters(rest, [value.name, ..seen])
      }
  }
}

fn validate_predicates(
  values: List(Predicate),
  seen: List(String),
) -> Result(Nil, DefinitionError) {
  case values {
    [] -> Error(MissingRequiredPredicate)
    values -> {
      use _ <- result.try(validate_predicate_ids(values, seen))
      case list.any(values, fn(value) { value.role == Required }) {
        True -> Ok(Nil)
        False -> Error(MissingRequiredPredicate)
      }
    }
  }
}

fn validate_predicate_ids(
  values: List(Predicate),
  seen: List(String),
) -> Result(Nil, DefinitionError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case list.contains(seen, value.id) {
        True -> Error(DuplicatePredicate(value.id))
        False -> validate_predicate_ids(rest, [value.id, ..seen])
      }
  }
}

fn validate_requirements(
  values: List(Requirement),
  seen: List(Requirement),
) -> Result(Nil, DefinitionError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case list.contains(seen, value) {
        True -> Error(DuplicateRequirement(value))
        False -> validate_requirements(rest, [value, ..seen])
      }
  }
}

fn canonical_without_digest(
  id: String,
  version: String,
  hypothesis: String,
  negative_claims: List(String),
  tracks: List(Track),
  valid_from: Date,
  valid_through: Option(Date),
  parameters: List(Parameter),
  predicates: List(Predicate),
  setup_requirements: List(Requirement),
  acceptance_requirements: List(Requirement),
  lifecycle: LifecyclePolicy,
) -> String {
  json.object([
    #("schema", json.string("finance_strategy_definition")),
    #("schema_version", json.int(1)),
    #("id", json.string(id)),
    #("version", json.string(version)),
    #("hypothesis", json.string(hypothesis)),
    #("negative_claims", json.array(negative_claims, json.string)),
    #(
      "tracks",
      json.array(tracks, fn(track) {
        track |> finance_track.name |> json.string
      }),
    ),
    #("valid_from", date_json(valid_from)),
    #("valid_through", json.nullable(valid_through, date_json)),
    #("parameters", json.array(parameters, parameter_json)),
    #("predicates", json.array(predicates, predicate_json)),
    #(
      "setup_requirements",
      json.array(setup_requirements, fn(value) {
        value |> requirement_name |> json.string
      }),
    ),
    #(
      "acceptance_requirements",
      json.array(acceptance_requirements, fn(value) {
        value |> requirement_name |> json.string
      }),
    ),
    #("lifecycle", lifecycle_json(lifecycle)),
  ])
  |> json.to_string
}

fn predicate_json(value: Predicate) -> json.Json {
  json.object([
    #("id", json.string(value.id)),
    #("role", json.string(role_name(value.role))),
    #("evidence_key", json.string(value.evidence_key)),
    #("description", json.string(value.description)),
  ])
}

fn parameter_json(value: Parameter) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #("value", json.string(value.value)),
    #("unit", json.string(value.unit)),
  ])
}

fn lifecycle_json(value: LifecyclePolicy) -> json.Json {
  json.object([
    #("entry_valid_sessions", json.int(value.entry_valid_sessions)),
    #("maximum_holding_sessions", json.int(value.maximum_holding_sessions)),
    #("monitoring", json.string(value.monitoring)),
    #("trailing_stop_intent", json.string(value.trailing_stop_intent)),
  ])
}

fn date_json(value: Date) -> json.Json {
  let #(year, month, day) = time.date_parts(value)
  json.object([
    #("year", json.int(year)),
    #("month", json.int(month)),
    #("day", json.int(day)),
  ])
}

fn role_name(value: PredicateRole) -> String {
  case value {
    Required -> "required"
    Confirmation -> "confirmation"
    Ranking -> "ranking"
  }
}

fn valid_version(value: String) -> Bool {
  case string.split(value, ".") {
    [major, minor, patch] ->
      [major, minor, patch]
      |> list.all(fn(part) {
        case int.parse(part) {
          Ok(number) -> number >= 0 && int.to_string(number) == part
          Error(_) -> False
        }
      })
    _ -> False
  }
}

fn valid_identifier(value: String) -> Bool {
  value != ""
  && string.length(value) <= 100
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_.-", character)
    })
  }
}

fn valid_text(value: String) -> Bool {
  value != ""
  && string.length(value) <= 500
  && string.trim(value) == value
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn date_number(value: Date) -> Int {
  let #(year, month, day) = time.date_parts(value)
  year * 10_000 + month * 100 + day
}
