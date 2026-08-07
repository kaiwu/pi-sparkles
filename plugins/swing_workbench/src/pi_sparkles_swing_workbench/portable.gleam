import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import pi_sparkles_swing_workbench/state

pub const schema_version = 1

pub type Selection {
  AllWorkflows
  ExactWorkflow(workflow_id: String)
}

pub opaque type Bundle {
  Bundle(
    selection: Selection,
    source_revision: Int,
    portable_revision: Int,
    workflow_ids: List(String),
    events: List(String),
    canonical_content_hash: Sha256,
  )
}

type Payload {
  Payload(
    selection: Selection,
    source_revision: Int,
    portable_revision: Int,
    workflow_ids: List(String),
    events: List(String),
  )
}

pub type PortableError {
  EmptySelection
  InvalidJson
  InvalidEnvelope
  ContentHashMismatch
  ExpectedContentHashMismatch
  NonCanonicalEncoding
  InvalidEventLog(state.ReplayError)
  MetadataMismatch
}

pub fn build(
  source: state.State,
  workflows: List(state.Workflow),
  selected: Selection,
) -> Result(Bundle, PortableError) {
  case workflows {
    [] -> Error(EmptySelection)
    _ -> {
      let events = state.canonical_event_log(workflows)
      let workflow_ids = list.map(workflows, state.workflow_id)
      let payload =
        Payload(
          selected,
          state.revision(source),
          list.length(events),
          workflow_ids,
          events,
        )
      let assert Ok(content_hash) =
        payload |> payload_json |> json.to_string |> hash.text
      Ok(Bundle(
        selected,
        state.revision(source),
        list.length(events),
        workflow_ids,
        events,
        content_hash,
      ))
    }
  }
}

pub fn decode_bundle(
  text: String,
  expected_hash: Sha256,
) -> Result(Bundle, PortableError) {
  case json.parse(text, envelope_decoder()) {
    Error(_) -> Error(InvalidJson)
    Ok(#(payload, stored_hash)) -> {
      let Payload(
        selection,
        source_revision,
        portable_revision,
        workflow_ids,
        events,
      ) = payload
      let assert Ok(actual_hash) =
        payload |> payload_json |> json.to_string |> hash.text
      case actual_hash == stored_hash, actual_hash == expected_hash {
        False, _ -> Error(ContentHashMismatch)
        _, False -> Error(ExpectedContentHashMismatch)
        True, True -> {
          let bundle =
            Bundle(
              selection,
              source_revision,
              portable_revision,
              workflow_ids,
              events,
              actual_hash,
            )
          use _ <- result.try(validate_canonical_text(bundle, text))
          use replayed <- result.try(
            state.replay(events)
            |> result.map_error(InvalidEventLog),
          )
          use _ <- result.try(validate_metadata(bundle, replayed))
          Ok(bundle)
        }
      }
    }
  }
}

fn validate_canonical_text(
  bundle: Bundle,
  supplied: String,
) -> Result(Nil, PortableError) {
  case encode(bundle) == supplied {
    True -> Ok(Nil)
    False -> Error(NonCanonicalEncoding)
  }
}

fn validate_metadata(
  bundle: Bundle,
  replayed: state.State,
) -> Result(Nil, PortableError) {
  let replayed_workflows = state.workflows(replayed)
  let replayed_ids = list.map(replayed_workflows, state.workflow_id)
  let canonical_events = state.canonical_event_log(replayed_workflows)
  let selection_matches = case bundle.selection {
    AllWorkflows -> bundle.source_revision == bundle.portable_revision
    ExactWorkflow(id) -> bundle.workflow_ids == [id]
  }
  case
    bundle.source_revision >= bundle.portable_revision,
    state.revision(replayed) == bundle.portable_revision,
    replayed_ids == bundle.workflow_ids,
    canonical_events == bundle.events,
    selection_matches
  {
    True, True, True, True, True -> Ok(Nil)
    _, _, _, _, _ -> Error(MetadataMismatch)
  }
}

pub fn encode(value: Bundle) -> String {
  value |> as_json |> json.to_string <> "\n"
}

pub fn as_json(value: Bundle) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/swing-workbench-portable-state")),
    #("schema_version", json.int(schema_version)),
    #(
      "payload",
      payload_json(Payload(
        value.selection,
        value.source_revision,
        value.portable_revision,
        value.workflow_ids,
        value.events,
      )),
    ),
    #(
      "canonical_content_hash",
      value.canonical_content_hash
        |> identity.sha256_value
        |> json.string,
    ),
  ])
}

fn payload_json(value: Payload) -> json.Json {
  json.object([
    #("selection", selection_json(value.selection)),
    #("source_revision", json.int(value.source_revision)),
    #("portable_revision", json.int(value.portable_revision)),
    #("workflow_ids", json.array(value.workflow_ids, json.string)),
    #("events", json.array(value.events, json.string)),
    #("decision_owner", json.string("llm")),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

fn selection_json(value: Selection) -> json.Json {
  case value {
    AllWorkflows -> json.object([#("kind", json.string("all_workflows"))])
    ExactWorkflow(id) ->
      json.object([
        #("kind", json.string("exact_workflow")),
        #("workflow_id", json.string(id)),
      ])
  }
}

fn envelope_decoder() -> decode.Decoder(#(Payload, Sha256)) {
  use schema <- decode.field("schema", decode.string)
  use version <- decode.field("schema_version", decode.int)
  use payload <- decode.field("payload", payload_decoder())
  use content_hash <- decode.field("canonical_content_hash", sha_decoder())
  case
    schema == "pi-sparkles/swing-workbench-portable-state",
    version == schema_version
  {
    True, True -> decode.success(#(payload, content_hash))
    _, _ ->
      decode.failure(
        #(placeholder_payload(), placeholder_hash()),
        "portable state v1",
      )
  }
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use selection <- decode.field("selection", selection_decoder())
  use source_revision <- decode.field("source_revision", decode.int)
  use portable_revision <- decode.field("portable_revision", decode.int)
  use workflow_ids <- decode.field(
    "workflow_ids",
    decode.list(of: decode.string),
  )
  use events <- decode.field("events", decode.list(of: decode.string))
  use decision_owner <- decode.field("decision_owner", decode.string)
  use plugin_fields <- decode.field(
    "plugin_decision_fields",
    decode.list(of: decode.string),
  )
  case decision_owner == "llm", plugin_fields == [] {
    True, True ->
      decode.success(Payload(
        selection,
        source_revision,
        portable_revision,
        workflow_ids,
        events,
      ))
    _, _ -> decode.failure(placeholder_payload(), "LLM-owned portable payload")
  }
}

fn selection_decoder() -> decode.Decoder(Selection) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "all_workflows" -> decode.success(AllWorkflows)
    "exact_workflow" -> {
      use workflow_id <- decode.field("workflow_id", decode.string)
      decode.success(ExactWorkflow(workflow_id))
    }
    _ -> decode.failure(AllWorkflows, "known portable selection")
  }
}

fn sha_decoder() -> decode.Decoder(Sha256) {
  decode.string
  |> decode.then(fn(value) {
    case identity.sha256(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder_hash(), "SHA-256 hex")
    }
  })
}

fn placeholder_payload() -> Payload {
  Payload(AllWorkflows, 0, 0, [], [])
}

fn placeholder_hash() -> Sha256 {
  let assert Ok(value) =
    identity.sha256(
      "0000000000000000000000000000000000000000000000000000000000000000",
    )
  value
}

pub fn selection(value: Bundle) -> Selection {
  value.selection
}

pub fn source_revision(value: Bundle) -> Int {
  value.source_revision
}

pub fn portable_revision(value: Bundle) -> Int {
  value.portable_revision
}

pub fn workflow_ids(value: Bundle) -> List(String) {
  value.workflow_ids
}

pub fn events(value: Bundle) -> List(String) {
  value.events
}

pub fn content_hash(value: Bundle) -> Sha256 {
  value.canonical_content_hash
}
