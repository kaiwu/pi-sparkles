import finance_core/identifier
import finance_core/time
import finance_listing/listing
import finance_provenance/hash
import finance_provenance/identity.{type EvidenceId, type Sha256}
import finance_strategy/definition.{
  type Definition, type PredicateRole, type Requirement,
}
import finance_strategy/evidence.{
  type DependencyReceipt, type EvaluationContext, type FeatureReceipt,
  type Readiness,
}
import finance_track
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const schema_version = 1

/// A structural fact about the definition and the evaluation context.
///
/// These values are deliberately not collapsed into a trade or setup decision.
pub type ScopeIssue {
  TrackOutsideDefinition
  DefinitionNotEffective
  ConflictingAdjustmentBasis(first: String, second: String)
}

/// Whether one supplied receipt is compatible with the requested fact.
///
/// `Compatible` only describes shape, identity, timing, warm-up, and upstream
/// readiness. It does not mean the strategy is attractive or actionable.
pub type Compatibility {
  Compatible
  MissingReceipt
  MultipleReceipts(count: Int)
  EvidenceKeyMismatch(expected: String, received: String)
  ListingMismatch
  SessionMismatch
  KnownAfterCutoff(known_at_unix_ms: Int, cutoff_unix_ms: Int)
  SourceCutoffAfterRequestedCutoff(receipt_unix_ms: Int, cutoff_unix_ms: Int)
  WarmupUnavailable(actual_sessions: Int, required_sessions: Int)
  UpstreamReadiness(readiness: Readiness)
}

pub type DependencyFact {
  DependencyFact(
    requirement: Requirement,
    compatibility: Compatibility,
    receipt: Option(DependencyReceipt),
  )
}

pub type PredicateFact {
  PredicateFact(
    id: String,
    role: PredicateRole,
    evidence_key: String,
    description: String,
    compatibility: Compatibility,
    receipts: List(FeatureReceipt),
  )
}

/// Compact, auditable input for an LLM-owned decision.
///
/// There is intentionally no aggregate `qualified`, `accepted`, `rejected`,
/// recommendation, or score field.
pub opaque type StrategyEvidenceReceipt {
  StrategyEvidenceReceipt(
    definition_id: String,
    definition_version: String,
    definition_hash: Sha256,
    input_hash: Sha256,
    context: EvaluationContext,
    scope_issues: List(ScopeIssue),
    setup_dependencies: List(DependencyFact),
    acceptance_dependencies: List(DependencyFact),
    predicate_facts: List(PredicateFact),
    unmatched_features: List(FeatureReceipt),
    evidence_roots: List(EvidenceId),
  )
}

pub fn build(
  definition definition_value: Definition,
  context context_value: EvaluationContext,
  features feature_values: List(FeatureReceipt),
) -> StrategyEvidenceReceipt {
  let predicates = definition.predicates(definition_value)
  let unmatched = unmatched_features_for(predicates, feature_values)
  let ordered_features =
    list.append(
      list.flat_map(predicates, fn(predicate) {
        list.filter(feature_values, fn(feature) {
          definition.predicate_id(predicate) == evidence.predicate_id(feature)
        })
      }),
      unmatched,
    )
  let input_hash =
    input_hash_for(
      definition.digest(definition_value),
      context_value,
      ordered_features,
    )
  StrategyEvidenceReceipt(
    definition.id(definition_value),
    definition.version(definition_value),
    definition.digest(definition_value),
    input_hash,
    context_value,
    scope_issues_for(definition_value, context_value, feature_values),
    dependency_facts(
      definition.setup_requirements(definition_value),
      context_value,
    ),
    dependency_facts(
      definition.acceptance_requirements(definition_value),
      context_value,
    ),
    list.map(predicates, fn(predicate) {
      predicate_fact(predicate, context_value, feature_values)
    }),
    unmatched,
    collect_roots(context_value, ordered_features),
  )
}

pub fn definition_id(value: StrategyEvidenceReceipt) -> String {
  value.definition_id
}

pub fn definition_version(value: StrategyEvidenceReceipt) -> String {
  value.definition_version
}

pub fn definition_hash(value: StrategyEvidenceReceipt) -> Sha256 {
  value.definition_hash
}

pub fn input_hash(value: StrategyEvidenceReceipt) -> Sha256 {
  value.input_hash
}

pub fn context(value: StrategyEvidenceReceipt) -> EvaluationContext {
  value.context
}

pub fn scope_issues(value: StrategyEvidenceReceipt) -> List(ScopeIssue) {
  value.scope_issues
}

pub fn setup_dependencies(
  value: StrategyEvidenceReceipt,
) -> List(DependencyFact) {
  value.setup_dependencies
}

pub fn acceptance_dependencies(
  value: StrategyEvidenceReceipt,
) -> List(DependencyFact) {
  value.acceptance_dependencies
}

pub fn predicate_facts(value: StrategyEvidenceReceipt) -> List(PredicateFact) {
  value.predicate_facts
}

pub fn unmatched_features(
  value: StrategyEvidenceReceipt,
) -> List(FeatureReceipt) {
  value.unmatched_features
}

pub fn evidence_roots(value: StrategyEvidenceReceipt) -> List(EvidenceId) {
  value.evidence_roots
}

pub fn encode(value: StrategyEvidenceReceipt) -> String {
  value |> to_json |> json.to_string
}

pub fn to_json(value: StrategyEvidenceReceipt) -> Json {
  json.object([
    #("schema", json.string("finance_strategy_evidence")),
    #("schema_version", json.int(schema_version)),
    #("definition_id", json.string(value.definition_id)),
    #("definition_version", json.string(value.definition_version)),
    #(
      "definition_hash",
      value.definition_hash |> identity.sha256_value |> json.string,
    ),
    #("input_hash", value.input_hash |> identity.sha256_value |> json.string),
    #("context", evidence.context_to_json(value.context)),
    #("scope_issues", json.array(value.scope_issues, scope_issue_json)),
    #(
      "setup_dependencies",
      json.array(value.setup_dependencies, dependency_fact_json),
    ),
    #(
      "acceptance_dependencies",
      json.array(value.acceptance_dependencies, dependency_fact_json),
    ),
    #("predicate_facts", json.array(value.predicate_facts, predicate_fact_json)),
    #(
      "unmatched_features",
      json.array(value.unmatched_features, evidence.feature_to_json),
    ),
    #("evidence_roots", roots_json(value.evidence_roots)),
  ])
}

pub fn decode(
  input: String,
) -> Result(StrategyEvidenceReceipt, json.DecodeError) {
  json.parse(input, decoder())
}

pub fn decoder() -> decode.Decoder(StrategyEvidenceReceipt) {
  use schema <- decode.field("schema", decode.string)
  use version <- decode.field("schema_version", decode.int)
  use definition_id <- decode.field("definition_id", decode.string)
  use definition_version <- decode.field("definition_version", decode.string)
  use definition_hash <- decode.field("definition_hash", sha_decoder())
  use input_hash <- decode.field("input_hash", sha_decoder())
  use context <- decode.field("context", evidence.context_decoder())
  use scope_issues <- decode.field(
    "scope_issues",
    decode.list(of: scope_issue_decoder()),
  )
  use setup_dependencies <- decode.field(
    "setup_dependencies",
    decode.list(of: dependency_fact_decoder()),
  )
  use acceptance_dependencies <- decode.field(
    "acceptance_dependencies",
    decode.list(of: dependency_fact_decoder()),
  )
  use predicate_facts <- decode.field(
    "predicate_facts",
    decode.list(of: predicate_fact_decoder()),
  )
  use unmatched_features <- decode.field(
    "unmatched_features",
    decode.list(of: evidence.feature_decoder()),
  )
  use roots <- decode.field("evidence_roots", roots_decoder())
  let value =
    StrategyEvidenceReceipt(
      definition_id,
      definition_version,
      definition_hash,
      input_hash,
      context,
      scope_issues,
      setup_dependencies,
      acceptance_dependencies,
      predicate_facts,
      unmatched_features,
      roots,
    )
  case
    schema == "finance_strategy_evidence",
    version == schema_version,
    wire_consistent(value)
  {
    True, True, True -> decode.success(value)
    _, _, _ ->
      decode.failure(
        placeholder_receipt(),
        "valid finance strategy evidence v1",
      )
  }
}

fn unmatched_features_for(
  predicates: List(definition.Predicate),
  features: List(FeatureReceipt),
) -> List(FeatureReceipt) {
  list.filter(features, fn(feature) {
    !list.any(predicates, fn(predicate) {
      definition.predicate_id(predicate) == evidence.predicate_id(feature)
    })
  })
}

fn input_hash_for(
  definition_hash: Sha256,
  context: EvaluationContext,
  features: List(FeatureReceipt),
) -> Sha256 {
  let input_text =
    json.object([
      #(
        "definition_hash",
        definition_hash |> identity.sha256_value |> json.string,
      ),
      #("context", evidence.context_to_json(context)),
      #("features", json.array(features, evidence.feature_to_json)),
    ])
    |> json.to_string
  let assert Ok(value) = hash.text(input_text)
  value
}

fn wire_consistent(value: StrategyEvidenceReceipt) -> Bool {
  let features = wire_features(value)
  value.input_hash
  == input_hash_for(value.definition_hash, value.context, features)
  && value.evidence_roots == collect_roots(value.context, features)
  && unique_dependency_requirements(value)
  && unique_predicate_ids(value.predicate_facts)
  && list.all(value.setup_dependencies, fn(fact) {
    dependency_fact_consistent(fact, value.context)
  })
  && list.all(value.acceptance_dependencies, fn(fact) {
    dependency_fact_consistent(fact, value.context)
  })
  && list.all(value.predicate_facts, fn(fact) {
    predicate_fact_consistent(fact, value.context)
  })
  && list.all(value.unmatched_features, fn(feature) {
    !list.any(value.predicate_facts, fn(fact) {
      fact.id == evidence.predicate_id(feature)
    })
  })
  && adjustment_issue_consistent(value.scope_issues, features)
}

fn wire_features(value: StrategyEvidenceReceipt) -> List(FeatureReceipt) {
  list.append(
    list.flat_map(value.predicate_facts, fn(fact) { fact.receipts }),
    value.unmatched_features,
  )
}

fn dependency_fact_consistent(
  fact: DependencyFact,
  context: EvaluationContext,
) -> Bool {
  case fact.receipt {
    None -> fact.compatibility == MissingReceipt
    Some(value) ->
      fact.requirement == evidence.dependency_requirement(value)
      && fact.compatibility == dependency_compatibility(value, context)
  }
}

fn predicate_fact_consistent(
  fact: PredicateFact,
  context: EvaluationContext,
) -> Bool {
  let ids_match =
    list.all(fact.receipts, fn(value) {
      evidence.predicate_id(value) == fact.id
    })
  let expected = case fact.receipts {
    [] -> MissingReceipt
    [feature] -> feature_compatibility(fact.evidence_key, feature, context)
    many -> MultipleReceipts(list.length(many))
  }
  ids_match && fact.compatibility == expected
}

fn unique_dependency_requirements(value: StrategyEvidenceReceipt) -> Bool {
  let requirements =
    list.append(value.setup_dependencies, value.acceptance_dependencies)
    |> list.map(fn(fact) { fact.requirement })
  list.length(requirements) == list.length(list.unique(requirements))
}

fn unique_predicate_ids(values: List(PredicateFact)) -> Bool {
  let ids = list.map(values, fn(value) { value.id })
  list.length(ids) == list.length(list.unique(ids))
}

fn adjustment_issue_consistent(
  issues: List(ScopeIssue),
  features: List(FeatureReceipt),
) -> Bool {
  let conflicts =
    list.filter(issues, fn(value) {
      case value {
        ConflictingAdjustmentBasis(_, _) -> True
        _ -> False
      }
    })
  case distinct_price_bases(features, []) {
    [first, second, ..] ->
      conflicts == [ConflictingAdjustmentBasis(first, second)]
    _ -> conflicts == []
  }
}

fn scope_issues_for(
  definition_value: Definition,
  context: EvaluationContext,
  features: List(FeatureReceipt),
) -> List(ScopeIssue) {
  []
  |> append_if(
    !list.contains(
      definition.tracks(definition_value),
      context
        |> evidence.context_listing
        |> listing.track,
    ),
    TrackOutsideDefinition,
  )
  |> append_if(
    !definition.effective_on(definition_value, evidence.signal_session(context)),
    DefinitionNotEffective,
  )
  |> append_adjustment_issue(features)
}

fn append_adjustment_issue(
  issues: List(ScopeIssue),
  features: List(FeatureReceipt),
) -> List(ScopeIssue) {
  case distinct_price_bases(features, []) {
    [first, second, ..] ->
      list.append(issues, [ConflictingAdjustmentBasis(first, second)])
    _ -> issues
  }
}

fn distinct_price_bases(
  features: List(FeatureReceipt),
  found: List(String),
) -> List(String) {
  case features {
    [] -> found
    [feature, ..rest] ->
      case evidence.price_dependency(feature) {
        evidence.NotPriceDependent -> distinct_price_bases(rest, found)
        evidence.PriceDependent(basis) ->
          case list.contains(found, basis) {
            True -> distinct_price_bases(rest, found)
            False -> distinct_price_bases(rest, list.append(found, [basis]))
          }
      }
  }
}

fn dependency_facts(
  requirements: List(Requirement),
  context: EvaluationContext,
) -> List(DependencyFact) {
  list.map(requirements, fn(requirement) {
    let matches =
      context
      |> evidence.dependencies
      |> list.filter(fn(receipt) {
        evidence.dependency_requirement(receipt) == requirement
      })
    case matches {
      [] -> DependencyFact(requirement, MissingReceipt, None)
      [receipt] ->
        DependencyFact(
          requirement,
          dependency_compatibility(receipt, context),
          Some(receipt),
        )
      many ->
        DependencyFact(requirement, MultipleReceipts(list.length(many)), None)
    }
  })
}

fn dependency_compatibility(
  receipt: DependencyReceipt,
  context: EvaluationContext,
) -> Compatibility {
  case evidence.dependency_readiness(receipt) {
    evidence.Ready ->
      case evidence.dependency_known_at(receipt) {
        Some(known_at) ->
          late_or_compatible(
            time.unix_milliseconds(known_at),
            time.unix_milliseconds(evidence.context_source_cutoff(context)),
          )
        None -> UpstreamReadiness(evidence.Missing("known_at"))
      }
    readiness -> UpstreamReadiness(readiness)
  }
}

fn predicate_fact(
  predicate: definition.Predicate,
  context: EvaluationContext,
  features: List(FeatureReceipt),
) -> PredicateFact {
  let matching =
    list.filter(features, fn(feature) {
      evidence.predicate_id(feature) == definition.predicate_id(predicate)
    })
  let compatibility = case matching {
    [] -> MissingReceipt
    [feature] ->
      feature_compatibility(
        definition.predicate_evidence_key(predicate),
        feature,
        context,
      )
    many -> MultipleReceipts(list.length(many))
  }
  PredicateFact(
    definition.predicate_id(predicate),
    definition.predicate_role(predicate),
    definition.predicate_evidence_key(predicate),
    definition.predicate_description(predicate),
    compatibility,
    matching,
  )
}

fn feature_compatibility(
  expected_evidence_key: String,
  feature: FeatureReceipt,
  context: EvaluationContext,
) -> Compatibility {
  case
    evidence.feature_id(feature) == expected_evidence_key,
    evidence.listing(feature) == evidence.context_listing(context),
    evidence.session(feature) == evidence.signal_session(context)
  {
    False, _, _ ->
      EvidenceKeyMismatch(expected_evidence_key, evidence.feature_id(feature))
    _, False, _ -> ListingMismatch
    _, _, False -> SessionMismatch
    True, True, True -> ready_feature_compatibility(feature, context)
  }
}

fn ready_feature_compatibility(
  feature: FeatureReceipt,
  context: EvaluationContext,
) -> Compatibility {
  case evidence.readiness(feature) {
    evidence.Ready -> warm_feature_compatibility(feature, context)
    readiness -> UpstreamReadiness(readiness)
  }
}

fn warm_feature_compatibility(
  feature: FeatureReceipt,
  context: EvaluationContext,
) -> Compatibility {
  case evidence.warmup(feature) {
    evidence.WarmupIncomplete(actual, required)
    | evidence.WarmupResetAfterSuspension(actual, required) ->
      WarmupUnavailable(actual, required)
    evidence.WarmupComplete(_, _) -> {
      let cutoff =
        context |> evidence.context_source_cutoff |> time.unix_milliseconds
      let feature_cutoff =
        feature |> evidence.source_cutoff |> time.unix_milliseconds
      case feature_cutoff > cutoff {
        True -> SourceCutoffAfterRequestedCutoff(feature_cutoff, cutoff)
        False ->
          late_or_compatible(
            feature |> evidence.known_at |> time.unix_milliseconds,
            cutoff,
          )
      }
    }
  }
}

fn late_or_compatible(known_at: Int, cutoff: Int) -> Compatibility {
  case known_at > cutoff {
    True -> KnownAfterCutoff(known_at, cutoff)
    False -> Compatible
  }
}

fn collect_roots(
  context: EvaluationContext,
  features: List(FeatureReceipt),
) -> List(EvidenceId) {
  let dependency_roots =
    context
    |> evidence.dependencies
    |> list.flat_map(evidence.dependency_evidence_roots)
  let feature_roots = list.flat_map(features, evidence.feature_evidence_roots)
  list.append(
    evidence.context_evidence_roots(context),
    list.append(dependency_roots, feature_roots),
  )
  |> unique_roots([])
}

fn unique_roots(
  values: List(EvidenceId),
  found: List(EvidenceId),
) -> List(EvidenceId) {
  case values {
    [] -> found
    [value, ..rest] ->
      case list.contains(found, value) {
        True -> unique_roots(rest, found)
        False -> unique_roots(rest, list.append(found, [value]))
      }
  }
}

fn scope_issue_json(value: ScopeIssue) -> Json {
  case value {
    TrackOutsideDefinition -> tagged("track_outside_definition")
    DefinitionNotEffective -> tagged("definition_not_effective")
    ConflictingAdjustmentBasis(first, second) ->
      json.object([
        #("state", json.string("conflicting_adjustment_basis")),
        #("first", json.string(first)),
        #("second", json.string(second)),
      ])
  }
}

fn dependency_fact_json(value: DependencyFact) -> Json {
  json.object([
    #(
      "requirement",
      value.requirement |> definition.requirement_name |> json.string,
    ),
    #("compatibility", compatibility_json(value.compatibility)),
    #("receipt", json.nullable(value.receipt, evidence.dependency_to_json)),
  ])
}

fn predicate_fact_json(value: PredicateFact) -> Json {
  json.object([
    #("id", json.string(value.id)),
    #("role", value.role |> role_name |> json.string),
    #("evidence_key", json.string(value.evidence_key)),
    #("description", json.string(value.description)),
    #("compatibility", compatibility_json(value.compatibility)),
    #("receipts", json.array(value.receipts, evidence.feature_to_json)),
  ])
}

fn compatibility_json(value: Compatibility) -> Json {
  case value {
    Compatible -> tagged("compatible")
    MissingReceipt -> tagged("missing_receipt")
    MultipleReceipts(count) ->
      state_with_int("multiple_receipts", "count", count)
    EvidenceKeyMismatch(expected, received) ->
      json.object([
        #("state", json.string("evidence_key_mismatch")),
        #("expected", json.string(expected)),
        #("received", json.string(received)),
      ])
    ListingMismatch -> tagged("listing_mismatch")
    SessionMismatch -> tagged("session_mismatch")
    KnownAfterCutoff(known_at, cutoff) ->
      timing_json("known_after_cutoff", known_at, cutoff)
    SourceCutoffAfterRequestedCutoff(receipt, cutoff) ->
      timing_json("source_cutoff_after_requested_cutoff", receipt, cutoff)
    WarmupUnavailable(actual, required) ->
      json.object([
        #("state", json.string("warmup_unavailable")),
        #("actual_sessions", json.int(actual)),
        #("required_sessions", json.int(required)),
      ])
    UpstreamReadiness(readiness) ->
      json.object([
        #("state", json.string("upstream_readiness")),
        #(
          "readiness_state",
          readiness |> evidence.readiness_name |> json.string,
        ),
        #(
          "readiness_detail",
          readiness |> evidence.readiness_detail |> json.nullable(json.string),
        ),
      ])
  }
}

fn scope_issue_decoder() -> decode.Decoder(ScopeIssue) {
  use state <- decode.field("state", decode.string)
  case state {
    "track_outside_definition" -> decode.success(TrackOutsideDefinition)
    "definition_not_effective" -> decode.success(DefinitionNotEffective)
    "conflicting_adjustment_basis" -> {
      use first <- decode.field("first", decode.string)
      use second <- decode.field("second", decode.string)
      decode.success(ConflictingAdjustmentBasis(first, second))
    }
    _ -> decode.failure(DefinitionNotEffective, "known scope issue")
  }
}

fn dependency_fact_decoder() -> decode.Decoder(DependencyFact) {
  use requirement <- decode.field("requirement", requirement_decoder())
  use compatibility <- decode.field("compatibility", compatibility_decoder())
  use receipt <- decode.field(
    "receipt",
    decode.optional(evidence.dependency_decoder()),
  )
  decode.success(DependencyFact(requirement, compatibility, receipt))
}

fn predicate_fact_decoder() -> decode.Decoder(PredicateFact) {
  use id <- decode.field("id", decode.string)
  use role <- decode.field("role", role_decoder())
  use evidence_key <- decode.field("evidence_key", decode.string)
  use description <- decode.field("description", decode.string)
  use compatibility <- decode.field("compatibility", compatibility_decoder())
  use receipts <- decode.field(
    "receipts",
    decode.list(of: evidence.feature_decoder()),
  )
  decode.success(PredicateFact(
    id,
    role,
    evidence_key,
    description,
    compatibility,
    receipts,
  ))
}

fn compatibility_decoder() -> decode.Decoder(Compatibility) {
  use state <- decode.field("state", decode.string)
  case state {
    "compatible" -> decode.success(Compatible)
    "missing_receipt" -> decode.success(MissingReceipt)
    "multiple_receipts" -> {
      use count <- decode.field("count", decode.int)
      decode.success(MultipleReceipts(count))
    }
    "evidence_key_mismatch" -> {
      use expected <- decode.field("expected", decode.string)
      use received <- decode.field("received", decode.string)
      decode.success(EvidenceKeyMismatch(expected, received))
    }
    "listing_mismatch" -> decode.success(ListingMismatch)
    "session_mismatch" -> decode.success(SessionMismatch)
    "known_after_cutoff" -> timing_decoder(KnownAfterCutoff)
    "source_cutoff_after_requested_cutoff" ->
      timing_decoder(SourceCutoffAfterRequestedCutoff)
    "warmup_unavailable" -> {
      use actual <- decode.field("actual_sessions", decode.int)
      use required <- decode.field("required_sessions", decode.int)
      decode.success(WarmupUnavailable(actual, required))
    }
    "upstream_readiness" -> {
      use readiness_state <- decode.field("readiness_state", decode.string)
      use readiness_detail <- decode.field(
        "readiness_detail",
        decode.optional(decode.string),
      )
      case readiness_from_wire(readiness_state, readiness_detail) {
        Ok(value) -> decode.success(UpstreamReadiness(value))
        Error(_) ->
          decode.failure(MissingReceipt, "valid upstream readiness state")
      }
    }
    _ -> decode.failure(MissingReceipt, "known compatibility state")
  }
}

fn timing_decoder(
  constructor: fn(Int, Int) -> Compatibility,
) -> decode.Decoder(Compatibility) {
  use value <- decode.field("value_unix_ms", decode.int)
  use cutoff <- decode.field("cutoff_unix_ms", decode.int)
  decode.success(constructor(value, cutoff))
}

fn readiness_from_wire(
  state: String,
  detail: Option(String),
) -> Result(Readiness, Nil) {
  case state, detail {
    "ready", None -> Ok(evidence.Ready)
    "missing", Some(value) -> Ok(evidence.Missing(value))
    "stale", Some(value) -> Ok(evidence.Stale(value))
    "incomplete", Some(value) -> Ok(evidence.Incomplete(value))
    "conflicting", Some(value) -> Ok(evidence.Conflicting(value))
    "unsupported", Some(value) -> Ok(evidence.Unsupported(value))
    "declared", Some(value) -> Ok(evidence.Declared(value))
    _, _ -> Error(Nil)
  }
}

fn role_name(value: PredicateRole) -> String {
  case value {
    definition.Required -> "required"
    definition.Confirmation -> "confirmation"
    definition.Ranking -> "ranking"
  }
}

fn role_decoder() -> decode.Decoder(PredicateRole) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "required" -> decode.success(definition.Required)
      "confirmation" -> decode.success(definition.Confirmation)
      "ranking" -> decode.success(definition.Ranking)
      _ -> decode.failure(definition.Required, "known predicate role")
    }
  })
}

fn requirement_decoder() -> decode.Decoder(Requirement) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "exact_identity" -> decode.success(definition.ExactIdentity)
      "completed_session" -> decode.success(definition.CompletedSession)
      "completed_daily_data" -> decode.success(definition.CompletedDailyData)
      "adjustment_provenance" -> decode.success(definition.AdjustmentProvenance)
      "source_rights" -> decode.success(definition.SourceRights)
      "freshness" -> decode.success(definition.Freshness)
      "market_rules" -> decode.success(definition.MarketRules)
      "risk_policy" -> decode.success(definition.RiskPolicy)
      "execution_capability" -> decode.success(definition.ExecutionCapability)
      _ -> decode.failure(definition.ExactIdentity, "known requirement")
    }
  })
}

fn sha_decoder() -> decode.Decoder(Sha256) {
  let assert Ok(placeholder) = identity.sha256(string.repeat("0", 64))
  decode.string
  |> decode.then(fn(value) {
    case identity.sha256(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder, "SHA-256 hex digest")
    }
  })
}

fn roots_decoder() -> decode.Decoder(List(EvidenceId)) {
  decode.list(of: sha_decoder() |> decode.map(identity.evidence_id))
}

fn roots_json(values: List(EvidenceId)) -> Json {
  json.array(values, fn(value) {
    value |> identity.evidence_id_value |> json.string
  })
}

fn tagged(state: String) -> Json {
  json.object([#("state", json.string(state))])
}

fn state_with_int(state: String, key: String, value: Int) -> Json {
  json.object([#("state", json.string(state)), #(key, json.int(value))])
}

fn timing_json(state: String, value: Int, cutoff: Int) -> Json {
  json.object([
    #("state", json.string(state)),
    #("value_unix_ms", json.int(value)),
    #("cutoff_unix_ms", json.int(cutoff)),
  ])
}

fn append_if(
  values: List(value),
  condition: Bool,
  value: value,
) -> List(value) {
  case condition {
    True -> list.append(values, [value])
    False -> values
  }
}

fn placeholder_receipt() -> StrategyEvidenceReceipt {
  let assert Ok(day) = time.date(1970, 1, 1)
  let assert Ok(at) = time.instant(0)
  let assert Ok(instrument_id) = identifier.instrument_id("placeholder")
  let assert Ok(symbol) = identifier.symbol("PLACEHOLDER")
  let assert Ok(mic) = identifier.mic("XNAS")
  let listing = listing.new(finance_track.Us, instrument_id, symbol, mic)
  let assert Ok(context) =
    evidence.evaluation_context(listing, day, at, at, [], [])
  let assert Ok(digest) = identity.sha256(string.repeat("0", 64))
  StrategyEvidenceReceipt(
    "placeholder",
    "0.0.0",
    digest,
    digest,
    context,
    [],
    [],
    [],
    [],
    [],
    [],
  )
}
