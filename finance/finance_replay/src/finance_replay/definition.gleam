import finance_core/time.{type Instant}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/fact.{type Fact}
import finance_replay/wire
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result

pub type DeclaredPolicy {
  DeclaredPolicy(name: String, value: String, source_receipt: Option(Sha256))
}

pub opaque type RunDefinition {
  RunDefinition(
    id: String,
    version: String,
    feature_receipts: List(Sha256),
    strategy_receipt: Sha256,
    risk_receipts: List(Sha256),
    execution_receipt: Sha256,
    universe_manifest: Sha256,
    dataset_manifest: Sha256,
    partition_receipt: Sha256,
    knowledge_cutoff: Fact(Instant),
    policies: List(DeclaredPolicy),
    execution_branch_policy: String,
    seed_and_stream: Fact(String),
    limitations: List(String),
    digest: Sha256,
  )
}

pub type DefinitionError {
  InvalidText(field: String)
  DuplicatePolicy(String)
  DuplicateReceipt(family: String, hash: String)
  TooManyValues(field: String, received: Int, maximum: Int)
  HashMismatch
  InvalidJson
}

pub fn new(
  id: String,
  version: String,
  feature_receipts: List(Sha256),
  strategy_receipt: Sha256,
  risk_receipts: List(Sha256),
  execution_receipt: Sha256,
  universe_manifest: Sha256,
  dataset_manifest: Sha256,
  partition_receipt: Sha256,
  knowledge_cutoff: Fact(Instant),
  policies: List(DeclaredPolicy),
  execution_branch_policy: String,
  seed_and_stream: Fact(String),
  limitations: List(String),
) -> Result(RunDefinition, DefinitionError) {
  use _ <- result.try(validate_text(id, "run_definition_id"))
  use _ <- result.try(validate_text(version, "version"))
  use _ <- result.try(validate_text(
    execution_branch_policy,
    "execution_branch_policy",
  ))
  use _ <- result.try(validate_receipts("feature", feature_receipts, []))
  use _ <- result.try(validate_receipts("risk", risk_receipts, []))
  use _ <- result.try(validate_policies(policies, []))
  use _ <- result.try(validate_texts(limitations, "limitation"))
  use _ <- result.try(validate_count("feature_receipts", feature_receipts, 1000))
  use _ <- result.try(validate_count("risk_receipts", risk_receipts, 1000))
  use _ <- result.try(validate_count("policies", policies, 1000))
  let payload =
    payload(
      id,
      version,
      feature_receipts,
      strategy_receipt,
      risk_receipts,
      execution_receipt,
      universe_manifest,
      dataset_manifest,
      partition_receipt,
      knowledge_cutoff,
      policies,
      execution_branch_policy,
      seed_and_stream,
      limitations,
    )
  let assert Ok(digest) = payload |> json.to_string |> hash.text
  Ok(RunDefinition(
    id,
    version,
    feature_receipts,
    strategy_receipt,
    risk_receipts,
    execution_receipt,
    universe_manifest,
    dataset_manifest,
    partition_receipt,
    knowledge_cutoff,
    policies,
    execution_branch_policy,
    seed_and_stream,
    limitations,
    digest,
  ))
}

pub fn encode(value: RunDefinition) -> String {
  json.object([
    #("payload", to_json(value)),
    #("canonical_content_hash", wire.sha_json(value.digest)),
  ])
  |> json.to_string
}

pub fn decode(input: String) -> Result(RunDefinition, DefinitionError) {
  case json.parse(input, envelope_decoder()) {
    Error(_) -> Error(InvalidJson)
    Ok(#(value, expected)) ->
      case value.digest == expected {
        True -> Ok(value)
        False -> Error(HashMismatch)
      }
  }
}

pub fn to_json(value: RunDefinition) -> json.Json {
  json.object([
    #(
      "content",
      payload(
        value.id,
        value.version,
        value.feature_receipts,
        value.strategy_receipt,
        value.risk_receipts,
        value.execution_receipt,
        value.universe_manifest,
        value.dataset_manifest,
        value.partition_receipt,
        value.knowledge_cutoff,
        value.policies,
        value.execution_branch_policy,
        value.seed_and_stream,
        value.limitations,
      ),
    ),
    #("content_hash", wire.sha_json(value.digest)),
  ])
}

fn payload(
  id: String,
  version: String,
  feature_receipts: List(Sha256),
  strategy_receipt: Sha256,
  risk_receipts: List(Sha256),
  execution_receipt: Sha256,
  universe_manifest: Sha256,
  dataset_manifest: Sha256,
  partition_receipt: Sha256,
  knowledge_cutoff: Fact(Instant),
  policies: List(DeclaredPolicy),
  execution_branch_policy: String,
  seed_and_stream: Fact(String),
  limitations: List(String),
) -> json.Json {
  json.object([
    #("schema", json.string("finance_replay_run_definition")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("run_definition_id", json.string(id)),
    #("version", json.string(version)),
    #("feature_receipts", json.array(feature_receipts, wire.sha_json)),
    #("strategy_receipt", wire.sha_json(strategy_receipt)),
    #("risk_receipts", json.array(risk_receipts, wire.sha_json)),
    #("execution_receipt", wire.sha_json(execution_receipt)),
    #("universe_manifest", wire.sha_json(universe_manifest)),
    #("dataset_manifest", wire.sha_json(dataset_manifest)),
    #("partition_receipt", wire.sha_json(partition_receipt)),
    #("knowledge_cutoff", fact.to_json(knowledge_cutoff, wire.instant_json)),
    #("declared_policies", json.array(policies, policy_json)),
    #("execution_branch_policy", json.string(execution_branch_policy)),
    #("seed_and_stream", fact.to_json(seed_and_stream, json.string)),
    #("limitations", json.array(limitations, json.string)),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
    #(
      "available_operations",
      json.array(
        [
          "inspect_receipt",
          "compare_run_definition",
          "declare_trial",
          "request_scripted_replay",
        ],
        json.string,
      ),
    ),
  ])
}

fn policy_json(value: DeclaredPolicy) -> json.Json {
  let DeclaredPolicy(name, value, source) = value
  json.object([
    #("name", json.string(name)),
    #("value", json.string(value)),
    #("source_receipt", json.nullable(source, wire.sha_json)),
  ])
}

fn envelope_decoder() -> decode.Decoder(#(RunDefinition, Sha256)) {
  use value <- decode.field("payload", wrapper_decoder())
  use expected <- decode.field("canonical_content_hash", wire.sha_decoder())
  decode.success(#(value, expected))
}

fn wrapper_decoder() -> decode.Decoder(RunDefinition) {
  use content <- decode.field("content", payload_decoder())
  use supplied <- decode.field("content_hash", wire.sha_decoder())
  let #(
    id,
    version,
    features,
    strategy,
    risks,
    execution,
    universe,
    dataset,
    partition,
    cutoff,
    policies,
    branch_policy,
    seed,
    limitations,
  ) = content
  case
    new(
      id,
      version,
      features,
      strategy,
      risks,
      execution,
      universe,
      dataset,
      partition,
      cutoff,
      policies,
      branch_policy,
      seed,
      limitations,
    )
  {
    Ok(value) if value.digest == supplied -> decode.success(value)
    _ -> decode.failure(placeholder(), "valid run definition")
  }
}

fn payload_decoder() -> decode.Decoder(
  #(
    String,
    String,
    List(Sha256),
    Sha256,
    List(Sha256),
    Sha256,
    Sha256,
    Sha256,
    Sha256,
    Fact(Instant),
    List(DeclaredPolicy),
    String,
    Fact(String),
    List(String),
  ),
) {
  use schema <- decode.field("schema", decode.string)
  use version_number <- decode.field("schema_version", decode.int)
  use decision_owner <- decode.field("decision_owner", decode.string)
  use id <- decode.field("run_definition_id", decode.string)
  use version <- decode.field("version", decode.string)
  use features <- decode.field(
    "feature_receipts",
    decode.list(of: wire.sha_decoder()),
  )
  use strategy <- decode.field("strategy_receipt", wire.sha_decoder())
  use risks <- decode.field(
    "risk_receipts",
    decode.list(of: wire.sha_decoder()),
  )
  use execution <- decode.field("execution_receipt", wire.sha_decoder())
  use universe <- decode.field("universe_manifest", wire.sha_decoder())
  use dataset <- decode.field("dataset_manifest", wire.sha_decoder())
  use partition <- decode.field("partition_receipt", wire.sha_decoder())
  use cutoff <- decode.field(
    "knowledge_cutoff",
    fact.decoder(wire.instant_decoder()),
  )
  use policies <- decode.field(
    "declared_policies",
    decode.list(of: policy_decoder()),
  )
  use branch_policy <- decode.field("execution_branch_policy", decode.string)
  use seed <- decode.field("seed_and_stream", fact.decoder(decode.string))
  use limitations <- decode.field("limitations", decode.list(of: decode.string))
  case schema, version_number, decision_owner {
    "finance_replay_run_definition", 1, "llm" ->
      decode.success(#(
        id,
        version,
        features,
        strategy,
        risks,
        execution,
        universe,
        dataset,
        partition,
        cutoff,
        policies,
        branch_policy,
        seed,
        limitations,
      ))
    _, _, _ -> decode.failure(placeholder_payload(), "run definition v1")
  }
}

fn policy_decoder() -> decode.Decoder(DeclaredPolicy) {
  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", decode.string)
  use source <- decode.optional_field(
    "source_receipt",
    None,
    decode.optional(wire.sha_decoder()),
  )
  decode.success(DeclaredPolicy(name, value, source))
}

fn validate_policies(
  values: List(DeclaredPolicy),
  seen: List(String),
) -> Result(Nil, DefinitionError) {
  case values {
    [] -> Ok(Nil)
    [DeclaredPolicy(name, value, _), ..rest] -> {
      use _ <- result.try(validate_text(name, "policy_name"))
      use _ <- result.try(validate_text(value, "policy_value"))
      case list.contains(seen, name) {
        True -> Error(DuplicatePolicy(name))
        False -> validate_policies(rest, [name, ..seen])
      }
    }
  }
}

fn validate_receipts(
  family: String,
  values: List(Sha256),
  seen: List(Sha256),
) -> Result(Nil, DefinitionError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case list.contains(seen, value) {
        True -> Error(DuplicateReceipt(family, identity.sha256_value(value)))
        False -> validate_receipts(family, rest, [value, ..seen])
      }
  }
}

fn validate_count(
  field: String,
  values: List(a),
  maximum: Int,
) -> Result(Nil, DefinitionError) {
  let count = list.length(values)
  case count > maximum {
    True -> Error(TooManyValues(field, count, maximum))
    False -> Ok(Nil)
  }
}

fn validate_text(value: String, field: String) -> Result(Nil, DefinitionError) {
  case wire.valid_text(value, 2000) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn validate_texts(
  values: List(String),
  field: String,
) -> Result(Nil, DefinitionError) {
  case list.all(values, fn(value) { wire.valid_text(value, 2000) }) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn placeholder_payload() {
  let sha = wire.placeholder_sha()
  #(
    "placeholder",
    "placeholder",
    [],
    sha,
    [],
    sha,
    sha,
    sha,
    sha,
    fact.Unknown("placeholder"),
    [],
    "placeholder",
    fact.NotApplicable("placeholder"),
    [],
  )
}

fn placeholder() -> RunDefinition {
  let sha = wire.placeholder_sha()
  let assert Ok(value) =
    new(
      "placeholder",
      "placeholder",
      [],
      sha,
      [],
      sha,
      sha,
      sha,
      sha,
      fact.Unknown("placeholder"),
      [],
      "placeholder",
      fact.NotApplicable("placeholder"),
      [],
    )
  value
}

pub fn digest(value: RunDefinition) -> Sha256 {
  value.digest
}

pub fn id(value: RunDefinition) -> String {
  value.id
}

pub fn feature_receipts(value: RunDefinition) -> List(Sha256) {
  value.feature_receipts
}

pub fn strategy_receipt(value: RunDefinition) -> Sha256 {
  value.strategy_receipt
}

pub fn risk_receipts(value: RunDefinition) -> List(Sha256) {
  value.risk_receipts
}

pub fn execution_receipt(value: RunDefinition) -> Sha256 {
  value.execution_receipt
}

pub fn version(value: RunDefinition) -> String {
  value.version
}

pub fn universe_manifest(value: RunDefinition) -> Sha256 {
  value.universe_manifest
}

pub fn dataset_manifest(value: RunDefinition) -> Sha256 {
  value.dataset_manifest
}

pub fn partition_receipt(value: RunDefinition) -> Sha256 {
  value.partition_receipt
}

pub fn policies(value: RunDefinition) -> List(DeclaredPolicy) {
  value.policies
}

pub fn execution_branch_policy(value: RunDefinition) -> String {
  value.execution_branch_policy
}

pub fn limitations(value: RunDefinition) -> List(String) {
  value.limitations
}
