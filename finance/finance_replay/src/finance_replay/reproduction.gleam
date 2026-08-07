import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/event.{type Event}
import finance_replay/fact.{type Fact}
import finance_replay/wire
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type EnvironmentVersion {
  EnvironmentVersion(name: String, version: String, semantic: Bool)
}

pub type Dependency {
  Dependency(receipt_hash: Fact(Sha256), reason: String)
}

pub opaque type Manifest {
  Manifest(
    manifest_id: String,
    environment_versions: List(EnvironmentVersion),
    run_definition_hash: Sha256,
    trial_ids: List(String),
    partition_receipt: Sha256,
    universe_manifest_hash: Sha256,
    dataset_manifest_hash: Sha256,
    ordered_source_hashes: List(Sha256),
    transformation_receipts: List(Sha256),
    calendar_receipts: List(Sha256),
    rule_receipts: List(Sha256),
    corporate_action_receipts: List(Sha256),
    execution_model_receipt: Sha256,
    cost_receipts: List(Sha256),
    seed_and_random_stream_facts: List(String),
    effect_facts: List(String),
    output_receipt_hashes: List(Sha256),
    checkpoint_hashes: List(Sha256),
    entitlement_limitations: List(String),
    omitted_dependencies: List(Dependency),
    unknown_dependencies: List(Dependency),
    conflicting_dependencies: List(Dependency),
    export_provenance: String,
    privacy_policy: String,
    digest: Sha256,
  )
}

pub type Comparison {
  ExactMatch
  Different(differing_receipts: List(Sha256))
  Unperformed(reason: String)
  Partial(continuation: String)
}

pub type Bundle {
  Bundle(
    manifest_json: String,
    events_jsonl: String,
    receipt_directory: String,
    checkpoint_directory: String,
  )
}

pub type ManifestError {
  InvalidText(field: String)
  DuplicateValue(field: String, value: String)
  TooManyValues(field: String, received: Int, maximum: Int)
  HashMismatch
  InvalidJson
}

pub type PortableError {
  TooManyCharacters(received: Int, maximum: Int)
  TooManyEvents(received: Int, maximum: Int)
  EmptyLine(line: Int)
  EventDecodeFailure(line: Int, error: event.EventError)
}

pub const maximum_values = 10_000

pub fn new(
  manifest_id: String,
  environment_versions: List(EnvironmentVersion),
  run_definition_hash: Sha256,
  trial_ids: List(String),
  partition_receipt: Sha256,
  universe_manifest_hash: Sha256,
  dataset_manifest_hash: Sha256,
  ordered_source_hashes: List(Sha256),
  transformation_receipts: List(Sha256),
  calendar_receipts: List(Sha256),
  rule_receipts: List(Sha256),
  corporate_action_receipts: List(Sha256),
  execution_model_receipt: Sha256,
  cost_receipts: List(Sha256),
  seed_and_random_stream_facts: List(String),
  effect_facts: List(String),
  output_receipt_hashes: List(Sha256),
  checkpoint_hashes: List(Sha256),
  entitlement_limitations: List(String),
  omitted_dependencies: List(Dependency),
  unknown_dependencies: List(Dependency),
  conflicting_dependencies: List(Dependency),
  export_provenance: String,
  privacy_policy: String,
) -> Result(Manifest, ManifestError) {
  use _ <- result.try(validate_text(manifest_id, "manifest_id"))
  use _ <- result.try(validate_text(export_provenance, "export_provenance"))
  use _ <- result.try(validate_text(privacy_policy, "privacy_policy"))
  use _ <- result.try(validate_environments(environment_versions, []))
  use _ <- result.try(validate_unique_texts("trial_ids", trial_ids, []))
  use _ <- result.try(validate_receipt_family(
    "ordered_source_hashes",
    ordered_source_hashes,
  ))
  use _ <- result.try(validate_receipt_family(
    "transformation_receipts",
    transformation_receipts,
  ))
  use _ <- result.try(validate_receipt_family(
    "calendar_receipts",
    calendar_receipts,
  ))
  use _ <- result.try(validate_receipt_family("rule_receipts", rule_receipts))
  use _ <- result.try(validate_receipt_family(
    "corporate_action_receipts",
    corporate_action_receipts,
  ))
  use _ <- result.try(validate_receipt_family("cost_receipts", cost_receipts))
  use _ <- result.try(validate_receipt_family(
    "output_receipt_hashes",
    output_receipt_hashes,
  ))
  use _ <- result.try(validate_receipt_family(
    "checkpoint_hashes",
    checkpoint_hashes,
  ))
  use _ <- result.try(validate_texts(
    seed_and_random_stream_facts,
    "seed_and_random_stream_fact",
  ))
  use _ <- result.try(validate_texts(effect_facts, "effect_fact"))
  use _ <- result.try(validate_texts(
    entitlement_limitations,
    "entitlement_limitation",
  ))
  use _ <- result.try(validate_dependencies(
    omitted_dependencies,
    "omitted_dependencies",
  ))
  use _ <- result.try(validate_dependencies(
    unknown_dependencies,
    "unknown_dependencies",
  ))
  use _ <- result.try(validate_dependencies(
    conflicting_dependencies,
    "conflicting_dependencies",
  ))
  let payload =
    payload(
      manifest_id,
      environment_versions,
      run_definition_hash,
      trial_ids,
      partition_receipt,
      universe_manifest_hash,
      dataset_manifest_hash,
      ordered_source_hashes,
      transformation_receipts,
      calendar_receipts,
      rule_receipts,
      corporate_action_receipts,
      execution_model_receipt,
      cost_receipts,
      seed_and_random_stream_facts,
      effect_facts,
      output_receipt_hashes,
      checkpoint_hashes,
      entitlement_limitations,
      omitted_dependencies,
      unknown_dependencies,
      conflicting_dependencies,
      export_provenance,
      privacy_policy,
    )
  let assert Ok(digest) = payload |> json.to_string |> hash.text
  Ok(Manifest(
    manifest_id,
    environment_versions,
    run_definition_hash,
    trial_ids,
    partition_receipt,
    universe_manifest_hash,
    dataset_manifest_hash,
    ordered_source_hashes,
    transformation_receipts,
    calendar_receipts,
    rule_receipts,
    corporate_action_receipts,
    execution_model_receipt,
    cost_receipts,
    seed_and_random_stream_facts,
    effect_facts,
    output_receipt_hashes,
    checkpoint_hashes,
    entitlement_limitations,
    omitted_dependencies,
    unknown_dependencies,
    conflicting_dependencies,
    export_provenance,
    privacy_policy,
    digest,
  ))
}

pub fn encode(value: Manifest) -> String {
  value |> as_json |> json.to_string
}

pub fn as_json(value: Manifest) -> json.Json {
  json.object([
    #(
      "payload",
      payload(
        value.manifest_id,
        value.environment_versions,
        value.run_definition_hash,
        value.trial_ids,
        value.partition_receipt,
        value.universe_manifest_hash,
        value.dataset_manifest_hash,
        value.ordered_source_hashes,
        value.transformation_receipts,
        value.calendar_receipts,
        value.rule_receipts,
        value.corporate_action_receipts,
        value.execution_model_receipt,
        value.cost_receipts,
        value.seed_and_random_stream_facts,
        value.effect_facts,
        value.output_receipt_hashes,
        value.checkpoint_hashes,
        value.entitlement_limitations,
        value.omitted_dependencies,
        value.unknown_dependencies,
        value.conflicting_dependencies,
        value.export_provenance,
        value.privacy_policy,
      ),
    ),
    #("canonical_content_hash", wire.sha_json(value.digest)),
  ])
}

pub fn decode(input: String) -> Result(Manifest, ManifestError) {
  case json.parse(input, envelope_decoder()) {
    Error(_) -> Error(InvalidJson)
    Ok(#(value, expected)) ->
      case value.digest == expected {
        True -> Ok(value)
        False -> Error(HashMismatch)
      }
  }
}

pub fn export_bundle(value: Manifest, events: List(Event)) -> Bundle {
  Bundle(
    encode(value),
    encode_events_jsonl(events),
    "receipts/",
    "checkpoints/",
  )
}

pub fn encode_events_jsonl(events: List(Event)) -> String {
  case events {
    [] -> ""
    _ ->
      events
      |> list.map(event.encode)
      |> string.join("\n")
      |> fn(value) { value <> "\n" }
  }
}

pub fn decode_events_jsonl(
  input: String,
  maximum_events: Int,
  maximum_characters: Int,
) -> Result(List(Event), PortableError) {
  let character_count = string.length(input)
  case character_count > maximum_characters {
    True -> Error(TooManyCharacters(character_count, maximum_characters))
    False -> {
      let lines = jsonl_lines(input)
      let event_count = list.length(lines)
      case event_count > maximum_events {
        True -> Error(TooManyEvents(event_count, maximum_events))
        False -> decode_lines(lines, 1, [])
      }
    }
  }
}

fn jsonl_lines(input: String) -> List(String) {
  case input {
    "" -> []
    _ -> {
      let lines = string.split(input, on: "\n")
      case list.last(lines) {
        Ok("") -> list.take(lines, list.length(lines) - 1)
        _ -> lines
      }
    }
  }
}

fn decode_lines(
  lines: List(String),
  line: Int,
  reversed: List(Event),
) -> Result(List(Event), PortableError) {
  case lines {
    [] -> Ok(list.reverse(reversed))
    ["", ..] -> Error(EmptyLine(line))
    [value, ..rest] ->
      case event.decode(value) {
        Error(error) -> Error(EventDecodeFailure(line, error))
        Ok(value) -> decode_lines(rest, line + 1, [value, ..reversed])
      }
  }
}

pub fn compare(left: Manifest, right: Manifest) -> Comparison {
  case left.digest == right.digest {
    True -> ExactMatch
    False -> Different(differing_receipts(left, right))
  }
}

fn differing_receipts(left: Manifest, right: Manifest) -> List(Sha256) {
  let pairs = [
    #(left.run_definition_hash, right.run_definition_hash),
    #(left.partition_receipt, right.partition_receipt),
    #(left.universe_manifest_hash, right.universe_manifest_hash),
    #(left.dataset_manifest_hash, right.dataset_manifest_hash),
    #(left.execution_model_receipt, right.execution_model_receipt),
  ]
  let direct =
    pairs
    |> list.flat_map(fn(pair) {
      case pair.0 == pair.1 {
        True -> []
        False -> [pair.0, pair.1]
      }
    })
  case direct {
    [] -> [left.digest, right.digest]
    _ -> direct
  }
}

fn payload(
  manifest_id: String,
  environment_versions: List(EnvironmentVersion),
  run_definition_hash: Sha256,
  trial_ids: List(String),
  partition_receipt: Sha256,
  universe_manifest_hash: Sha256,
  dataset_manifest_hash: Sha256,
  ordered_source_hashes: List(Sha256),
  transformation_receipts: List(Sha256),
  calendar_receipts: List(Sha256),
  rule_receipts: List(Sha256),
  corporate_action_receipts: List(Sha256),
  execution_model_receipt: Sha256,
  cost_receipts: List(Sha256),
  seed_and_random_stream_facts: List(String),
  effect_facts: List(String),
  output_receipt_hashes: List(Sha256),
  checkpoint_hashes: List(Sha256),
  entitlement_limitations: List(String),
  omitted_dependencies: List(Dependency),
  unknown_dependencies: List(Dependency),
  conflicting_dependencies: List(Dependency),
  export_provenance: String,
  privacy_policy: String,
) -> json.Json {
  json.object([
    #("schema", json.string("finance_replay_reproduction_manifest")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("manifest_id", json.string(manifest_id)),
    #(
      "environment_versions",
      json.array(environment_versions, environment_json),
    ),
    #("run_definition_hash", wire.sha_json(run_definition_hash)),
    #("trial_ids", json.array(trial_ids, json.string)),
    #("partition_receipt", wire.sha_json(partition_receipt)),
    #("universe_manifest_hash", wire.sha_json(universe_manifest_hash)),
    #("dataset_manifest_hash", wire.sha_json(dataset_manifest_hash)),
    #("ordered_source_hashes", json.array(ordered_source_hashes, wire.sha_json)),
    #(
      "transformation_receipts",
      json.array(transformation_receipts, wire.sha_json),
    ),
    #("calendar_receipts", json.array(calendar_receipts, wire.sha_json)),
    #("rule_receipts", json.array(rule_receipts, wire.sha_json)),
    #(
      "corporate_action_receipts",
      json.array(corporate_action_receipts, wire.sha_json),
    ),
    #("execution_model_receipt", wire.sha_json(execution_model_receipt)),
    #("cost_receipts", json.array(cost_receipts, wire.sha_json)),
    #(
      "seed_and_random_stream_facts",
      json.array(seed_and_random_stream_facts, json.string),
    ),
    #("effect_facts", json.array(effect_facts, json.string)),
    #("output_receipt_hashes", json.array(output_receipt_hashes, wire.sha_json)),
    #("checkpoint_hashes", json.array(checkpoint_hashes, wire.sha_json)),
    #(
      "entitlement_limitations",
      json.array(entitlement_limitations, json.string),
    ),
    #("omitted_dependencies", json.array(omitted_dependencies, dependency_json)),
    #("unknown_dependencies", json.array(unknown_dependencies, dependency_json)),
    #(
      "conflicting_dependencies",
      json.array(conflicting_dependencies, dependency_json),
    ),
    #("export_provenance", json.string(export_provenance)),
    #("privacy_policy", json.string(privacy_policy)),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

fn environment_json(value: EnvironmentVersion) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #("version", json.string(value.version)),
    #("semantic", json.bool(value.semantic)),
  ])
}

fn dependency_json(value: Dependency) -> json.Json {
  json.object([
    #("receipt_hash", fact.to_json(value.receipt_hash, wire.sha_json)),
    #("reason", json.string(value.reason)),
  ])
}

fn envelope_decoder() -> decode.Decoder(#(Manifest, Sha256)) {
  use value <- decode.field("payload", manifest_decoder())
  use expected <- decode.field("canonical_content_hash", wire.sha_decoder())
  decode.success(#(value, expected))
}

fn manifest_decoder() -> decode.Decoder(Manifest) {
  use manifest_id <- decode.field("manifest_id", decode.string)
  use environments <- decode.field(
    "environment_versions",
    decode.list(of: environment_decoder()),
  )
  use run_definition <- decode.field("run_definition_hash", wire.sha_decoder())
  use trial_ids <- decode.field("trial_ids", decode.list(of: decode.string))
  use partition <- decode.field("partition_receipt", wire.sha_decoder())
  use universe <- decode.field("universe_manifest_hash", wire.sha_decoder())
  use dataset <- decode.field("dataset_manifest_hash", wire.sha_decoder())
  use sources <- decode.field(
    "ordered_source_hashes",
    decode.list(of: wire.sha_decoder()),
  )
  use transformations <- decode.field(
    "transformation_receipts",
    decode.list(of: wire.sha_decoder()),
  )
  use calendars <- decode.field(
    "calendar_receipts",
    decode.list(of: wire.sha_decoder()),
  )
  use rules <- decode.field(
    "rule_receipts",
    decode.list(of: wire.sha_decoder()),
  )
  use actions <- decode.field(
    "corporate_action_receipts",
    decode.list(of: wire.sha_decoder()),
  )
  use execution <- decode.field("execution_model_receipt", wire.sha_decoder())
  use costs <- decode.field(
    "cost_receipts",
    decode.list(of: wire.sha_decoder()),
  )
  use seeds <- decode.field(
    "seed_and_random_stream_facts",
    decode.list(of: decode.string),
  )
  use effects <- decode.field("effect_facts", decode.list(of: decode.string))
  use outputs <- decode.field(
    "output_receipt_hashes",
    decode.list(of: wire.sha_decoder()),
  )
  use checkpoints <- decode.field(
    "checkpoint_hashes",
    decode.list(of: wire.sha_decoder()),
  )
  use limitations <- decode.field(
    "entitlement_limitations",
    decode.list(of: decode.string),
  )
  use omitted <- decode.field(
    "omitted_dependencies",
    decode.list(of: dependency_decoder()),
  )
  use unknown <- decode.field(
    "unknown_dependencies",
    decode.list(of: dependency_decoder()),
  )
  use conflicting <- decode.field(
    "conflicting_dependencies",
    decode.list(of: dependency_decoder()),
  )
  use export_provenance <- decode.field("export_provenance", decode.string)
  use privacy_policy <- decode.field("privacy_policy", decode.string)
  case
    new(
      manifest_id,
      environments,
      run_definition,
      trial_ids,
      partition,
      universe,
      dataset,
      sources,
      transformations,
      calendars,
      rules,
      actions,
      execution,
      costs,
      seeds,
      effects,
      outputs,
      checkpoints,
      limitations,
      omitted,
      unknown,
      conflicting,
      export_provenance,
      privacy_policy,
    )
  {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(placeholder(), "valid reproduction manifest")
  }
}

fn environment_decoder() -> decode.Decoder(EnvironmentVersion) {
  use name <- decode.field("name", decode.string)
  use version <- decode.field("version", decode.string)
  use semantic <- decode.field("semantic", decode.bool)
  decode.success(EnvironmentVersion(name, version, semantic))
}

fn dependency_decoder() -> decode.Decoder(Dependency) {
  use receipt_hash <- decode.field(
    "receipt_hash",
    fact.decoder(wire.sha_decoder()),
  )
  use reason <- decode.field("reason", decode.string)
  decode.success(Dependency(receipt_hash, reason))
}

fn validate_environments(
  values: List(EnvironmentVersion),
  seen: List(String),
) -> Result(Nil, ManifestError) {
  case values {
    [] -> Ok(Nil)
    [EnvironmentVersion(name, version, _), ..rest] -> {
      use _ <- result.try(validate_text(name, "environment_name"))
      use _ <- result.try(validate_text(version, "environment_version"))
      case list.contains(seen, name) {
        True -> Error(DuplicateValue("environment_versions", name))
        False -> validate_environments(rest, [name, ..seen])
      }
    }
  }
}

fn validate_dependencies(
  values: List(Dependency),
  field: String,
) -> Result(Nil, ManifestError) {
  use _ <- result.try(validate_count(field, values))
  values
  |> list.fold(Ok(Nil), fn(acc, value) {
    use _ <- result.try(acc)
    validate_text(value.reason, field <> ".reason")
  })
}

fn validate_receipt_family(
  field: String,
  values: List(Sha256),
) -> Result(Nil, ManifestError) {
  use _ <- result.try(validate_count(field, values))
  validate_receipts(field, values, [])
}

fn validate_receipts(
  field: String,
  values: List(Sha256),
  seen: List(String),
) -> Result(Nil, ManifestError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      let text = identity.sha256_value(value)
      case list.contains(seen, text) {
        True -> Error(DuplicateValue(field, text))
        False -> validate_receipts(field, rest, [text, ..seen])
      }
    }
  }
}

fn validate_unique_texts(
  field: String,
  values: List(String),
  seen: List(String),
) -> Result(Nil, ManifestError) {
  use _ <- result.try(validate_count(field, values))
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(validate_text(value, field))
      case list.contains(seen, value) {
        True -> Error(DuplicateValue(field, value))
        False -> validate_unique_texts(field, rest, [value, ..seen])
      }
    }
  }
}

fn validate_texts(
  values: List(String),
  field: String,
) -> Result(Nil, ManifestError) {
  use _ <- result.try(validate_count(field, values))
  values
  |> list.fold(Ok(Nil), fn(acc, value) {
    use _ <- result.try(acc)
    validate_text(value, field)
  })
}

fn validate_count(
  field: String,
  values: List(a),
) -> Result(Nil, ManifestError) {
  let count = list.length(values)
  case count > maximum_values {
    True -> Error(TooManyValues(field, count, maximum_values))
    False -> Ok(Nil)
  }
}

fn validate_text(value: String, field: String) -> Result(Nil, ManifestError) {
  case wire.valid_text(value, 65_536) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn placeholder() -> Manifest {
  let sha = wire.placeholder_sha()
  let assert Ok(value) =
    new(
      "placeholder",
      [],
      sha,
      [],
      sha,
      sha,
      sha,
      [],
      [],
      [],
      [],
      [],
      sha,
      [],
      [],
      [],
      [],
      [],
      [],
      [],
      [],
      [],
      "placeholder",
      "placeholder",
    )
  value
}

pub fn content_hash(value: Manifest) -> Sha256 {
  value.digest
}
