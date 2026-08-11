import finance_thesis as thesis
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/option.{Some}
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_stock_thesis/input
import pi_sparkles_stock_thesis_local_file as local_file

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_append(api, "thesis_create", "Create immutable thesis", "created")
  register_append(api, "thesis_amend", "Amend immutable thesis", "amended")
  register_append(
    api,
    "thesis_withdraw",
    "Withdraw immutable thesis",
    "withdrawn",
  )
  tool.register(
    api,
    "thesis_inspect",
    "Inspect thesis version",
    "Replay an append-only thesis journal and inspect the latest or exact version with bounded history and explicit private-content inclusion",
    "Interpret claims and evidence yourself; the plugin validates only immutable mechanics and exact lineage",
    tool.parameters(inspect_schema(), input.inspect_decoder()),
    tool.Parallel,
    fn(_id, value, signal, _updates, _ctx) {
      inspect(value, raw.dynamic(signal))
    },
  )
  tool.register(
    api,
    "thesis_compare",
    "Compare thesis versions",
    "Replay an append-only thesis journal and return exact added, removed, and changed claim snapshots between two versions, with privacy redaction and content hashes",
    "Use the mechanical diff as review context; it is not a thesis-health or evidence-quality judgment",
    tool.parameters(compare_schema(), input.compare_decoder()),
    tool.Parallel,
    fn(_id, value, signal, _updates, _ctx) {
      compare(value, raw.dynamic(signal))
    },
  )
  tool.register(
    api,
    "thesis_export",
    "Export selected thesis events",
    "Return bounded canonical JSONL from an append-only thesis journal under explicit private, review-visible, and exportable inclusion flags; does not write a destination",
    "Select privacy classes explicitly and retain the returned content hash",
    tool.parameters(export_schema(), input.export_decoder()),
    tool.Parallel,
    fn(_id, value, signal, _updates, _ctx) {
      export(value, raw.dynamic(signal))
    },
  )
  promise.resolve(Nil)
}

fn register_append(
  api: pi.ExtensionApi,
  name: String,
  label: String,
  required_kind: String,
) -> Nil {
  tool.register(
    api,
    name,
    label,
    "Atomically append one complete caller-authored thesis snapshot to explicit local JSONL with compare-and-swap revision, immutable ancestry, idempotency, privacy, evidence correction lineage, deterministic replay, and content hash",
    "Supply every claim, evidence relation/state, author, time, horizon, privacy class, parent, and version; no claim or evidence judgment is inferred",
    tool.parameters(append_schema(), input.append_decoder()),
    tool.Sequential,
    fn(_id, value, signal, _updates, _ctx) {
      append(value, required_kind, raw.dynamic(signal))
    },
  )
}

fn append(
  value: input.AppendInput,
  required_kind: String,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input.AppendInput(path, expected_revision, maximum_bytes, draft) = value
  let thesis.Draft(_, thesis_id, _, kind, version, ..) = draft
  case kind == required_kind {
    False -> tool.reject("This thesis tool requires kind=" <> required_kind)
    True ->
      case thesis.new(draft) {
        Error(error) -> tool.reject(thesis.error_message(error))
        Ok(event) -> {
          use loaded <- promise.await(load(path, maximum_bytes, signal))
          case loaded {
            Error(message) -> tool.reject(message)
            Ok(#(original, state)) ->
              case thesis.append(state, event) {
                Error(error) -> tool.reject(thesis.error_message(error))
                Ok(#(same, thesis.AlreadyStored(stored))) ->
                  respond(same, thesis_id, version, stored, "already_stored")
                Ok(#(next, thesis.Stored(stored))) ->
                  case thesis.revision(state) == expected_revision {
                    False ->
                      tool.reject(
                        "Thesis append revision conflict; currentRevision="
                        <> int.to_string(thesis.revision(state)),
                      )
                    True -> {
                      use replaced <- promise.await(local_file.replace(
                        path,
                        original,
                        thesis.encode_state(next),
                        maximum_bytes,
                        signal,
                      ))
                      case replaced {
                        local_file.Replaced(_) ->
                          respond(next, thesis_id, version, stored, "stored")
                        local_file.Changed(bytes) ->
                          tool.reject(
                            "Thesis storage changed concurrently; current bytes="
                            <> int.to_string(bytes),
                          )
                        local_file.Busy ->
                          tool.reject(
                            "Thesis storage is busy; retry with a fresh revision",
                          )
                        local_file.CancelledReplace ->
                          tool.reject(
                            "Thesis storage replacement was cancelled",
                          )
                        local_file.TooLargeReplacement(bytes, maximum) ->
                          tool.reject(
                            "Thesis replacement exceeds maximumBytes: "
                            <> int.to_string(bytes)
                            <> "/"
                            <> int.to_string(maximum),
                          )
                        local_file.InvalidUtf8Current ->
                          tool.reject("Thesis storage changed to invalid UTF-8")
                        local_file.ReplaceFailure(code) ->
                          tool.reject(
                            "Thesis storage replacement failed safely: " <> code,
                          )
                        local_file.InvalidReplaceResult ->
                          tool.reject(
                            "Thesis storage replacement returned an invalid result",
                          )
                      }
                    }
                  }
              }
          }
        }
      }
  }
}

fn respond(
  state: thesis.State,
  thesis_id: String,
  version: Int,
  event: thesis.Event,
  status: String,
) -> Promise(tool.ToolResult) {
  case thesis.inspect(state, thesis_id, Some(version), False, True, 0) {
    Error(error) -> tool.reject(thesis.error_message(error))
    Ok(details) ->
      tool.text_result(
        "Thesis "
          <> status
          <> "; eventSha256="
          <> thesis.event_hash(event)
          <> "; journalRevision="
          <> int.to_string(thesis.revision(state)),
        details,
      )
      |> promise.resolve
  }
}

fn inspect(
  value: input.InspectInput,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input.InspectInput(
    path,
    maximum,
    thesis_id,
    version,
    history,
    private,
    max_history,
  ) = value
  use loaded <- promise.await(load(path, maximum, signal))
  case loaded {
    Error(message) -> tool.reject(message)
    Ok(#(_, state)) ->
      case
        thesis.inspect(state, thesis_id, version, history, private, max_history)
      {
        Error(error) -> tool.reject(thesis.error_message(error))
        Ok(details) ->
          tool.text_result(thesis.summary(state), details) |> promise.resolve
      }
  }
}

fn compare(
  value: input.CompareInput,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input.CompareInput(path, maximum, thesis_id, left, right, private) = value
  use loaded <- promise.await(load(path, maximum, signal))
  case loaded {
    Error(message) -> tool.reject(message)
    Ok(#(_, state)) ->
      case thesis.compare_versions(state, thesis_id, left, right, private) {
        Error(error) -> tool.reject(thesis.error_message(error))
        Ok(details) ->
          tool.text_result(
            "Exact thesis snapshot comparison "
              <> int.to_string(left)
              <> "→"
              <> int.to_string(right),
            details,
          )
          |> promise.resolve
      }
  }
}

fn export(
  value: input.ExportInput,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input.ExportInput(
    path,
    maximum_bytes,
    private,
    review,
    exportable,
    maximum_events,
  ) = value
  use loaded <- promise.await(load(path, maximum_bytes, signal))
  case loaded {
    Error(message) -> tool.reject(message)
    Ok(#(_, state)) ->
      case
        thesis.export_jsonl(state, private, review, exportable, maximum_events)
      {
        Error(error) -> tool.reject(thesis.error_message(error))
        Ok(details) ->
          tool.text_result(
            "Canonical bounded thesis JSONL export; no destination written",
            details,
          )
          |> promise.resolve
      }
  }
}

fn load(
  path: String,
  maximum: Int,
  signal: Dynamic,
) -> Promise(Result(#(String, thesis.State), String)) {
  use outcome <- promise.await(local_file.read(path, maximum, signal))
  case outcome {
    local_file.Missing -> promise.resolve(Ok(#("", thesis.empty())))
    local_file.Loaded(text, _) ->
      case thesis.decode_jsonl(text) {
        Ok(state) -> promise.resolve(Ok(#(text, state)))
        Error(error) -> promise.resolve(Error(thesis.error_message(error)))
      }
    local_file.Cancelled ->
      promise.resolve(Error("Thesis storage read was cancelled"))
    local_file.TooLarge(bytes, maximum) ->
      promise.resolve(Error(
        "Thesis storage exceeds maximumBytes: "
        <> int.to_string(bytes)
        <> "/"
        <> int.to_string(maximum),
      ))
    local_file.InvalidUtf8 ->
      promise.resolve(Error("Thesis storage requires strict UTF-8"))
    local_file.Failure(code) ->
      promise.resolve(Error("Thesis storage read failed safely: " <> code))
    local_file.InvalidResult ->
      promise.resolve(Error("Thesis storage read returned an invalid result"))
  }
}

fn append_schema() -> schema.Schema {
  schema.object([
    schema.Required("path", bounded_string(1, 4096)),
    schema.Required(
      "expectedRevision",
      schema.integer() |> schema.with_number_range(0.0, 10_000.0),
    ),
    schema.Required(
      "maximumBytes",
      schema.integer() |> schema.with_number_range(1.0, 10_000_000.0),
    ),
    schema.Required("journalId", bounded_string(1, 500)),
    schema.Required("thesisId", bounded_string(1, 500)),
    schema.Required("eventId", bounded_string(1, 500)),
    schema.Required(
      "kind",
      schema.string_enum(["created", "amended", "withdrawn"]),
    ),
    schema.Required(
      "version",
      schema.integer() |> schema.with_number_range(1.0, 10_000.0),
    ),
    schema.Optional("parentEventId", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "authorKind",
      schema.string_enum(["user", "llm", "imported"]),
    ),
    schema.Required("authorId", bounded_string(1, 500)),
    schema.Required("recordedAt", bounded_string(1, 100)),
    schema.Required("subject", subject_schema()),
    schema.Required("horizon", bounded_string(1, 500)),
    schema.Required(
      "claims",
      schema.array(claim_schema()) |> schema.with_array_length(0, 100),
    ),
    schema.Required(
      "privacy",
      schema.string_enum(["private", "review_visible", "exportable"]),
    ),
    schema.Optional("reason", schema.nullable(bounded_string(1, 2000))),
    schema.Required("idempotencyKey", bounded_string(1, 500)),
  ])
}

fn subject_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("issuerId", bounded_string(1, 500)),
    schema.Required("listingId", bounded_string(1, 500)),
    schema.Required(
      "mic",
      schema.string_enum(["XSHG", "XSHE", "XBSE", "XHKG", "XNYS", "XNAS"]),
    ),
    schema.Required("symbol", bounded_string(1, 100)),
  ])
}

fn claim_schema() -> schema.Schema {
  schema.object([
    schema.Required("claimId", bounded_string(1, 500)),
    schema.Required("text", bounded_string(1, 65_536)),
    schema.Required("state", schema.string_enum(["active", "withdrawn"])),
    schema.Required(
      "evidence",
      schema.array(evidence_schema()) |> schema.with_array_length(0, 100),
    ),
  ])
}

fn evidence_schema() -> schema.Schema {
  schema.object([
    schema.Required("linkId", bounded_string(1, 500)),
    schema.Required(
      "relation",
      schema.string_enum([
        "supporting",
        "contradicting",
        "contextual",
        "unresolved",
      ]),
    ),
    schema.Required("receiptSha256", bounded_string(64, 64)),
    schema.Required(
      "sourceState",
      schema.string_enum(["current", "stale", "retracted", "corrected"]),
    ),
    schema.Optional("correctedBy", schema.nullable(bounded_string(64, 64))),
  ])
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Required("path", bounded_string(1, 4096)),
    schema.Required(
      "maximumBytes",
      schema.integer() |> schema.with_number_range(1.0, 10_000_000.0),
    ),
    schema.Required("thesisId", bounded_string(1, 500)),
    schema.Optional(
      "version",
      schema.nullable(
        schema.integer() |> schema.with_number_range(1.0, 10_000.0),
      ),
    ),
    schema.Required("includeHistory", schema.boolean()),
    schema.Required("includePrivate", schema.boolean()),
    schema.Required(
      "maximumHistory",
      schema.integer() |> schema.with_number_range(0.0, 100.0),
    ),
  ])
}

fn compare_schema() -> schema.Schema {
  schema.object([
    schema.Required("path", bounded_string(1, 4096)),
    schema.Required(
      "maximumBytes",
      schema.integer() |> schema.with_number_range(1.0, 10_000_000.0),
    ),
    schema.Required("thesisId", bounded_string(1, 500)),
    schema.Required(
      "leftVersion",
      schema.integer() |> schema.with_number_range(1.0, 10_000.0),
    ),
    schema.Required(
      "rightVersion",
      schema.integer() |> schema.with_number_range(1.0, 10_000.0),
    ),
    schema.Required("includePrivate", schema.boolean()),
  ])
}

fn export_schema() -> schema.Schema {
  schema.object([
    schema.Required("path", bounded_string(1, 4096)),
    schema.Required(
      "maximumBytes",
      schema.integer() |> schema.with_number_range(1.0, 10_000_000.0),
    ),
    schema.Required("includePrivate", schema.boolean()),
    schema.Required("includeReviewVisible", schema.boolean()),
    schema.Required("includeExportable", schema.boolean()),
    schema.Required(
      "maximumEvents",
      schema.integer() |> schema.with_number_range(0.0, 10_000.0),
    ),
  ])
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}
