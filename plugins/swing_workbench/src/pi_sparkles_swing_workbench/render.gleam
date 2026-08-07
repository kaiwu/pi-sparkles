import finance_core/time
import finance_provenance/identity
import finance_track
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pi_sparkles_swing_workbench/domain.{type EvidenceFact, type FactChange}
import pi_sparkles_swing_workbench/portable
import pi_sparkles_swing_workbench/state.{type State, type Workflow}

pub const available_operations = [
  "attach_candidate_snapshot",
  "attach_plan_declaration",
  "attach_observation_or_review_fact",
  "attach_durable_journal_event_reference",
  "inspect_workflow",
  "inspect_strategy_receipt",
  "inspect_fact",
  "compare_latest_snapshots",
  "supply_replacement_snapshot",
  "export_caller_selected_portable_state",
  "import_caller_selected_portable_state_into_empty_branch",
]

pub fn summary(state: State, workflows: List(Workflow)) -> String {
  let header =
    "Swing workbench facts revision="
    <> int.to_string(state.revision(state))
    <> " workflows="
    <> { workflows |> list.length |> int.to_string }
    <> ". The LLM chooses every interpretation and operation."
  case workflows {
    [] -> header <> " No workflow facts are attached on this branch."
    _ ->
      [header, ..list.map(workflows, workflow_summary)]
      |> string.join(with: "\n")
  }
}

fn workflow_summary(value: Workflow) -> String {
  let latest = state.latest_snapshot(value)
  let facts = domain.facts(latest)
  let non_known =
    facts
    |> list.filter(fn(value) { domain.information_state(value) != domain.Known })
    |> list.length
  let changed =
    domain.changes(state.prior_snapshot(value), latest)
    |> list.filter(fn(value) {
      domain.change_kind(value) != domain.UnchangedFact
    })
    |> list.length
  "- workflow="
  <> state.workflow_id(value)
  <> " listing="
  <> state.listing_key(value)
  <> " strategy="
  <> state.definition_id(value)
  <> "@"
  <> state.definition_version(value)
  <> " snapshots="
  <> { value |> state.snapshots |> list.length |> int.to_string }
  <> " facts="
  <> { facts |> list.length |> int.to_string }
  <> " non_known_states="
  <> int.to_string(non_known)
  <> " changed_since_prior="
  <> int.to_string(changed)
  <> " plan_attached="
  <> bool_text(state.plan(value) != None)
  <> " review_records="
  <> { value |> state.reviews |> list.length |> int.to_string }
  <> " journal_event_references="
  <> { value |> state.journal_references |> list.length |> int.to_string }
}

pub fn snapshot_json(
  state_value: State,
  workflows: List(Workflow),
) -> json.Json {
  json.object([
    #("schema", json.string("pi_sparkles_swing_workbench_snapshot")),
    #("schemaVersion", json.int(1)),
    #("revision", json.int(state.revision(state_value))),
    #("persistence", json.string("session_branch_versioned_event_log")),
    #(
      "crossSessionPersistence",
      json.string(
        "caller_selected_portable_event_log_and_external_journal_references",
      ),
    ),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], fn(value) { json.string(value) })),
    #("maximumWorkflows", json.int(state.maximum_workflow_count())),
    #("maximumSnapshotsPerWorkflow", json.int(state.maximum_snapshots())),
    #("maximumReviewsPerWorkflow", json.int(state.maximum_reviews())),
    #(
      "maximumJournalReferencesPerWorkflow",
      json.int(state.maximum_journal_references()),
    ),
    #("maximumRevision", json.int(state.maximum_event_revision())),
    #("workflows", json.array(workflows, workflow_json)),
    #("availableOperations", json.array(available_operations, json.string)),
  ])
}

pub fn portable_result_text(
  operation: String,
  outcome: String,
  path: String,
  bundle: portable.Bundle,
) -> String {
  json.object([
    #("operation", json.string(operation)),
    #("outcome", json.string(outcome)),
    #("portablePath", json.string(path)),
    #(
      "canonicalContentHash",
      bundle
        |> portable.content_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #("sourceRevision", bundle |> portable.source_revision |> json.int),
    #("portableRevision", bundle |> portable.portable_revision |> json.int),
    #("workflowIds", bundle |> portable.workflow_ids |> json.array(json.string)),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], fn(value) { json.string(value) })),
  ])
  |> json.to_string
}

pub fn portable_export_json(
  bundle: portable.Bundle,
  path: String,
  outcome: String,
  byte_count: Int,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/swing-portable-storage-effect")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string("export")),
    #("outcome", json.string(outcome)),
    #("portablePath", json.string(path)),
    #("storedBytes", json.int(byte_count)),
    #(
      "canonicalContentHash",
      bundle
        |> portable.content_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #("sourceRevision", bundle |> portable.source_revision |> json.int),
    #("portableRevision", bundle |> portable.portable_revision |> json.int),
    #("workflowIds", bundle |> portable.workflow_ids |> json.array(json.string)),
    #("bundle", portable.as_json(bundle)),
    #("storageCapabilities", portable_storage_capabilities(path)),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], fn(value) { json.string(value) })),
    #(
      "availableOperations",
      json.array(
        [
          "retain_portable_handle",
          "import_into_empty_branch",
          "export_new_path",
        ],
        json.string,
      ),
    ),
  ])
}

pub fn portable_import_json(
  bundle: portable.Bundle,
  restored: State,
  path: String,
  outcome: String,
  byte_count: Int,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/swing-portable-storage-effect")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string("import")),
    #("outcome", json.string(outcome)),
    #("portablePath", json.string(path)),
    #("loadedBytes", json.int(byte_count)),
    #(
      "canonicalContentHash",
      bundle
        |> portable.content_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #("sourceRevision", bundle |> portable.source_revision |> json.int),
    #("portableRevision", bundle |> portable.portable_revision |> json.int),
    #("workflowIds", bundle |> portable.workflow_ids |> json.array(json.string)),
    #("snapshot", snapshot_json(restored, state.workflows(restored))),
    #("storageCapabilities", portable_storage_capabilities(path)),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], fn(value) { json.string(value) })),
    #(
      "availableOperations",
      json.array(
        [
          "inspect_restored_workflows",
          "attach_new_information",
          "export_new_path",
        ],
        json.string,
      ),
    ),
  ])
}

pub fn portable_conflict_json(
  operation: String,
  reason: String,
  current_revision: Int,
  current_bytes: Int,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/swing-portable-storage-effect")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string(operation)),
    #("outcome", json.string("conflict")),
    #("reason", json.string(reason)),
    #("currentRevision", json.int(current_revision)),
    #("currentBytes", json.int(current_bytes)),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], fn(value) { json.string(value) })),
    #(
      "availableOperations",
      json.array(
        ["inspect_conflict", "choose_new_path", "inspect_current_branch"],
        json.string,
      ),
    ),
  ])
}

fn portable_storage_capabilities(path: String) -> json.Json {
  json.object([
    #("backend", json.string("local_canonical_json_v1")),
    #("destination", json.string(path)),
    #("atomic_create", json.bool(True)),
    #("idempotent_exact_retry", json.bool(True)),
    #("overwrite", json.bool(False)),
    #("merge", json.bool(False)),
    #("automatic_retry", json.bool(False)),
    #("ownership", unavailable("not_obtained")),
    #("encryption_at_rest", unavailable("not_obtained")),
    #("access_control", unavailable("not_obtained")),
    #("backup_status", unavailable("not_obtained")),
    #("sync_status", unavailable("not_obtained")),
    #("security_claim", json.null()),
  ])
}

fn unavailable(value: String) -> json.Json {
  json.object([#("state", json.string(value))])
}

pub fn workflow_json(value: Workflow) -> json.Json {
  let latest = state.latest_snapshot(value)
  json.object([
    #("workflowId", json.string(state.workflow_id(value))),
    #("listingKey", json.string(state.listing_key(value))),
    #("definitionId", json.string(state.definition_id(value))),
    #("definitionVersion", json.string(state.definition_version(value))),
    #("track", latest |> domain.track |> finance_track.name |> json.string),
    #("snapshots", value |> state.snapshots |> json.array(candidate_json)),
    #(
      "latestChanges",
      changes_json(domain.changes(state.prior_snapshot(value), latest)),
    ),
    #("plan", case state.plan(value) {
      None -> json.null()
      Some(plan) -> plan_json(plan)
    }),
    #("reviewRecords", value |> state.reviews |> json.array(review_json)),
    #(
      "journalEventReferences",
      value |> state.journal_references |> json.array(journal_reference_json),
    ),
    #("availableOperations", json.array(available_operations, json.string)),
  ])
}

fn journal_reference_json(value: domain.JournalEventReference) -> json.Json {
  json.object([
    #("workflowId", json.string(domain.journal_workflow_id(value))),
    #("journalId", json.string(domain.journal_id(value))),
    #("eventId", json.string(domain.journal_event_id(value))),
    #(
      "canonicalContentHash",
      value
        |> domain.journal_event_content_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #("relation", json.string(domain.journal_relation(value))),
    #(
      "attachedAtUnixMs",
      value |> domain.journal_attached_at |> time.unix_milliseconds |> json.int,
    ),
  ])
}

fn plan_json(value: domain.PlanRecord) -> json.Json {
  json.object([
    #("workflowId", json.string(domain.plan_workflow_id(value))),
    #(
      "sourceStrategyReceiptHash",
      value
        |> domain.source_strategy_receipt_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #(
      "planReceiptHash",
      value |> domain.plan_receipt_hash |> identity.sha256_value |> json.string,
    ),
    #("planPayload", json.string(domain.plan_payload(value))),
    #(
      "origin",
      value |> domain.plan_origin |> domain.origin_name |> json.string,
    ),
    #(
      "riskReceiptReferences",
      hashes_json(domain.risk_receipt_references(value)),
    ),
    #(
      "ruleReceiptReferences",
      hashes_json(domain.rule_receipt_references(value)),
    ),
    #(
      "executionReceiptReferences",
      hashes_json(domain.execution_receipt_references(value)),
    ),
    #(
      "createdAtUnixMs",
      value |> domain.plan_created_at |> time.unix_milliseconds |> json.int,
    ),
  ])
}

fn review_json(value: domain.ReviewRecord) -> json.Json {
  json.object([
    #("workflowId", json.string(domain.review_workflow_id(value))),
    #("recordId", json.string(domain.record_id(value))),
    #("recordKind", json.string(domain.record_kind(value))),
    #(
      "payloadHash",
      value
        |> domain.review_payload_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #("payload", json.string(domain.review_payload(value))),
    #(
      "planReceiptReference",
      json.nullable(domain.plan_receipt_reference(value), fn(reference) {
        reference |> identity.sha256_value |> json.string
      }),
    ),
    #(
      "evidenceReferences",
      hashes_json(domain.review_evidence_references(value)),
    ),
    #(
      "observedAtUnixMs",
      value |> domain.observed_at |> time.unix_milliseconds |> json.int,
    ),
  ])
}

pub fn candidate_json(value: domain.CandidateSnapshot) -> json.Json {
  let #(year, month, day) = value |> domain.signal_session |> time.date_parts
  json.object([
    #("workflowId", json.string(domain.workflow_id(value))),
    #("listingKey", json.string(domain.listing_key(value))),
    #("track", value |> domain.track |> finance_track.name |> json.string),
    #("definitionId", json.string(domain.definition_id(value))),
    #("definitionVersion", json.string(domain.definition_version(value))),
    #(
      "definitionHash",
      value |> domain.definition_hash |> identity.sha256_value |> json.string,
    ),
    #(
      "signalSession",
      json.object([
        #("year", json.int(year)),
        #("month", json.int(month)),
        #("day", json.int(day)),
      ]),
    ),
    #(
      "strategyReceiptHash",
      value
        |> domain.strategy_receipt_hash
        |> identity.sha256_value
        |> json.string,
    ),
    #(
      "strategyReceiptPayload",
      json.string(domain.strategy_receipt_payload(value)),
    ),
    #("facts", value |> domain.facts |> json.array(fact_json)),
    #(
      "attachedAtUnixMs",
      value |> domain.attached_at |> time.unix_milliseconds |> json.int,
    ),
  ])
}

pub fn fact_json(value: EvidenceFact) -> json.Json {
  json.object([
    #("factId", json.string(domain.fact_id(value))),
    #("role", value |> domain.fact_role |> domain.fact_role_name |> json.string),
    #(
      "state",
      value
        |> domain.information_state
        |> domain.information_state_name
        |> json.string,
    ),
    #("detail", json.string(domain.fact_detail(value))),
    #(
      "receiptReferences",
      value
        |> domain.fact_receipt_references
        |> list.map(identity.sha256_value)
        |> json.array(json.string),
    ),
  ])
}

fn changes_json(values: List(FactChange)) -> json.Json {
  json.array(values, fn(value) {
    json.object([
      #("factId", json.string(domain.change_fact_id(value))),
      #(
        "change",
        value |> domain.change_kind |> domain.change_kind_name |> json.string,
      ),
      #("previous", optional_fact_json(domain.previous_fact(value))),
      #("current", optional_fact_json(domain.current_fact(value))),
    ])
  })
}

fn optional_fact_json(value: Option(EvidenceFact)) -> json.Json {
  case value {
    None -> json.null()
    Some(value) -> fact_json(value)
  }
}

fn hashes_json(values: List(identity.Sha256)) -> json.Json {
  values
  |> list.map(identity.sha256_value)
  |> json.array(json.string)
}

fn bool_text(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
