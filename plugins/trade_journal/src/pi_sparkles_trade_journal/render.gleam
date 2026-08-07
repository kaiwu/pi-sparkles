import finance_journal/context
import finance_journal/event
import finance_journal/receipt
import finance_journal/state
import finance_provenance/identity
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub fn compact_text(value: state.State) -> String {
  "Journal context journal="
  <> case state.journal_id(value) {
    None -> "empty"
    Some(id) -> id
  }
  <> " revision="
  <> string.inspect(state.revision(value))
  <> " events="
  <> string.inspect(state.event_count(value))
  <> " current="
  <> string.inspect(value |> state.current_events |> list.length)
  <> "; payload prose omitted; decision owner=LLM"
}

pub fn context_json(value: state.State, include_superseded: Bool) -> json.Json {
  value |> context.receipt(include_superseded) |> receipt.as_json
}

pub fn search_json(
  value: state.State,
  result: state.QueryResult,
  include_private_payloads: Bool,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/journal-search-result")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("revision", value |> state.revision |> json.int),
    #("matched_count", result |> state.matched_count |> json.int),
    #("omitted_count", result |> state.query_omitted_count |> json.int),
    #(
      "events",
      result
        |> state.query_events
        |> json.array(fn(value) {
          event_projection(value, include_private_payloads)
        }),
    ),
    #("context", context_json(value, True)),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
    #(
      "available_operations",
      json.array(
        [
          "inspect_event",
          "inspect_lineage",
          "query_timeline",
          "append_declaration",
          "append_review_conclusion",
          "correct_event",
          "redact_event",
          "export_journal",
        ],
        json.string,
      ),
    ),
  ])
}

pub fn search_text(
  value: state.State,
  result: state.QueryResult,
  include_private_payloads: Bool,
) -> String {
  json.object([
    #("schema", json.string("pi-sparkles/journal-search-model-context")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("revision", value |> state.revision |> json.int),
    #("matched_count", result |> state.matched_count |> json.int),
    #("omitted_count", result |> state.query_omitted_count |> json.int),
    #(
      "events",
      result
        |> state.query_events
        |> json.array(fn(value) {
          event_projection(value, include_private_payloads)
        }),
    ),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
  |> json.to_string
}

pub fn stored_text(
  value: state.State,
  stored: event.Event,
  outcome: String,
) -> String {
  json.object([
    #("schema", json.string("pi-sparkles/journal-event-handle")),
    #("schema_version", json.int(1)),
    #("outcome", json.string(outcome)),
    #("revision", value |> state.revision |> json.int),
    #("journal_id", stored |> event.journal_id |> json.string),
    #("event_id", stored |> event.event_id |> json.string),
    #(
      "workflow_id",
      stored |> event.scope |> event.workflow_id |> optional_string,
    ),
    #(
      "canonical_content_hash",
      stored
        |> event.canonical_content_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #("decision_owner", json.string("llm")),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
  |> json.to_string
}

pub fn stored_json(
  value: state.State,
  stored: event.Event,
  outcome: String,
  byte_count: Int,
  path: String,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/journal-storage-effect")),
    #("schema_version", json.int(1)),
    #("operation", json.string("append")),
    #("outcome", json.string(outcome)),
    #("journal_path", json.string(path)),
    #("revision", value |> state.revision |> json.int),
    #("stored_bytes", json.int(byte_count)),
    #("event", event.as_json(stored)),
    #("storage_capabilities", storage_capabilities(path)),
    #("decision_owner", json.string("llm")),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
    #(
      "available_operations",
      json.array(
        ["inspect_event", "append_event", "query_journal", "export_journal"],
        json.string,
      ),
    ),
  ])
}

pub fn import_json(
  value: state.State,
  outcomes: List(state.AppendOutcome),
  byte_count: Int,
  path: String,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/journal-import-result")),
    #("schema_version", json.int(1)),
    #("journal_path", json.string(path)),
    #("revision", value |> state.revision |> json.int),
    #("stored_bytes", json.int(byte_count)),
    #("event_count", outcomes |> list.length |> json.int),
    #("outcomes", json.array(outcomes, append_outcome_json)),
    #("storage_capabilities", storage_capabilities(path)),
    #("decision_owner", json.string("llm")),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

pub fn export_json(
  value: state.State,
  exported: state.ExportResult,
  path: String,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/journal-export-result")),
    #("schema_version", json.int(1)),
    #("source_journal_path", json.string(path)),
    #("revision", value |> state.revision |> json.int),
    #("format", json.string("jsonl")),
    #("jsonl", exported |> state.export_text |> json.string),
    #("event_count", exported |> state.exported_count |> json.int),
    #("omitted_count", exported |> state.export_omitted_count |> json.int),
    #(
      "content_hash",
      exported
        |> state.export_content_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #("decision_owner", json.string("llm")),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

pub fn conflict_json(
  operation: String,
  reason: String,
  current_revision: Int,
  current_bytes: Int,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/journal-storage-effect")),
    #("schema_version", json.int(1)),
    #("operation", json.string(operation)),
    #("outcome", json.string("conflict")),
    #("reason", json.string(reason)),
    #("current_revision", json.int(current_revision)),
    #("current_bytes", json.int(current_bytes)),
    #("decision_owner", json.string("llm")),
    #(
      "available_operations",
      json.array(["reload_journal", "inspect_conflict"], json.string),
    ),
  ])
}

pub fn storage_capabilities(path: String) -> json.Json {
  json.object([
    #("backend", json.string("local_jsonl_v1")),
    #("destination", json.string(path)),
    #("atomic_replace", json.bool(True)),
    #("optimistic_concurrency", json.bool(True)),
    #("exclusive_sidecar_lock", json.bool(True)),
    #("automatic_retry", json.bool(False)),
    #("ownership", unavailable("not_obtained")),
    #("encryption_at_rest", unavailable("not_obtained")),
    #("access_control", unavailable("not_obtained")),
    #("backup_status", unavailable("not_obtained")),
    #("sync_status", unavailable("not_obtained")),
    #("security_claim", json.null()),
  ])
}

fn event_projection(value: event.Event, include_private: Bool) -> json.Json {
  case event.privacy(value), include_private {
    event.Private, False ->
      json.object([
        #("journal_id", value |> event.journal_id |> json.string),
        #("event_id", value |> event.event_id |> json.string),
        #(
          "workflow_id",
          value |> event.scope |> event.workflow_id |> optional_string,
        ),
        #("event_kind", value |> event.kind |> event.kind_name |> json.string),
        #("privacy", json.string("private")),
        #("payload_omitted", json.bool(True)),
        #(
          "canonical_content_hash",
          value
            |> event.canonical_content_hash
            |> identity.sha256_value
            |> json.string,
        ),
      ])
    _, _ ->
      json.object([
        #("payload_omitted", json.bool(False)),
        #("canonical_event", event.as_json(value)),
      ])
  }
}

fn optional_string(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn append_outcome_json(value: state.AppendOutcome) -> json.Json {
  case value {
    state.Stored(value) ->
      json.object([
        #("outcome", json.string("stored")),
        #("event_id", value |> event.event_id |> json.string),
        #("event", event.as_json(value)),
      ])
    state.AlreadyStored(value) ->
      json.object([
        #("outcome", json.string("already_stored")),
        #("event_id", value |> event.event_id |> json.string),
        #("event", event.as_json(value)),
      ])
  }
}

fn unavailable(state: String) -> json.Json {
  json.object([#("state", json.string(state))])
}
