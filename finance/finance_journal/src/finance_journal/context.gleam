import finance_journal/event
import finance_journal/receipt.{type Envelope}
import finance_journal/state.{type State}
import gleam/json
import gleam/list
import gleam/option.{None, Some}

pub const available_operations = [
  "inspect_event",
  "inspect_lineage",
  "query_timeline",
  "query_declared_labels",
  "attach_declaration",
  "attach_observation_reference",
  "attach_review_conclusion",
  "request_plan_observation_comparison",
  "request_metric",
  "correct_event",
  "redact_event",
  "export_journal",
]

pub fn receipt(
  value: State,
  include_superseded include_superseded_value: Bool,
) -> Envelope {
  let events = case include_superseded_value {
    True -> state.events(value)
    False -> state.current_events(value)
  }
  let private_count =
    events
    |> list.filter(fn(value) { event.privacy(value) == event.Private })
    |> list.length
  let all_count = value |> state.events |> list.length
  let current_count = value |> state.current_events |> list.length
  json.object([
    #("schema", json.string("pi-sparkles/journal-context")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("journal_id", case state.journal_id(value) {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
    #("revision", json.int(state.revision(value))),
    #("event_count", json.int(list.length(events))),
    #("current_event_count", json.int(current_count)),
    #("superseded_event_count", json.int(all_count - current_count)),
    #(
      "by_event_kind",
      count_pairs(events, fn(value) { value |> event.kind |> event.kind_name }),
    ),
    #(
      "by_attribution",
      count_pairs(events, fn(value) {
        value |> event.attribution |> event.attribution_name
      }),
    ),
    #(
      "omitted_counts",
      json.object([#("private_payloads", json.int(private_count))]),
    ),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
    #("available_operations", json.array(available_operations, json.string)),
  ])
  |> receipt.envelope
}

fn count_pairs(
  values: List(event.Event),
  key: fn(event.Event) -> String,
) -> json.Json {
  values
  |> list.map(key)
  |> list.unique
  |> list.map(fn(name) {
    #(
      name,
      values
        |> list.filter(fn(value) { key(value) == name })
        |> list.length
        |> json.int,
    )
  })
  |> json.object
}
