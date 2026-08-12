import finance_provenance/hash
import finance_provenance/identity
import finance_replay/manifest
import finance_track
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Error {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract(expected: String, received: String)
  WrongOperation(expected: String, received: String)
  InvalidField(field: String, reason: String)
  InvalidReceipt(field: String)
  DuplicateIdentity(field: String, value: String)
  ManifestFailure(kind: String, reason: String)
  ManifestNotCanonical(kind: String)
  ManifestHashMismatch(kind: String, expected: String, actual: String)
  TrackMismatch(expected: String, actual: String)
  CalculationFailure(reason: String)
  BudgetExceeded(field: String, received: Int, maximum: Int)
}

pub type Metadata {
  Metadata(schema_version: Int, contract_id: String, operation: String)
}

pub type ManifestInput {
  ManifestInput(manifest_json: String, manifest_hash: String)
}

pub type BindingInput {
  BindingInput(
    track: String,
    universe: ManifestInput,
    dataset: ManifestInput,
    knowledge_cutoff_unix_ms: Int,
    calendar_receipt: String,
    trial_id: String,
  )
}

pub type Binding {
  Binding(
    track: finance_track.Track,
    universe: manifest.UniverseManifest,
    dataset: manifest.DatasetManifest,
    universe_hash: String,
    dataset_hash: String,
    knowledge_cutoff_unix_ms: Int,
    calendar_receipt: String,
    trial_id: String,
  )
}

pub type Response {
  Response(summary: String, details: json.Json)
}

pub fn response(summary: String, details: json.Json) -> Response {
  Response(summary, details)
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> json.Json {
  value.details
}

pub fn error_message(error: Error) -> String {
  case error {
    InvalidJson -> "Quant packet is not valid versioned JSON"
    ContentHashMismatch -> "Quant packet does not match expectedSha256"
    WrongSchema -> "Quant packet schemaVersion must be 1"
    WrongContract(expected, received) ->
      "Quant packet contractId must be "
      <> expected
      <> ", received "
      <> received
    WrongOperation(expected, received) ->
      "Quant packet operation must be " <> expected <> ", received " <> received
    InvalidField(field, reason) ->
      "Invalid quant field " <> field <> ": " <> reason
    InvalidReceipt(field) ->
      "Quant field "
      <> field
      <> " must be exactly 64 hexadecimal SHA-256 characters"
    DuplicateIdentity(field, value) ->
      "Duplicate quant identity in " <> field <> ": " <> value
    ManifestFailure(kind, reason) ->
      kind
      <> " manifest failed the canonical finance_replay contract: "
      <> reason
    ManifestNotCanonical(kind) ->
      kind <> " manifestJson is not the exact canonical finance_replay envelope"
    ManifestHashMismatch(kind, expected, actual) ->
      kind
      <> " manifestHash "
      <> expected
      <> " does not match canonical handle "
      <> actual
    TrackMismatch(expected, actual) ->
      "Quant track " <> expected <> " does not match manifest track " <> actual
    CalculationFailure(reason) -> "Quant calculation is unperformed: " <> reason
    BudgetExceeded(field, received, maximum) ->
      field
      <> " budget exceeded: received "
      <> string.inspect(received)
      <> ", maximum "
      <> string.inspect(maximum)
  }
}

pub fn verify_packet(
  bytes: String,
  expected_sha256: String,
  contract_id: String,
  operation: String,
) -> Result(Nil, Error) {
  use _ <- result.try(case hash.text(bytes) {
    Ok(actual) ->
      case identity.sha256_value(actual) == expected_sha256 {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
    Error(_) -> Error(ContentHashMismatch)
  })
  use metadata <- result.try(parse(bytes, metadata_decoder()))
  use _ <- result.try(case metadata.schema_version == 1 {
    True -> Ok(Nil)
    False -> Error(WrongSchema)
  })
  use _ <- result.try(case metadata.contract_id == contract_id {
    True -> Ok(Nil)
    False -> Error(WrongContract(contract_id, metadata.contract_id))
  })
  case metadata.operation == operation {
    True -> Ok(Nil)
    False -> Error(WrongOperation(operation, metadata.operation))
  }
}

pub fn parse(
  bytes: String,
  decoder: decode.Decoder(value),
) -> Result(value, Error) {
  json.parse(bytes, decoder) |> result.map_error(fn(_) { InvalidJson })
}

pub fn metadata_decoder() -> decode.Decoder(Metadata) {
  use schema_version <- decode.field("schemaVersion", decode.int)
  use contract_id <- decode.field("contractId", decode.string)
  use operation <- decode.field("operation", decode.string)
  decode.success(Metadata(schema_version, contract_id, operation))
}

pub fn binding_decoder() -> decode.Decoder(BindingInput) {
  use track <- decode.field("track", decode.string)
  use universe <- decode.field("universe", manifest_decoder())
  use dataset <- decode.field("dataset", manifest_decoder())
  use cutoff <- decode.field("knowledgeCutoffUnixMilliseconds", decode.int)
  use calendar <- decode.field("calendarReceipt", decode.string)
  use trial_id <- decode.field("trialId", decode.string)
  decode.success(BindingInput(
    track,
    universe,
    dataset,
    cutoff,
    calendar,
    trial_id,
  ))
}

fn manifest_decoder() -> decode.Decoder(ManifestInput) {
  use manifest_json <- decode.field("manifestJson", decode.string)
  use manifest_hash <- decode.field("manifestHash", decode.string)
  decode.success(ManifestInput(manifest_json, manifest_hash))
}

pub fn prepare_binding(input: BindingInput) -> Result(Binding, Error) {
  use track <- result.try(parse_track(input.track))
  use _ <- result.try(non_empty("binding.trialId", input.trial_id))
  use _ <- result.try(receipt("binding.calendarReceipt", input.calendar_receipt))
  use _ <- result.try(case input.knowledge_cutoff_unix_ms >= 0 {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "binding.knowledgeCutoffUnixMilliseconds",
        "must be non-negative",
      ))
  })
  use universe <- result.try(prepare_universe(input.universe))
  use dataset <- result.try(prepare_dataset(input.dataset))
  use _ <- result.try(exact_track(track, manifest.universe_track(universe.0)))
  use _ <- result.try(exact_track(track, manifest.dataset_track(dataset.0)))
  Ok(Binding(
    track,
    universe.0,
    dataset.0,
    universe.1,
    dataset.1,
    input.knowledge_cutoff_unix_ms,
    input.calendar_receipt,
    input.trial_id,
  ))
}

fn prepare_universe(
  input: ManifestInput,
) -> Result(#(manifest.UniverseManifest, String), Error) {
  use _ <- result.try(receipt(
    "binding.universe.manifestHash",
    input.manifest_hash,
  ))
  use decoded <- result.try(
    manifest.decode_universe(input.manifest_json)
    |> result.map_error(fn(error) {
      ManifestFailure("universe", string.inspect(error))
    }),
  )
  use _ <- result.try(
    case manifest.encode_universe(decoded) == input.manifest_json {
      True -> Ok(Nil)
      False -> Error(ManifestNotCanonical("universe"))
    },
  )
  let actual = decoded |> manifest.universe_digest |> identity.sha256_value
  case actual == input.manifest_hash {
    True -> Ok(#(decoded, actual))
    False ->
      Error(ManifestHashMismatch("universe", input.manifest_hash, actual))
  }
}

fn prepare_dataset(
  input: ManifestInput,
) -> Result(#(manifest.DatasetManifest, String), Error) {
  use _ <- result.try(receipt(
    "binding.dataset.manifestHash",
    input.manifest_hash,
  ))
  use decoded <- result.try(
    manifest.decode_dataset(input.manifest_json)
    |> result.map_error(fn(error) {
      ManifestFailure("dataset", string.inspect(error))
    }),
  )
  use _ <- result.try(
    case manifest.encode_dataset(decoded) == input.manifest_json {
      True -> Ok(Nil)
      False -> Error(ManifestNotCanonical("dataset"))
    },
  )
  let actual = decoded |> manifest.dataset_digest |> identity.sha256_value
  case actual == input.manifest_hash {
    True -> Ok(#(decoded, actual))
    False -> Error(ManifestHashMismatch("dataset", input.manifest_hash, actual))
  }
}

fn exact_track(
  expected: finance_track.Track,
  actual: finance_track.Track,
) -> Result(Nil, Error) {
  case expected == actual {
    True -> Ok(Nil)
    False ->
      Error(TrackMismatch(
        finance_track.name(expected),
        finance_track.name(actual),
      ))
  }
}

pub fn parse_track(value: String) -> Result(finance_track.Track, Error) {
  finance_track.from_name(value)
  |> result.map_error(fn(_) { InvalidField("track", "expected cn, hk, or us") })
}

pub fn non_empty(field: String, value: String) -> Result(Nil, Error) {
  case
    value == string.trim(value) && value != "" && string.length(value) <= 2000
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "must be non-empty, trimmed, and at most 2000 characters",
      ))
  }
}

pub fn receipt(field: String, value: String) -> Result(Nil, Error) {
  identity.sha256(value)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(_) { InvalidReceipt(field) })
}

pub fn require_unique(
  field: String,
  values: List(String),
) -> Result(Nil, Error) {
  require_unique_loop(field, values, [])
}

fn require_unique_loop(
  field: String,
  values: List(String),
  seen: List(String),
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case list.contains(seen, value) {
        True -> Error(DuplicateIdentity(field, value))
        False -> require_unique_loop(field, rest, [value, ..seen])
      }
  }
}

pub fn bounded_count(
  field: String,
  values: List(value),
  maximum: Int,
) -> Result(Nil, Error) {
  let count = list.length(values)
  case count <= maximum {
    True -> Ok(Nil)
    False -> Error(BudgetExceeded(field, count, maximum))
  }
}

pub fn binding_json(binding: Binding) -> json.Json {
  json.object([
    #("track", json.string(finance_track.name(binding.track))),
    #("universeManifestHash", json.string(binding.universe_hash)),
    #("datasetManifestHash", json.string(binding.dataset_hash)),
    #(
      "knowledgeCutoffUnixMilliseconds",
      json.int(binding.knowledge_cutoff_unix_ms),
    ),
    #("calendarReceipt", json.string(binding.calendar_receipt)),
    #("trialId", json.string(binding.trial_id)),
  ])
}

pub fn content_bound(fields: List(#(String, json.Json))) -> json.Json {
  let payload = json.object(fields)
  let assert Ok(digest) = payload |> json.to_string |> hash.text
  json.object(
    list.append(fields, [
      #("contentHash", json.string(identity.sha256_value(digest))),
    ]),
  )
}
