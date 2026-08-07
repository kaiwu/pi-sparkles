import finance_provenance/identity.{type Sha256}
import finance_replay/trial.{type Counts}
import finance_replay/wire
import finance_track.{type Track}
import gleam/json

pub type EventCounts {
  EventCounts(
    total: Int,
    observations: Int,
    corrections: Int,
    features_produced: Int,
    features_omitted: Int,
    instructions: Int,
    execution_branches: Int,
    terminal_events: Int,
  )
}

pub type OmittedCounts {
  OmittedCounts(event_payloads: Int, trial_payloads: Int, private_payloads: Int)
}

pub type Context {
  Context(
    active_hypothesis_handle: Sha256,
    active_run_definition_handle: Sha256,
    track: Track,
    universe_handle: Sha256,
    dataset_handle: Sha256,
    partition_handle: Sha256,
    replay_state_handle: Sha256,
    event_counts: EventCounts,
    trial_counts: Counts,
    unknown_counts: List(#(String, Int)),
    conflict_counts: List(#(String, Int)),
    ambiguity_counts: List(#(String, Int)),
    trial_ledger_cursor: Sha256,
    reproduction_manifest_handle: Sha256,
    omitted_counts: OmittedCounts,
  )
}

pub fn as_json(value: Context) -> json.Json {
  let Context(
    hypothesis,
    run_definition,
    track,
    universe,
    dataset,
    partition,
    replay_state,
    event_counts,
    trial_counts,
    unknown_counts,
    conflict_counts,
    ambiguity_counts,
    trial_cursor,
    reproduction,
    omitted_counts,
  ) = value
  json.object([
    #("schema", json.string("pi-sparkles/research-context")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("active_hypothesis_handle", wire.sha_json(hypothesis)),
    #("active_run_definition_handle", wire.sha_json(run_definition)),
    #(
      "versions",
      json.object([
        #("track", wire.track_json(track)),
        #("universe", wire.sha_json(universe)),
        #("dataset", wire.sha_json(dataset)),
        #("partition", wire.sha_json(partition)),
      ]),
    ),
    #("replay_state_handle", wire.sha_json(replay_state)),
    #("event_counts", event_counts_json(event_counts)),
    #("trial_counts", trial_counts_json(trial_counts)),
    #("unknown_counts", count_pairs_json(unknown_counts)),
    #("conflict_counts", count_pairs_json(conflict_counts)),
    #("ambiguity_counts", count_pairs_json(ambiguity_counts)),
    #("trial_ledger_cursor", wire.sha_json(trial_cursor)),
    #("reproduction_manifest_handle", wire.sha_json(reproduction)),
    #("omitted_counts", omitted_counts_json(omitted_counts)),
    #(
      "available_operations",
      json.array(
        [
          "inspect_run_definition",
          "inspect_replay_events",
          "compare_runs",
          "request_metric",
          "list_trials",
          "export_reproduction_manifest",
          "resume_from_checkpoint",
        ],
        json.string,
      ),
    ),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

fn event_counts_json(value: EventCounts) -> json.Json {
  let EventCounts(
    total,
    observations,
    corrections,
    features_produced,
    features_omitted,
    instructions,
    branches,
    terminals,
  ) = value
  json.object([
    #("total", json.int(total)),
    #("observations", json.int(observations)),
    #("corrections", json.int(corrections)),
    #("features_produced", json.int(features_produced)),
    #("features_omitted", json.int(features_omitted)),
    #("instructions", json.int(instructions)),
    #("execution_branches", json.int(branches)),
    #("terminal_events", json.int(terminals)),
  ])
}

fn trial_counts_json(value: Counts) -> json.Json {
  let trial.Counts(
    total,
    completed,
    failed,
    cancelled,
    truncated,
    duplicate,
    unperformed,
  ) = value
  json.object([
    #("total", json.int(total)),
    #("completed", json.int(completed)),
    #("failed", json.int(failed)),
    #("cancelled", json.int(cancelled)),
    #("truncated", json.int(truncated)),
    #("duplicate", json.int(duplicate)),
    #("unperformed", json.int(unperformed)),
  ])
}

fn count_pairs_json(values: List(#(String, Int))) -> json.Json {
  json.array(values, fn(value) {
    json.object([
      #("family", json.string(value.0)),
      #("count", json.int(value.1)),
    ])
  })
}

fn omitted_counts_json(value: OmittedCounts) -> json.Json {
  let OmittedCounts(events, trials, private) = value
  json.object([
    #("event_payloads", json.int(events)),
    #("trial_payloads", json.int(trials)),
    #("private_payloads", json.int(private)),
  ])
}
