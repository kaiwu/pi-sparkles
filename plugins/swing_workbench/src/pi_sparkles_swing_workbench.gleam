import gleam/dynamic/decode
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
import pi_sparkles_swing_workbench/render
import pi_sparkles_swing_workbench/state

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
    "swing_snapshot",
    "Export swing workflow facts",
    "Return a deterministic versioned snapshot of all branch workflows or one exact workflow, including receipt payloads, changes, declarations, review facts, and neutral available operations",
    "This is session-branch state, not cross-session durable storage or a workflow verdict",
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

fn snapshot_schema() -> schema.Schema {
  schema.object([
    schema.Optional("workflowId", schema.nullable(bounded_string(1, 200))),
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
