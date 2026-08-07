import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pi
import pi/context
import pi/event
import pi/raw
import pi/schema
import pi/session
import pi/tool
import pi/ui
import pi_sparkles_swing_workbench/decode as input_decode
import pi_sparkles_swing_workbench/domain
import pi_sparkles_swing_workbench/effect/store
import pi_sparkles_swing_workbench/portable
import pi_sparkles_swing_workbench/render
import pi_sparkles_swing_workbench/state
import pi_sparkles_swing_workbench_portable_file as portable_file

const event_entry_type = "pi_sparkles_swing_workbench.event.v1"

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let runtime = store.new(None)

  event.on_session_start(api, fn(_start, ctx) {
    restore(runtime, ctx)
    promise.resolve(Nil)
  })
  event.on_session_tree(api, fn(_tree, ctx) {
    restore(runtime, ctx)
    promise.resolve(Nil)
  })

  pi.register_command(
    api,
    "swing",
    "Show exact branch-scoped swing workflow facts without selecting a decision or next step",
    fn(args, ctx) {
      let selected = case string.trim(args) {
        "" -> None
        value -> Some(value)
      }
      case current(runtime) {
        Error(message) -> notify(ctx, message, ui.Error)
        Ok(state_value) ->
          case state.selected_workflows(state_value, selected) {
            Error(error) ->
              notify(
                ctx,
                "Swing workflow lookup failed: " <> string.inspect(error),
                ui.Error,
              )
            Ok(workflows) ->
              notify(ctx, render.summary(state_value, workflows), ui.Info)
          }
      }
      promise.resolve(Nil)
    },
  )

  tool.register(
    api,
    "swing_candidates",
    "Attach swing candidate evidence",
    "Attach one exact finance_strategy receipt and bounded sourced dependency facts to a branch workflow; returns changes without qualification, rank, recommendation, or selected operation",
    "Supply the canonical finance_strategy evidence JSON and its SHA-256 hash; every interpretation remains with the LLM",
    tool.parameters(candidate_schema(), input_decode.candidate_decoder()),
    tool.Sequential,
    fn(_id, input, _signal, _updates, _ctx) {
      case current(runtime) {
        Error(message) -> tool.reject(message)
        Ok(state_value) -> attach_candidate(api, runtime, state_value, input)
      }
    },
  )

  tool.register(
    api,
    "swing_plan",
    "Attach immutable swing plan declaration",
    "Attach an exact LLM- or user-authored non-executable declaration and its risk, rule, and execution receipt references; this tool does not accept, authorize, or transform it",
    "The plan payload is opaque user/LLM data and its supplied SHA-256 must match exactly",
    tool.parameters(plan_schema(), input_decode.plan_decoder()),
    tool.Sequential,
    fn(_id, input, _signal, _updates, _ctx) {
      case current(runtime) {
        Error(message) -> tool.reject(message)
        Ok(state_value) -> attach_plan(api, runtime, state_value, input)
      }
    },
  )

  tool.register(
    api,
    "swing_review",
    "Attach swing observation or review fact",
    "Append an exact content-bound observation, expiry, exit, ambiguity, or user/LLM review record without judging process quality, outcome, or the next operation",
    "Use recordKind as caller vocabulary and retain every source receipt reference",
    tool.parameters(review_schema(), input_decode.review_decoder()),
    tool.Sequential,
    fn(_id, input, _signal, _updates, _ctx) {
      case current(runtime) {
        Error(message) -> tool.reject(message)
        Ok(state_value) -> attach_review(api, runtime, state_value, input)
      }
    },
  )

  tool.register(
    api,
    "swing_journal_link",
    "Attach durable journal event reference",
    "Attach an exact journal ID, event ID, canonical event hash, and caller-named relation to an existing workflow; this tool does not read, trust, interpret, or select the journal event",
    "Supply the handle returned by trade_journal after the LLM or caller chooses to retain that relation",
    tool.parameters(journal_link_schema(), input_decode.journal_link_decoder()),
    tool.Sequential,
    fn(_id, input, _signal, _updates, _ctx) {
      case current(runtime) {
        Error(message) -> tool.reject(message)
        Ok(state_value) ->
          attach_journal_reference(api, runtime, state_value, input)
      }
    },
  )

  tool.register(
    api,
    "swing_snapshot",
    "Export swing workflow facts",
    "Return a deterministic versioned snapshot of all branch workflows or one exact workflow, including receipt payloads, changes, declarations, review facts, and neutral available operations",
    "This is the current branch projection, not a workflow verdict; use swing_state_export only when the LLM or caller chooses an exact portable selection and path",
    tool.parameters(snapshot_schema(), input_decode.snapshot_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      let input_decode.SnapshotInput(selected) = input
      case current(runtime) {
        Error(message) -> tool.reject(message)
        Ok(state_value) ->
          case state.selected_workflows(state_value, selected) {
            Error(error) ->
              tool.reject(
                "Swing workflow snapshot failed: " <> string.inspect(error),
              )
            Ok(workflows) ->
              tool.text_result(
                render.summary(state_value, workflows),
                render.snapshot_json(state_value, workflows),
              )
              |> promise.resolve
          }
      }
    },
  )

  tool.register(
    api,
    "swing_state_export",
    "Persist caller-selected swing state",
    "Write a canonical content-bound reconstruction log for all workflows or one exact workflow to a new caller-selected local file; exact retries are idempotent and differing existing content is a conflict",
    "The LLM or caller chooses the path and workflow selection; this tool never selects storage, overwrites a different file, interprets state, or chooses a later operation",
    tool.parameters(
      portable_export_schema(),
      input_decode.portable_export_decoder(),
    ),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      case current(runtime) {
        Error(message) -> tool.reject(message)
        Ok(state_value) ->
          export_portable(state_value, input, raw.dynamic(signal))
      }
    },
  )

  tool.register(
    api,
    "swing_state_import",
    "Restore caller-selected swing state",
    "Load one exact content-bound workbench reconstruction log from a caller-selected local file into an empty branch; identical retries are idempotent and merge or overwrite is never selected",
    "Supply the exact canonical hash returned by swing_state_export and expectedCurrentRevision=0; the LLM or caller chooses whether and what to restore",
    tool.parameters(
      portable_import_schema(),
      input_decode.portable_import_decoder(),
    ),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      case current(runtime) {
        Error(message) -> tool.reject(message)
        Ok(state_value) ->
          import_portable(api, runtime, state_value, input, raw.dynamic(signal))
      }
    },
  )

  promise.resolve(Nil)
}

fn candidate_schema() -> schema.Schema {
  schema.object([
    schema.Required("workflowId", bounded_string(1, 200)),
    schema.Required("strategyReceiptHash", bounded_string(64, 64)),
    schema.Required("strategyReceiptPayload", bounded_string(2, 200_000)),
    schema.Required(
      "facts",
      schema.array(fact_schema())
        |> schema.with_array_length(0, domain.maximum_facts_per_snapshot),
    ),
    schema.Required("attachedAtUnixMs", schema.integer()),
  ])
}

fn plan_schema() -> schema.Schema {
  schema.object([
    schema.Required("workflowId", bounded_string(1, 200)),
    schema.Required("sourceStrategyReceiptHash", bounded_string(64, 64)),
    schema.Required("planReceiptHash", bounded_string(64, 64)),
    schema.Required("planPayload", bounded_string(1, 20_000)),
    schema.Required(
      "origin",
      schema.string_enum(["llm_authored", "user_authored"]),
    ),
    schema.Required("riskReceiptReferences", hash_array_schema()),
    schema.Required("ruleReceiptReferences", hash_array_schema()),
    schema.Required("executionReceiptReferences", hash_array_schema()),
    schema.Required("createdAtUnixMs", schema.integer()),
  ])
}

fn review_schema() -> schema.Schema {
  schema.object([
    schema.Required("workflowId", bounded_string(1, 200)),
    schema.Required("recordId", bounded_string(1, 200)),
    schema.Required("recordKind", bounded_string(1, 200)),
    schema.Required("payloadHash", bounded_string(64, 64)),
    schema.Required("payload", bounded_string(1, 20_000)),
    schema.Optional(
      "planReceiptReference",
      schema.nullable(bounded_string(64, 64)),
    ),
    schema.Required("evidenceReferences", hash_array_schema()),
    schema.Required("observedAtUnixMs", schema.integer()),
  ])
}

fn journal_link_schema() -> schema.Schema {
  schema.object([
    schema.Required("workflowId", bounded_string(1, 200)),
    schema.Required("journalId", bounded_string(1, 200)),
    schema.Required("eventId", bounded_string(1, 200)),
    schema.Required("canonicalContentHash", bounded_string(64, 64)),
    schema.Required("relation", bounded_string(1, 200)),
    schema.Required("attachedAtUnixMs", schema.integer()),
  ])
}

fn snapshot_schema() -> schema.Schema {
  schema.object([
    schema.Optional("workflowId", schema.nullable(bounded_string(1, 200))),
  ])
}

fn portable_export_schema() -> schema.Schema {
  schema.object([
    schema.Required("portablePath", bounded_string(1, 4096)),
    schema.Optional("workflowId", schema.nullable(bounded_string(1, 200))),
    schema.Required("maximumPortableBytes", bounded_integer(1, 100_000_000)),
  ])
}

fn portable_import_schema() -> schema.Schema {
  schema.object([
    schema.Required("portablePath", bounded_string(1, 4096)),
    schema.Required("expectedContentHash", bounded_string(64, 64)),
    schema.Required("expectedCurrentRevision", bounded_integer(0, 0)),
    schema.Required("maximumPortableBytes", bounded_integer(1, 100_000_000)),
  ])
}

fn fact_schema() -> schema.Schema {
  schema.object([
    schema.Required("factId", bounded_string(1, 200)),
    schema.Required(
      "role",
      schema.string_enum(["required", "optional", "ranking", "context"]),
    ),
    schema.Required(
      "state",
      schema.string_enum([
        "known",
        "unknown",
        "not_obtained",
        "conflicting",
        "decode_failure",
        "declared",
        "unsupported",
        "stale",
        "late",
      ]),
    ),
    schema.Required("detail", bounded_string(1, 1000)),
    schema.Required("receiptReferences", hash_array_schema()),
  ])
}

fn hash_array_schema() -> schema.Schema {
  schema.array(bounded_string(64, 64))
  |> schema.with_array_length(0, domain.maximum_receipt_references)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Int, maximum: Int) -> schema.Schema {
  schema.integer()
  |> schema.with_number_range(minimum |> int.to_float, maximum |> int.to_float)
}

fn attach_candidate(
  api: pi.ExtensionApi,
  runtime: store.Store(Option(Result(state.State, String))),
  state_value: state.State,
  input: input_decode.CandidateInput,
) -> Promise(tool.ToolResult) {
  let input_decode.CandidateInput(
    workflow_id,
    hash,
    payload,
    facts,
    attached_at,
  ) = input
  case
    domain.candidate_snapshot(workflow_id, hash, payload, facts, attached_at)
  {
    Error(error) ->
      tool.reject(
        "Swing candidate snapshot rejected mechanically: "
        <> string.inspect(error),
      )
    Ok(snapshot) ->
      case state.attach_candidate(state_value, snapshot) {
        Error(error) -> reject_state(error)
        Ok(#(next, state.CandidateStored(_, changes))) -> {
          persist_candidate(api, runtime, next, snapshot)
          let assert Ok([workflow]) =
            state.selected_workflows(next, Some(workflow_id))
          tool.text_result(
            "Swing candidate facts attached workflow="
              <> workflow_id
              <> " revision="
              <> string.inspect(state.revision(next))
              <> " changed_facts="
              <> {
              changes
              |> list.filter(fn(value) {
                domain.change_kind(value) != domain.UnchangedFact
              })
              |> list.length
              |> string.inspect
            },
            render.workflow_json(workflow),
          )
          |> promise.resolve
        }
        Ok(#(_, _)) -> tool.reject("Unexpected candidate state transition")
      }
  }
}

fn attach_plan(
  api: pi.ExtensionApi,
  runtime: store.Store(Option(Result(state.State, String))),
  state_value: state.State,
  input: input_decode.PlanInput,
) -> Promise(tool.ToolResult) {
  let input_decode.PlanInput(
    workflow_id,
    source_hash,
    plan_hash,
    payload,
    origin,
    risk,
    rules,
    execution,
    created_at,
  ) = input
  case
    domain.plan_record(
      workflow_id,
      source_hash,
      plan_hash,
      payload,
      origin,
      risk,
      rules,
      execution,
      created_at,
    )
  {
    Error(error) ->
      tool.reject(
        "Swing plan declaration rejected mechanically: "
        <> string.inspect(error),
      )
    Ok(plan) ->
      case state.attach_plan(state_value, plan) {
        Error(error) -> reject_state(error)
        Ok(#(next, state.PlanStored(_))) -> {
          persist_plan(api, runtime, next, plan)
          workflow_result(next, workflow_id, "Swing plan declaration attached")
        }
        Ok(#(next, state.PlanUnchanged(_))) ->
          workflow_result(
            next,
            workflow_id,
            "Identical swing plan declaration already attached",
          )
        Ok(#(_, _)) -> tool.reject("Unexpected plan state transition")
      }
  }
}

fn attach_review(
  api: pi.ExtensionApi,
  runtime: store.Store(Option(Result(state.State, String))),
  state_value: state.State,
  input: input_decode.ReviewInput,
) -> Promise(tool.ToolResult) {
  let input_decode.ReviewInput(
    workflow_id,
    record_id,
    record_kind,
    payload_hash,
    payload,
    plan_reference,
    references,
    observed_at,
  ) = input
  case
    domain.review_record(
      workflow_id,
      record_id,
      record_kind,
      payload_hash,
      payload,
      plan_reference,
      references,
      observed_at,
    )
  {
    Error(error) ->
      tool.reject(
        "Swing review fact rejected mechanically: " <> string.inspect(error),
      )
    Ok(review) ->
      case state.attach_review(state_value, review) {
        Error(error) -> reject_state(error)
        Ok(#(next, state.ReviewStored(_))) -> {
          persist_review(api, runtime, next, review)
          workflow_result(next, workflow_id, "Swing review fact attached")
        }
        Ok(#(_, _)) -> tool.reject("Unexpected review state transition")
      }
  }
}

fn attach_journal_reference(
  api: pi.ExtensionApi,
  runtime: store.Store(Option(Result(state.State, String))),
  state_value: state.State,
  input: input_decode.JournalLinkInput,
) -> Promise(tool.ToolResult) {
  let input_decode.JournalLinkInput(
    workflow_id,
    journal_id,
    event_id,
    content_hash,
    relation,
    attached_at,
  ) = input
  case
    domain.journal_event_reference(
      workflow_id,
      journal_id,
      event_id,
      content_hash,
      relation,
      attached_at,
    )
  {
    Error(error) ->
      tool.reject(
        "Swing journal reference rejected mechanically: "
        <> string.inspect(error),
      )
    Ok(reference) ->
      case state.attach_journal_reference(state_value, reference) {
        Error(error) -> reject_state(error)
        Ok(#(next, state.JournalReferenceStored(_))) -> {
          persist_journal_reference(api, runtime, next, reference)
          workflow_result(next, workflow_id, "Journal event reference attached")
        }
        Ok(#(next, state.JournalReferenceUnchanged(_))) ->
          workflow_result(
            next,
            workflow_id,
            "Identical journal event reference already attached",
          )
        Ok(#(_, _)) -> tool.reject("Unexpected journal reference transition")
      }
  }
}

fn export_portable(
  state_value: state.State,
  input: input_decode.PortableExportInput,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input_decode.PortableExportInput(path, selected, maximum_bytes) = input
  case state.selected_workflows(state_value, selected) {
    Error(error) ->
      tool.reject(
        "Swing portable export selection failed: " <> string.inspect(error),
      )
    Ok(workflows) -> {
      let selection = case selected {
        None -> portable.AllWorkflows
        Some(id) -> portable.ExactWorkflow(id)
      }
      case portable.build(state_value, workflows, selection) {
        Error(error) ->
          tool.reject(
            "Swing portable export rejected mechanically: "
            <> string.inspect(error),
          )
        Ok(bundle) -> {
          let replacement = portable.encode(bundle)
          use read_outcome <- promise.await(portable_file.read(
            path,
            maximum_bytes,
            signal,
          ))
          case read_outcome {
            portable_file.Missing ->
              persist_portable_export(
                path,
                replacement,
                maximum_bytes,
                signal,
                state_value,
                bundle,
              )
            portable_file.Loaded(existing, bytes) ->
              case existing == replacement {
                True ->
                  portable_export_result(bundle, path, "already_stored", bytes)
                False ->
                  portable_conflict_result(
                    "export",
                    "destination_exists_with_different_content",
                    state.revision(state_value),
                    bytes,
                  )
              }
            portable_file.ReadCancelled ->
              tool.reject("Swing portable export read cancelled")
            portable_file.ReadTooLarge(received, maximum) ->
              tool.reject(
                "Swing portable destination exceeds byte bound received="
                <> string.inspect(received)
                <> " maximum="
                <> string.inspect(maximum),
              )
            portable_file.ReadFailure(code) ->
              tool.reject("Swing portable storage read failed code=" <> code)
            portable_file.InvalidReadResult ->
              tool.reject(
                "Swing portable storage returned an invalid read result",
              )
          }
        }
      }
    }
  }
}

fn persist_portable_export(
  path: String,
  replacement: String,
  maximum_bytes: Int,
  signal: Dynamic,
  state_value: state.State,
  bundle: portable.Bundle,
) -> Promise(tool.ToolResult) {
  use outcome <- promise.await(portable_file.replace(
    path,
    "",
    replacement,
    maximum_bytes,
    signal,
  ))
  case outcome {
    portable_file.Replaced(bytes) ->
      portable_export_result(bundle, path, "stored", bytes)
    portable_file.StorageChanged(bytes) ->
      portable_conflict_result(
        "export",
        "destination_changed_after_read",
        state.revision(state_value),
        bytes,
      )
    portable_file.StorageBusy ->
      portable_conflict_result(
        "export",
        "exclusive_storage_lock_busy",
        state.revision(state_value),
        0,
      )
    portable_file.ReplaceCancelled ->
      tool.reject("Swing portable export cancelled")
    portable_file.ReplacementTooLarge(received, maximum) ->
      tool.reject(
        "Swing portable export exceeds byte bound received="
        <> string.inspect(received)
        <> " maximum="
        <> string.inspect(maximum),
      )
    portable_file.ReplaceFailure(code) ->
      tool.reject("Swing portable storage replace failed code=" <> code)
    portable_file.InvalidReplaceResult ->
      tool.reject("Swing portable storage returned an invalid replace result")
  }
}

fn portable_export_result(
  bundle: portable.Bundle,
  path: String,
  outcome: String,
  bytes: Int,
) -> Promise(tool.ToolResult) {
  tool.text_result(
    render.portable_result_text("export", outcome, path, bundle),
    render.portable_export_json(bundle, path, outcome, bytes),
  )
  |> promise.resolve
}

fn import_portable(
  api: pi.ExtensionApi,
  runtime: store.Store(Option(Result(state.State, String))),
  state_value: state.State,
  input: input_decode.PortableImportInput,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input_decode.PortableImportInput(
    path,
    expected_hash,
    expected_revision,
    maximum_bytes,
  ) = input
  use read_outcome <- promise.await(portable_file.read(
    path,
    maximum_bytes,
    signal,
  ))
  case read_outcome {
    portable_file.Missing ->
      tool.reject("Swing portable import source is missing")
    portable_file.Loaded(text, bytes) ->
      case portable.decode_bundle(text, expected_hash) {
        Error(error) ->
          tool.reject(
            "Swing portable import rejected mechanically: "
            <> string.inspect(error),
          )
        Ok(bundle) ->
          apply_portable_import(
            api,
            runtime,
            state_value,
            bundle,
            path,
            bytes,
            expected_revision,
          )
      }
    portable_file.ReadCancelled ->
      tool.reject("Swing portable import read cancelled")
    portable_file.ReadTooLarge(received, maximum) ->
      tool.reject(
        "Swing portable source exceeds byte bound received="
        <> string.inspect(received)
        <> " maximum="
        <> string.inspect(maximum),
      )
    portable_file.ReadFailure(code) ->
      tool.reject("Swing portable storage read failed code=" <> code)
    portable_file.InvalidReadResult ->
      tool.reject("Swing portable storage returned an invalid read result")
  }
}

fn apply_portable_import(
  api: pi.ExtensionApi,
  runtime: store.Store(Option(Result(state.State, String))),
  current_state: state.State,
  bundle: portable.Bundle,
  path: String,
  bytes: Int,
  expected_revision: Int,
) -> Promise(tool.ToolResult) {
  let events = portable.events(bundle)
  let exact_retry =
    state.canonical_event_log(state.workflows(current_state)) == events
  case exact_retry {
    True ->
      portable_import_result(
        bundle,
        current_state,
        path,
        "already_imported",
        bytes,
      )
    False ->
      case
        state.revision(current_state) == expected_revision,
        expected_revision == 0,
        state.workflows(current_state) == []
      {
        False, _, _ ->
          portable_conflict_result(
            "import",
            "expected_current_revision_mismatch",
            state.revision(current_state),
            bytes,
          )
        _, False, _ | _, _, False ->
          portable_conflict_result(
            "import",
            "target_branch_is_not_empty",
            state.revision(current_state),
            bytes,
          )
        True, True, True ->
          case state.replay(events) {
            Error(error) ->
              tool.reject(
                "Swing portable reconstruction failed: "
                <> string.inspect(error),
              )
            Ok(restored) -> {
              list.each(events, fn(value) { append_event(value, api) })
              store.write(runtime, Some(Ok(restored)))
              portable_import_result(bundle, restored, path, "imported", bytes)
            }
          }
      }
  }
}

fn portable_import_result(
  bundle: portable.Bundle,
  restored: state.State,
  path: String,
  outcome: String,
  bytes: Int,
) -> Promise(tool.ToolResult) {
  tool.text_result(
    render.portable_result_text("import", outcome, path, bundle),
    render.portable_import_json(bundle, restored, path, outcome, bytes),
  )
  |> promise.resolve
}

fn portable_conflict_result(
  operation: String,
  reason: String,
  revision: Int,
  bytes: Int,
) -> Promise(tool.ToolResult) {
  tool.text_result(
    "Swing portable storage conflict operation="
      <> operation
      <> " reason="
      <> reason
      <> " current_revision="
      <> string.inspect(revision),
    render.portable_conflict_json(operation, reason, revision, bytes),
  )
  |> promise.resolve
}

fn workflow_result(
  state_value: state.State,
  workflow_id: String,
  message: String,
) -> Promise(tool.ToolResult) {
  let assert Ok([workflow]) =
    state.selected_workflows(state_value, Some(workflow_id))
  tool.text_result(
    message
      <> " workflow="
      <> workflow_id
      <> " revision="
      <> string.inspect(state.revision(state_value)),
    render.workflow_json(workflow),
  )
  |> promise.resolve
}

fn persist_candidate(
  api: pi.ExtensionApi,
  runtime: store.Store(Option(Result(state.State, String))),
  next: state.State,
  snapshot: domain.CandidateSnapshot,
) -> Nil {
  state.event_for_candidate(next, snapshot)
  |> state.encode_event
  |> append_event(api)
  store.write(runtime, Some(Ok(next)))
}

fn persist_plan(
  api: pi.ExtensionApi,
  runtime: store.Store(Option(Result(state.State, String))),
  next: state.State,
  plan: domain.PlanRecord,
) -> Nil {
  state.event_for_plan(next, plan)
  |> state.encode_event
  |> append_event(api)
  store.write(runtime, Some(Ok(next)))
}

fn persist_review(
  api: pi.ExtensionApi,
  runtime: store.Store(Option(Result(state.State, String))),
  next: state.State,
  review: domain.ReviewRecord,
) -> Nil {
  state.event_for_review(next, review)
  |> state.encode_event
  |> append_event(api)
  store.write(runtime, Some(Ok(next)))
}

fn persist_journal_reference(
  api: pi.ExtensionApi,
  runtime: store.Store(Option(Result(state.State, String))),
  next: state.State,
  reference: domain.JournalEventReference,
) -> Nil {
  state.event_for_journal_reference(next, reference)
  |> state.encode_event
  |> append_event(api)
  store.write(runtime, Some(Ok(next)))
}

fn append_event(value: String, api: pi.ExtensionApi) -> Nil {
  pi.append_entry(api, event_entry_type, raw.dynamic(value))
}

fn restore(
  runtime: store.Store(Option(Result(state.State, String))),
  ctx: pi.Context,
) -> Nil {
  let restored =
    session.custom_entries(
      session.manager(ctx),
      event_entry_type,
      decode.string,
    )
  case restored {
    Error(_) ->
      lock(runtime, ctx, "Swing workflow entries could not be decoded")
    Ok(entries) ->
      case payloads(entries, []) {
        Error(message) -> lock(runtime, ctx, message)
        Ok(events) ->
          case state.replay(events) {
            Error(error) ->
              lock(
                runtime,
                ctx,
                "Swing workflow event replay failed: " <> string.inspect(error),
              )
            Ok(value) -> store.write(runtime, Some(Ok(value)))
          }
      }
  }
}

fn payloads(
  entries: List(session.CustomEntry(String)),
  reversed: List(String),
) -> Result(List(String), String) {
  case entries {
    [] -> Ok(list.reverse(reversed))
    [entry, ..rest] ->
      case entry.data {
        None -> Error("Swing workflow event entry has no payload")
        Some(value) -> payloads(rest, [value, ..reversed])
      }
  }
}

fn lock(
  runtime: store.Store(Option(Result(state.State, String))),
  ctx: pi.Context,
  message: String,
) -> Nil {
  store.write(runtime, Some(Error(message)))
  notify(
    ctx,
    message <> "; swing workflow mutation is disabled on this branch",
    ui.Error,
  )
}

fn current(
  runtime: store.Store(Option(Result(state.State, String))),
) -> Result(state.State, String) {
  case store.read(runtime) {
    None -> Error("Swing workflow state is not initialized for this session")
    Some(Error(message)) ->
      Error(message <> "; swing workflow mutation is disabled on this branch")
    Some(Ok(value)) -> Ok(value)
  }
}

fn reject_state(error: state.StateError) -> Promise(value) {
  tool.reject(
    "Swing workflow state transition rejected mechanically: "
    <> string.inspect(error),
  )
}

fn notify(ctx: pi.Context, message: String, kind: ui.Notification) -> Nil {
  case context.has_ui(ctx) {
    True -> ui.notify(context.ui(ctx), message, kind)
    False -> Nil
  }
}
