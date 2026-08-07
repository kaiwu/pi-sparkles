import finance_core/identifier
import finance_core/time.{type Date, type Instant}
import finance_listing/listing.{type Key}
import finance_provenance/identity.{type EvidenceId, type Sha256}
import finance_strategy/definition.{type Requirement}
import finance_track
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Readiness supplied by an upstream typed contract.
///
/// `Declared` deliberately does not mean verified. It lets the LLM see a
/// caller statement without this package promoting it to provider or authority
/// evidence.
pub type Readiness {
  Ready
  Missing(reason: String)
  Stale(reason: String)
  Incomplete(reason: String)
  Conflicting(reason: String)
  Unsupported(reason: String)
  Declared(value: String)
}

pub type PredicateObservation {
  ObservedTrue
  ObservedFalse
  Unknown(reason: String)
}

pub type Warmup {
  WarmupComplete(actual_sessions: Int, required_sessions: Int)
  WarmupIncomplete(actual_sessions: Int, required_sessions: Int)
  WarmupResetAfterSuspension(actual_sessions: Int, required_sessions: Int)
}

pub type PriceDependency {
  NotPriceDependent
  PriceDependent(adjustment_basis: String)
}

pub opaque type DependencyReceipt {
  DependencyReceipt(
    requirement: Requirement,
    readiness: Readiness,
    known_at: Option(Instant),
    evidence_roots: List(EvidenceId),
  )
}

pub opaque type FeatureReceipt {
  FeatureReceipt(
    predicate_id: String,
    feature_id: String,
    formula_version: String,
    parameters: List(#(String, String)),
    warmup: Warmup,
    input_series_hash: Sha256,
    listing: Key,
    session: Date,
    price_dependency: PriceDependency,
    unit: String,
    known_at: Instant,
    source_cutoff: Instant,
    readiness: Readiness,
    observation: PredicateObservation,
    evidence_roots: List(EvidenceId),
  )
}

pub opaque type EvaluationContext {
  EvaluationContext(
    listing: Key,
    signal_session: Date,
    evaluated_at: Instant,
    source_cutoff: Instant,
    dependencies: List(DependencyReceipt),
    evidence_roots: List(EvidenceId),
  )
}

pub type EvidenceError {
  InvalidText
  InvalidWarmup
  InvalidParameter
  DuplicateParameter(name: String)
  DuplicateRequirement(requirement: Requirement)
  DuplicateEvidenceRoot(value: String)
  ReadyRequiresKnownAt
  ReadyRequiresEvidence
  ReadyCannotBeDeclaration
  KnownAfterSourceCutoff
  SourceCutoffAfterEvaluation
}

pub fn dependency_receipt(
  requirement requirement_value: Requirement,
  readiness readiness_value: Readiness,
  known_at known_at_value: Option(Instant),
  evidence_roots evidence_root_values: List(EvidenceId),
) -> Result(DependencyReceipt, EvidenceError) {
  use _ <- result.try(validate_readiness(readiness_value))
  use _ <- result.try(validate_roots(evidence_root_values))
  case readiness_value, known_at_value, evidence_root_values {
    Ready, None, _ -> Error(ReadyRequiresKnownAt)
    Ready, _, [] -> Error(ReadyRequiresEvidence)
    Declared(_), _, roots if roots != [] -> Error(ReadyCannotBeDeclaration)
    _, _, _ ->
      Ok(DependencyReceipt(
        requirement_value,
        readiness_value,
        known_at_value,
        evidence_root_values,
      ))
  }
}

pub fn feature_receipt(
  predicate_id predicate_id_value: String,
  feature_id feature_id_value: String,
  formula_version formula_version_value: String,
  parameters parameter_values: List(#(String, String)),
  warmup warmup_value: Warmup,
  input_series_hash input_series_hash_value: Sha256,
  listing listing_value: Key,
  session session_value: Date,
  price_dependency price_dependency_value: PriceDependency,
  unit unit_value: String,
  known_at known_at_value: Instant,
  source_cutoff source_cutoff_value: Instant,
  readiness readiness_value: Readiness,
  observation observation_value: PredicateObservation,
  evidence_roots evidence_root_values: List(EvidenceId),
) -> Result(FeatureReceipt, EvidenceError) {
  use _ <- result.try(validate_feature_text(
    predicate_id_value,
    feature_id_value,
    formula_version_value,
    unit_value,
    price_dependency_value,
  ))
  use _ <- result.try(validate_parameters(parameter_values, []))
  use _ <- result.try(validate_warmup(warmup_value))
  use _ <- result.try(validate_readiness(readiness_value))
  use _ <- result.try(validate_observation(observation_value))
  use _ <- result.try(validate_roots(evidence_root_values))
  use _ <- result.try(validate_feature_evidence(
    readiness_value,
    evidence_root_values,
  ))
  case
    time.unix_milliseconds(known_at_value)
    <= time.unix_milliseconds(source_cutoff_value)
  {
    False -> Error(KnownAfterSourceCutoff)
    True ->
      Ok(FeatureReceipt(
        predicate_id_value,
        feature_id_value,
        formula_version_value,
        parameter_values,
        warmup_value,
        input_series_hash_value,
        listing_value,
        session_value,
        price_dependency_value,
        unit_value,
        known_at_value,
        source_cutoff_value,
        readiness_value,
        observation_value,
        evidence_root_values,
      ))
  }
}

pub fn evaluation_context(
  listing listing_value: Key,
  signal_session signal_session_value: Date,
  evaluated_at evaluated_at_value: Instant,
  source_cutoff source_cutoff_value: Instant,
  dependencies dependency_values: List(DependencyReceipt),
  evidence_roots evidence_root_values: List(EvidenceId),
) -> Result(EvaluationContext, EvidenceError) {
  use _ <- result.try(validate_dependencies(dependency_values, []))
  use _ <- result.try(validate_roots(evidence_root_values))
  case
    time.unix_milliseconds(source_cutoff_value)
    <= time.unix_milliseconds(evaluated_at_value)
  {
    False -> Error(SourceCutoffAfterEvaluation)
    True ->
      Ok(EvaluationContext(
        listing_value,
        signal_session_value,
        evaluated_at_value,
        source_cutoff_value,
        dependency_values,
        evidence_root_values,
      ))
  }
}

pub fn dependency_requirement(value: DependencyReceipt) -> Requirement {
  value.requirement
}

pub fn dependency_readiness(value: DependencyReceipt) -> Readiness {
  value.readiness
}

pub fn dependency_known_at(value: DependencyReceipt) -> Option(Instant) {
  value.known_at
}

pub fn dependency_evidence_roots(value: DependencyReceipt) -> List(EvidenceId) {
  value.evidence_roots
}

pub fn predicate_id(value: FeatureReceipt) -> String {
  value.predicate_id
}

pub fn feature_id(value: FeatureReceipt) -> String {
  value.feature_id
}

pub fn formula_version(value: FeatureReceipt) -> String {
  value.formula_version
}

pub fn parameters(value: FeatureReceipt) -> List(#(String, String)) {
  value.parameters
}

pub fn warmup(value: FeatureReceipt) -> Warmup {
  value.warmup
}

pub fn input_series_hash(value: FeatureReceipt) -> Sha256 {
  value.input_series_hash
}

pub fn listing(value: FeatureReceipt) -> Key {
  value.listing
}

pub fn session(value: FeatureReceipt) -> Date {
  value.session
}

pub fn price_dependency(value: FeatureReceipt) -> PriceDependency {
  value.price_dependency
}

pub fn unit(value: FeatureReceipt) -> String {
  value.unit
}

pub fn known_at(value: FeatureReceipt) -> Instant {
  value.known_at
}

pub fn source_cutoff(value: FeatureReceipt) -> Instant {
  value.source_cutoff
}

pub fn readiness(value: FeatureReceipt) -> Readiness {
  value.readiness
}

pub fn observation(value: FeatureReceipt) -> PredicateObservation {
  value.observation
}

pub fn feature_evidence_roots(value: FeatureReceipt) -> List(EvidenceId) {
  value.evidence_roots
}

pub fn context_listing(value: EvaluationContext) -> Key {
  value.listing
}

pub fn signal_session(value: EvaluationContext) -> Date {
  value.signal_session
}

pub fn evaluated_at(value: EvaluationContext) -> Instant {
  value.evaluated_at
}

pub fn context_source_cutoff(value: EvaluationContext) -> Instant {
  value.source_cutoff
}

pub fn dependencies(value: EvaluationContext) -> List(DependencyReceipt) {
  value.dependencies
}

pub fn context_evidence_roots(value: EvaluationContext) -> List(EvidenceId) {
  value.evidence_roots
}

pub fn readiness_name(value: Readiness) -> String {
  case value {
    Ready -> "ready"
    Missing(_) -> "missing"
    Stale(_) -> "stale"
    Incomplete(_) -> "incomplete"
    Conflicting(_) -> "conflicting"
    Unsupported(_) -> "unsupported"
    Declared(_) -> "declared"
  }
}

pub fn readiness_detail(value: Readiness) -> Option(String) {
  case value {
    Ready -> None
    Missing(value)
    | Stale(value)
    | Incomplete(value)
    | Conflicting(value)
    | Unsupported(value)
    | Declared(value) -> Some(value)
  }
}

pub fn canonical_context(value: EvaluationContext) -> String {
  json.object([
    #("listing", listing_json(value.listing)),
    #("signal_session", date_json(value.signal_session)),
    #(
      "evaluated_at_unix_ms",
      value.evaluated_at
        |> time.unix_milliseconds
        |> int.to_string
        |> json.string,
    ),
    #(
      "source_cutoff_unix_ms",
      value.source_cutoff
        |> time.unix_milliseconds
        |> int.to_string
        |> json.string,
    ),
    #("dependencies", json.array(value.dependencies, dependency_json)),
    #("evidence_roots", roots_json(value.evidence_roots)),
  ])
  |> json.to_string
}

pub fn canonical_feature(value: FeatureReceipt) -> String {
  feature_json(value) |> json.to_string
}

pub fn dependency_to_json(value: DependencyReceipt) -> json.Json {
  dependency_json(value)
}

pub fn feature_to_json(value: FeatureReceipt) -> json.Json {
  feature_json(value)
}

pub fn context_to_json(value: EvaluationContext) -> json.Json {
  json.object([
    #("listing", listing_json(value.listing)),
    #("signal_session", date_json(value.signal_session)),
    #(
      "evaluated_at_unix_ms",
      value.evaluated_at
        |> time.unix_milliseconds
        |> int.to_string
        |> json.string,
    ),
    #(
      "source_cutoff_unix_ms",
      value.source_cutoff
        |> time.unix_milliseconds
        |> int.to_string
        |> json.string,
    ),
    #("dependencies", json.array(value.dependencies, dependency_json)),
    #("evidence_roots", roots_json(value.evidence_roots)),
  ])
}

pub fn dependency_decoder() -> decode.Decoder(DependencyReceipt) {
  use requirement <- decode.field("requirement", requirement_decoder())
  use readiness <- decode.field("readiness", readiness_decoder())
  use known_at <- decode.field(
    "known_at_unix_ms",
    decode.optional(instant_string_decoder()),
  )
  use roots <- decode.field("evidence_roots", roots_decoder())
  case dependency_receipt(requirement, readiness, known_at, roots) {
    Ok(value) -> decode.success(value)
    Error(_) ->
      decode.failure(placeholder_dependency(), "valid dependency receipt")
  }
}

pub fn feature_decoder() -> decode.Decoder(FeatureReceipt) {
  use predicate_id <- decode.field("predicate_id", decode.string)
  use feature_id <- decode.field("feature_id", decode.string)
  use formula_version <- decode.field("formula_version", decode.string)
  use parameters <- decode.field(
    "parameters",
    decode.list(of: parameter_decoder()),
  )
  use warmup <- decode.field("warmup", warmup_decoder())
  use input_hash <- decode.field("input_series_hash", sha_decoder())
  use listing <- decode.field("listing", listing_decoder())
  use session <- decode.field("session", date_decoder())
  use price_dependency <- decode.field(
    "price_dependency",
    price_dependency_decoder(),
  )
  use unit <- decode.field("unit", decode.string)
  use known_at <- decode.field("known_at_unix_ms", instant_string_decoder())
  use source_cutoff <- decode.field(
    "source_cutoff_unix_ms",
    instant_string_decoder(),
  )
  use readiness <- decode.field("readiness", readiness_decoder())
  use observation <- decode.field("observation", observation_decoder())
  use roots <- decode.field("evidence_roots", roots_decoder())
  case
    feature_receipt(
      predicate_id,
      feature_id,
      formula_version,
      parameters,
      warmup,
      input_hash,
      listing,
      session,
      price_dependency,
      unit,
      known_at,
      source_cutoff,
      readiness,
      observation,
      roots,
    )
  {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(placeholder_feature(), "valid feature receipt")
  }
}

pub fn context_decoder() -> decode.Decoder(EvaluationContext) {
  use listing <- decode.field("listing", listing_decoder())
  use signal_session <- decode.field("signal_session", date_decoder())
  use evaluated_at <- decode.field(
    "evaluated_at_unix_ms",
    instant_string_decoder(),
  )
  use source_cutoff <- decode.field(
    "source_cutoff_unix_ms",
    instant_string_decoder(),
  )
  use dependencies <- decode.field(
    "dependencies",
    decode.list(of: dependency_decoder()),
  )
  use roots <- decode.field("evidence_roots", roots_decoder())
  case
    evaluation_context(
      listing,
      signal_session,
      evaluated_at,
      source_cutoff,
      dependencies,
      roots,
    )
  {
    Ok(value) -> decode.success(value)
    Error(_) ->
      decode.failure(placeholder_context(), "valid strategy evidence context")
  }
}

fn dependency_json(value: DependencyReceipt) -> json.Json {
  json.object([
    #(
      "requirement",
      value.requirement |> definition.requirement_name |> json.string,
    ),
    #("readiness", readiness_json(value.readiness)),
    #(
      "known_at_unix_ms",
      json.nullable(value.known_at, fn(value) {
        value |> time.unix_milliseconds |> int.to_string |> json.string
      }),
    ),
    #("evidence_roots", roots_json(value.evidence_roots)),
  ])
}

fn feature_json(value: FeatureReceipt) -> json.Json {
  json.object([
    #("predicate_id", json.string(value.predicate_id)),
    #("feature_id", json.string(value.feature_id)),
    #("formula_version", json.string(value.formula_version)),
    #(
      "parameters",
      json.array(value.parameters, fn(parameter) {
        json.object([
          #("name", json.string(parameter.0)),
          #("value", json.string(parameter.1)),
        ])
      }),
    ),
    #("warmup", warmup_json(value.warmup)),
    #(
      "input_series_hash",
      value.input_series_hash |> identity.sha256_value |> json.string,
    ),
    #("listing", listing_json(value.listing)),
    #("session", date_json(value.session)),
    #("price_dependency", price_dependency_json(value.price_dependency)),
    #("unit", json.string(value.unit)),
    #(
      "known_at_unix_ms",
      value.known_at |> time.unix_milliseconds |> int.to_string |> json.string,
    ),
    #(
      "source_cutoff_unix_ms",
      value.source_cutoff
        |> time.unix_milliseconds
        |> int.to_string
        |> json.string,
    ),
    #("readiness", readiness_json(value.readiness)),
    #("observation", observation_json(value.observation)),
    #("evidence_roots", roots_json(value.evidence_roots)),
  ])
}

fn listing_json(value: Key) -> json.Json {
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
      value
        |> listing.symbol
        |> identifier.symbol_value
        |> json.string,
    ),
    #("mic", value |> listing.mic |> identifier.mic_value |> json.string),
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

fn readiness_json(value: Readiness) -> json.Json {
  json.object([
    #("state", value |> readiness_name |> json.string),
    #("detail", value |> readiness_detail |> json.nullable(json.string)),
  ])
}

fn warmup_json(value: Warmup) -> json.Json {
  let #(state, actual, required) = case value {
    WarmupComplete(actual, required) -> #("complete", actual, required)
    WarmupIncomplete(actual, required) -> #("incomplete", actual, required)
    WarmupResetAfterSuspension(actual, required) -> #(
      "reset_after_suspension",
      actual,
      required,
    )
  }
  json.object([
    #("state", json.string(state)),
    #("actual_sessions", json.int(actual)),
    #("required_sessions", json.int(required)),
  ])
}

fn price_dependency_json(value: PriceDependency) -> json.Json {
  case value {
    NotPriceDependent -> json.object([#("state", json.string("not_price"))])
    PriceDependent(basis) ->
      json.object([
        #("state", json.string("price")),
        #("adjustment_basis", json.string(basis)),
      ])
  }
}

fn observation_json(value: PredicateObservation) -> json.Json {
  case value {
    ObservedTrue -> json.object([#("state", json.string("true"))])
    ObservedFalse -> json.object([#("state", json.string("false"))])
    Unknown(reason) ->
      json.object([
        #("state", json.string("unknown")),
        #("reason", json.string(reason)),
      ])
  }
}

fn roots_json(values: List(EvidenceId)) -> json.Json {
  json.array(values, fn(value) {
    value |> identity.evidence_id_value |> json.string
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
      _ ->
        decode.failure(definition.ExactIdentity, "known strategy requirement")
    }
  })
}

fn readiness_decoder() -> decode.Decoder(Readiness) {
  use state <- decode.field("state", decode.string)
  use detail <- decode.field("detail", decode.optional(decode.string))
  case state, detail {
    "ready", None -> decode.success(Ready)
    "missing", Some(value) -> decode.success(Missing(value))
    "stale", Some(value) -> decode.success(Stale(value))
    "incomplete", Some(value) -> decode.success(Incomplete(value))
    "conflicting", Some(value) -> decode.success(Conflicting(value))
    "unsupported", Some(value) -> decode.success(Unsupported(value))
    "declared", Some(value) -> decode.success(Declared(value))
    _, _ -> decode.failure(Missing("invalid"), "known readiness state")
  }
}

fn parameter_decoder() -> decode.Decoder(#(String, String)) {
  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(#(name, value))
}

fn warmup_decoder() -> decode.Decoder(Warmup) {
  use state <- decode.field("state", decode.string)
  use actual <- decode.field("actual_sessions", decode.int)
  use required <- decode.field("required_sessions", decode.int)
  case state {
    "complete" -> decode.success(WarmupComplete(actual, required))
    "incomplete" -> decode.success(WarmupIncomplete(actual, required))
    "reset_after_suspension" ->
      decode.success(WarmupResetAfterSuspension(actual, required))
    _ -> decode.failure(WarmupIncomplete(0, 1), "known warm-up state")
  }
}

fn price_dependency_decoder() -> decode.Decoder(PriceDependency) {
  use state <- decode.field("state", decode.string)
  case state {
    "not_price" -> decode.success(NotPriceDependent)
    "price" -> {
      use basis <- decode.field("adjustment_basis", decode.string)
      decode.success(PriceDependent(basis))
    }
    _ -> decode.failure(NotPriceDependent, "known price dependency")
  }
}

fn observation_decoder() -> decode.Decoder(PredicateObservation) {
  use state <- decode.field("state", decode.string)
  case state {
    "true" -> decode.success(ObservedTrue)
    "false" -> decode.success(ObservedFalse)
    "unknown" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(Unknown(reason))
    }
    _ -> decode.failure(Unknown("invalid"), "known observation state")
  }
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

fn evidence_id_decoder() -> decode.Decoder(EvidenceId) {
  sha_decoder()
  |> decode.map(identity.evidence_id)
}

fn roots_decoder() -> decode.Decoder(List(EvidenceId)) {
  decode.list(of: evidence_id_decoder())
}

fn instant_string_decoder() -> decode.Decoder(Instant) {
  let assert Ok(placeholder) = time.instant(0)
  decode.string
  |> decode.then(fn(value) {
    case int.parse(value) {
      Ok(milliseconds) ->
        case time.instant(milliseconds) {
          Ok(value) -> decode.success(value)
          Error(_) -> decode.failure(placeholder, "safe Unix milliseconds")
        }
      Error(_) -> decode.failure(placeholder, "Unix milliseconds string")
    }
  })
}

fn date_decoder() -> decode.Decoder(Date) {
  let assert Ok(placeholder) = time.date(1970, 1, 1)
  use year <- decode.field("year", decode.int)
  use month <- decode.field("month", decode.int)
  use day <- decode.field("day", decode.int)
  case time.date(year, month, day) {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(placeholder, "valid Gregorian date")
  }
}

fn listing_decoder() -> decode.Decoder(Key) {
  use track <- decode.field("track", track_decoder())
  use instrument_id <- decode.field("instrument_id", decode.string)
  use symbol <- decode.field("symbol", decode.string)
  use mic <- decode.field("mic", decode.string)
  case
    identifier.instrument_id(instrument_id),
    identifier.symbol(symbol),
    identifier.mic(mic)
  {
    Ok(instrument_id), Ok(symbol), Ok(mic) ->
      decode.success(listing.new(track, instrument_id, symbol, mic))
    _, _, _ -> decode.failure(placeholder_listing(), "valid listing identity")
  }
}

fn track_decoder() -> decode.Decoder(finance_track.Track) {
  decode.string
  |> decode.then(fn(value) {
    case finance_track.from_name(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(finance_track.Us, "cn, hk, or us")
    }
  })
}

fn placeholder_listing() -> Key {
  let assert Ok(instrument_id) = identifier.instrument_id("placeholder")
  let assert Ok(symbol) = identifier.symbol("PLACEHOLDER")
  let assert Ok(mic) = identifier.mic("XNAS")
  listing.new(finance_track.Us, instrument_id, symbol, mic)
}

fn placeholder_dependency() -> DependencyReceipt {
  let assert Ok(root_hash) = identity.sha256(string.repeat("0", 64))
  let assert Ok(at) = time.instant(0)
  let assert Ok(value) =
    dependency_receipt(definition.ExactIdentity, Ready, Some(at), [
      identity.evidence_id(root_hash),
    ])
  value
}

fn placeholder_feature() -> FeatureReceipt {
  let assert Ok(digest) = identity.sha256(string.repeat("0", 64))
  let assert Ok(at) = time.instant(0)
  let assert Ok(day) = time.date(1970, 1, 1)
  let assert Ok(value) =
    feature_receipt(
      "placeholder",
      "placeholder",
      "1.0.0",
      [],
      WarmupComplete(1, 1),
      digest,
      placeholder_listing(),
      day,
      NotPriceDependent,
      "scalar",
      at,
      at,
      Ready,
      Unknown("placeholder"),
      [identity.evidence_id(digest)],
    )
  value
}

fn placeholder_context() -> EvaluationContext {
  let assert Ok(at) = time.instant(0)
  let assert Ok(day) = time.date(1970, 1, 1)
  let assert Ok(value) =
    evaluation_context(placeholder_listing(), day, at, at, [], [])
  value
}

fn validate_feature_text(
  predicate_id: String,
  feature_id: String,
  formula_version: String,
  unit: String,
  price_dependency: PriceDependency,
) -> Result(Nil, EvidenceError) {
  let price_valid = case price_dependency {
    NotPriceDependent -> True
    PriceDependent(basis) -> valid_text(basis)
  }
  case
    valid_identifier(predicate_id),
    valid_identifier(feature_id),
    valid_identifier(formula_version),
    valid_identifier(unit),
    price_valid
  {
    True, True, True, True, True -> Ok(Nil)
    _, _, _, _, _ -> Error(InvalidText)
  }
}

fn validate_parameters(
  values: List(#(String, String)),
  seen: List(String),
) -> Result(Nil, EvidenceError) {
  case values {
    [] -> Ok(Nil)
    [#(name, value), ..rest] ->
      case
        valid_identifier(name),
        valid_text(value),
        list.contains(seen, name)
      {
        False, _, _ | _, False, _ -> Error(InvalidParameter)
        _, _, True -> Error(DuplicateParameter(name))
        True, True, False -> validate_parameters(rest, [name, ..seen])
      }
  }
}

fn validate_warmup(value: Warmup) -> Result(Nil, EvidenceError) {
  let valid = case value {
    WarmupComplete(actual, required) ->
      actual >= 0 && required > 0 && actual >= required
    WarmupIncomplete(actual, required)
    | WarmupResetAfterSuspension(actual, required) ->
      actual >= 0 && required > 0 && actual < required
  }
  case valid {
    True -> Ok(Nil)
    False -> Error(InvalidWarmup)
  }
}

fn validate_readiness(value: Readiness) -> Result(Nil, EvidenceError) {
  case value {
    Ready -> Ok(Nil)
    Missing(value)
    | Stale(value)
    | Incomplete(value)
    | Conflicting(value)
    | Unsupported(value)
    | Declared(value) ->
      case valid_text(value) {
        True -> Ok(Nil)
        False -> Error(InvalidText)
      }
  }
}

fn validate_observation(
  value: PredicateObservation,
) -> Result(Nil, EvidenceError) {
  case value {
    ObservedTrue | ObservedFalse -> Ok(Nil)
    Unknown(reason) ->
      case valid_text(reason) {
        True -> Ok(Nil)
        False -> Error(InvalidText)
      }
  }
}

fn validate_feature_evidence(
  readiness: Readiness,
  roots: List(EvidenceId),
) -> Result(Nil, EvidenceError) {
  case readiness, roots {
    Ready, [] -> Error(ReadyRequiresEvidence)
    Declared(_), roots if roots != [] -> Error(ReadyCannotBeDeclaration)
    _, _ -> Ok(Nil)
  }
}

fn validate_dependencies(
  values: List(DependencyReceipt),
  seen: List(Requirement),
) -> Result(Nil, EvidenceError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case list.contains(seen, value.requirement) {
        True -> Error(DuplicateRequirement(value.requirement))
        False -> validate_dependencies(rest, [value.requirement, ..seen])
      }
  }
}

fn validate_roots(values: List(EvidenceId)) -> Result(Nil, EvidenceError) {
  case first_duplicate_root(values, []) {
    None -> Ok(Nil)
    Some(value) -> Error(DuplicateEvidenceRoot(value))
  }
}

fn first_duplicate_root(
  values: List(EvidenceId),
  seen: List(EvidenceId),
) -> Option(String) {
  case values {
    [] -> None
    [value, ..rest] ->
      case list.contains(seen, value) {
        True -> Some(identity.evidence_id_value(value))
        False -> first_duplicate_root(rest, [value, ..seen])
      }
  }
}

fn valid_identifier(value: String) -> Bool {
  value != ""
  && string.length(value) <= 100
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_.:-", character)
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
