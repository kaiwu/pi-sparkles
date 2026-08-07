import finance_journal/comparison
import finance_journal/event
import finance_journal/metric
import finance_journal/receipt
import finance_journal/state
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string
import pi
import pi/context
import pi/raw
import pi/schema
import pi/tool
import pi/ui
import pi_sparkles_trade_journal/decode as input_decode
import pi_sparkles_trade_journal/domain
import pi_sparkles_trade_journal/render
import pi_sparkles_trade_journal_local_file as local_file

const default_command_maximum_bytes = 10_000_000

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  pi.register_command(
    api,
    "journal",
    "Show compact exact journal context from an explicit local JSONL path; payload prose and all decisions remain with the LLM",
    fn(args, ctx) {
      let path = string.trim(args)
      case path {
        "" -> {
          notify(ctx, "Usage: /journal <local-jsonl-path>", ui.Error)
          promise.resolve(Nil)
        }
        _ -> {
          use outcome <- promise.await(local_file.read(
            path,
            default_command_maximum_bytes,
            raw.dynamic(Nil),
          ))
          case load(outcome, default_command_maximum_bytes) {
            Error(message) -> notify(ctx, message, ui.Error)
            Ok(#(_, _, value)) ->
              notify(ctx, render.compact_text(value), ui.Info)
          }
          promise.resolve(Nil)
        }
      }
    },
  )

  tool.register(
    api,
    "journal_entry",
    "Append exact journal event",
    "Atomically append one attributed immutable journal event to explicit local JSONL storage; returns exact hashes, storage facts, unknowns, and neutral operations without interpreting the payload",
    "Supply an exact user/LLM declaration, observation reference, checklist response, review conclusion, correction, redaction, or marker; the LLM owns every interpretation and next operation",
    tool.parameters(entry_schema(), input_decode.entry_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      append_entry(input, raw.dynamic(signal))
    },
  )

  tool.register(
    api,
    "trade_review",
    "Append exact trade review",
    "Append a review_conclusion journal event using the same exact attributed event contract; no process, psychology, outcome, or trade judgment is produced",
    "Set eventKind to review_conclusion and preserve the exact supplied attribution and source references",
    tool.parameters(entry_schema(), input_decode.entry_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      let input_decode.EntryInput(_, _, _, entry) = input
      let domain.EntryData(_, _, kind, ..) = entry
      case kind {
        "review_conclusion" -> append_entry(input, raw.dynamic(signal))
        _ -> tool.reject("trade_review requires eventKind=review_conclusion")
      }
    },
  )

  tool.register(
    api,
    "journal_search",
    "Query journal information",
    "Query exact event metadata and caller-selected payloads with explicit filters and bounds; private payloads are omitted unless explicitly requested",
    "Use the returned event handles and facts as information for LLM review; the plugin does not rank, summarize, diagnose, or decide",
    tool.parameters(search_schema(), input_decode.search_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      search(input, raw.dynamic(signal))
    },
  )

  tool.register(
    api,
    "journal_context",
    "Load compact journal context",
    "Return content-bound counts, omission counts, event handles, and neutral operations without including journal prose or making any decision",
    "Use before drilling into exact events after interruption or compaction",
    tool.parameters(context_schema(), input_decode.context_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      compact_context(input, raw.dynamic(signal))
    },
  )

  tool.register(
    api,
    "journal_export",
    "Export caller-selected journal events",
    "Return canonical JSONL under explicit privacy, supersession, event, and byte bounds; no destination is written and no export policy is selected by the plugin",
    "Choose every included privacy class explicitly and preserve the returned content hash",
    tool.parameters(export_schema(), input_decode.export_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      export(input, raw.dynamic(signal))
    },
  )

  tool.register(
    api,
    "journal_import",
    "Import canonical journal JSONL",
    "Atomically import a bounded canonical JSONL batch into explicit local storage, preserving attribution, IDs, hashes, privacy, and correction lineage",
    "The plugin reports stored, already-stored, conflict, and storage facts; it does not resolve conflicts or reinterpret imported content",
    tool.parameters(import_schema(), input_decode.import_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      import_jsonl(input, raw.dynamic(signal))
    },
  )

  tool.register(
    api,
    "journal_compare",
    "Calculate requested plan/observation differences",
    "Calculate only the exact equality or decimal deltas explicitly supplied by the caller, retaining every unknown, conflict, policy string, input, unit, and receipt",
    "The calculation does not judge adherence, process, outcome, setup quality, or the next operation",
    tool.parameters(comparison_schema(), input_decode.comparison_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) { calculate_comparison(input) },
  )

  tool.register(
    api,
    "journal_stats",
    "Calculate requested realized net P&L",
    "Calculate long-cash realized net P&L v1 from exact caller-supplied entry/exit fill and cost lexemes; preserves every component and source receipt and emits no performance judgment",
    "Select the inputs, currency, scale, and rounding explicitly; the LLM owns all interpretation",
    tool.parameters(metric_schema(), input_decode.metric_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) { calculate_metric(input) },
  )

  promise.resolve(Nil)
}

fn calculate_comparison(
  input: input_decode.ComparisonInput,
) -> Promise(tool.ToolResult) {
  let input_decode.ComparisonInput(
    instruction,
    plan,
    observations,
    missing_policy,
    conflict_policy,
    fields,
  ) = input
  case
    comparison.compare(
      instruction,
      plan,
      observations,
      missing_policy,
      conflict_policy,
      fields,
    )
  {
    Error(error) ->
      tool.reject(
        "Journal comparison rejected mechanically: " <> string.inspect(error),
      )
    Ok(value) -> {
      let envelope = comparison.receipt(value)
      tool.text_result(
        "Requested journal comparison calculated fields="
          <> string.inspect(list.length(fields))
          <> "; decision owner=LLM",
        receipt.as_json(envelope),
      )
      |> promise.resolve
    }
  }
}

fn calculate_metric(
  input: input_decode.MetricInput,
) -> Promise(tool.ToolResult) {
  let input_decode.MetricInput(
    instruction,
    currency,
    scale,
    rounding,
    fills,
    costs,
  ) = input
  case
    metric.long_cash_realized_net_pnl(
      instruction,
      currency,
      scale,
      rounding,
      fills,
      costs,
    )
  {
    Error(error) ->
      tool.reject(
        "Journal metric rejected mechanically: " <> string.inspect(error),
      )
    Ok(value) -> {
      let envelope = metric.receipt(value)
      tool.text_result(
        "Requested long-cash realized net P&L calculated; decision owner=LLM",
        receipt.as_json(envelope),
      )
      |> promise.resolve
    }
  }
}

fn append_entry(
  input: input_decode.EntryInput,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input_decode.EntryInput(path, expected_revision, maximum_bytes, data) =
    input
  case domain.build_event(data) {
    Error(error) ->
      tool.reject(
        "Journal event rejected mechanically: " <> string.inspect(error),
      )
    Ok(new_event) -> {
      use read_outcome <- promise.await(local_file.read(
        path,
        maximum_bytes,
        signal,
      ))
      case load(read_outcome, maximum_bytes) {
        Error(message) -> tool.reject(message)
        Ok(#(original_text, original_bytes, value)) ->
          case state.append(value, new_event) {
            Error(error) ->
              tool.reject(
                "Journal append rejected mechanically: "
                <> string.inspect(error),
              )
            Ok(#(same, state.AlreadyStored(stored))) ->
              tool.text_result(
                render.stored_text(same, stored, "already_stored"),
                render.stored_json(
                  same,
                  stored,
                  "already_stored",
                  original_bytes,
                  path,
                ),
              )
              |> promise.resolve
            Ok(#(next, state.Stored(stored))) ->
              case state.revision(value) == expected_revision {
                False ->
                  conflict_result(
                    "append",
                    "expected_revision_mismatch",
                    state.revision(value),
                    original_bytes,
                  )
                True ->
                  persist_append(
                    path,
                    original_text,
                    state.encode_jsonl(state.events(next)),
                    maximum_bytes,
                    signal,
                    next,
                    stored,
                  )
              }
          }
      }
    }
  }
}

fn persist_append(
  path: String,
  original_text: String,
  next_text: String,
  maximum_bytes: Int,
  signal: Dynamic,
  next: state.State,
  stored: event.Event,
) -> Promise(tool.ToolResult) {
  use outcome <- promise.await(local_file.replace(
    path,
    original_text,
    next_text,
    maximum_bytes,
    signal,
  ))
  case outcome {
    local_file.Replaced(bytes) ->
      tool.text_result(
        render.stored_text(next, stored, "stored"),
        render.stored_json(next, stored, "stored", bytes, path),
      )
      |> promise.resolve
    local_file.StorageChanged(bytes) ->
      conflict_result(
        "append",
        "storage_changed_after_read",
        state.revision(next) - 1,
        bytes,
      )
    local_file.StorageBusy ->
      conflict_result(
        "append",
        "exclusive_storage_lock_busy",
        state.revision(next) - 1,
        0,
      )
    local_file.ReplaceCancelled -> tool.reject("Journal append cancelled")
    local_file.ReplacementTooLarge(received, maximum) ->
      tool.reject(
        "Journal replacement exceeds byte bound received="
        <> string.inspect(received)
        <> " maximum="
        <> string.inspect(maximum),
      )
    local_file.ReplaceFailure(code) ->
      tool.reject("Journal storage replace failed code=" <> code)
    local_file.InvalidReplaceResult ->
      tool.reject("Journal storage returned an invalid replace result")
  }
}

fn search(
  input: input_decode.SearchInput,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input_decode.SearchInput(
    path,
    journal_id,
    workflow_id,
    kinds,
    attributions,
    privacy,
    include_superseded,
    include_private,
    maximum_events,
    maximum_bytes,
  ) = input
  use read_outcome <- promise.await(local_file.read(path, maximum_bytes, signal))
  case load_checked(read_outcome, maximum_bytes, journal_id) {
    Error(message) -> tool.reject(message)
    Ok(#(_, _, value)) -> {
      let result =
        state.query(
          value,
          state.Query(
            workflow_id,
            kinds,
            attributions,
            privacy,
            include_superseded,
            maximum_events,
          ),
        )
      tool.text_result(
        render.search_text(value, result, include_private),
        render.search_json(value, result, include_private),
      )
      |> promise.resolve
    }
  }
}

fn compact_context(
  input: input_decode.ContextInput,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input_decode.ContextInput(
    path,
    journal_id,
    include_superseded,
    maximum_bytes,
  ) = input
  use read_outcome <- promise.await(local_file.read(path, maximum_bytes, signal))
  case load_checked(read_outcome, maximum_bytes, journal_id) {
    Error(message) -> tool.reject(message)
    Ok(#(_, _, value)) ->
      tool.text_result(
        render.compact_text(value),
        render.context_json(value, include_superseded),
      )
      |> promise.resolve
  }
}

fn export(
  input: input_decode.ExportInput,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input_decode.ExportInput(
    path,
    journal_id,
    include_private,
    include_review,
    include_exportable,
    include_superseded,
    maximum_events,
    maximum_bytes,
  ) = input
  use read_outcome <- promise.await(local_file.read(path, maximum_bytes, signal))
  case load_checked(read_outcome, maximum_bytes, journal_id) {
    Error(message) -> tool.reject(message)
    Ok(#(_, _, value)) -> {
      let exported =
        state.export_jsonl(
          value,
          state.ExportPolicy(
            include_private,
            include_review,
            include_exportable,
            include_superseded,
          ),
          maximum_events,
        )
      tool.text_result(
        "Journal JSONL export events="
          <> string.inspect(state.exported_count(exported))
          <> " omitted="
          <> string.inspect(state.export_omitted_count(exported)),
        render.export_json(value, exported, path),
      )
      |> promise.resolve
    }
  }
}

fn import_jsonl(
  input: input_decode.ImportInput,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  let input_decode.ImportInput(
    path,
    expected_revision,
    jsonl,
    maximum_import_events,
    maximum_bytes,
  ) = input
  case state.decode_jsonl(jsonl, maximum_import_events, maximum_bytes) {
    Error(error) ->
      tool.reject(
        "Journal import JSONL rejected mechanically: " <> string.inspect(error),
      )
    Ok(imported) -> {
      use read_outcome <- promise.await(local_file.read(
        path,
        maximum_bytes,
        signal,
      ))
      case load(read_outcome, maximum_bytes) {
        Error(message) -> tool.reject(message)
        Ok(#(original_text, original_bytes, current)) ->
          case state.append_many(current, state.events(imported)) {
            Error(error) ->
              tool.reject(
                "Journal import rejected mechanically: "
                <> string.inspect(error),
              )
            Ok(#(next, outcomes)) -> {
              let changed =
                list.any(outcomes, fn(outcome) {
                  case outcome {
                    state.Stored(_) -> True
                    state.AlreadyStored(_) -> False
                  }
                })
              case changed, state.revision(current) == expected_revision {
                False, _ ->
                  tool.text_result(
                    "Journal import events already stored revision="
                      <> string.inspect(state.revision(current)),
                    render.import_json(current, outcomes, original_bytes, path),
                  )
                  |> promise.resolve
                True, False ->
                  conflict_result(
                    "import",
                    "expected_revision_mismatch",
                    state.revision(current),
                    original_bytes,
                  )
                True, True ->
                  persist_import(
                    path,
                    original_text,
                    state.encode_jsonl(state.events(next)),
                    maximum_bytes,
                    signal,
                    next,
                    outcomes,
                  )
              }
            }
          }
      }
    }
  }
}

fn persist_import(
  path: String,
  original_text: String,
  next_text: String,
  maximum_bytes: Int,
  signal: Dynamic,
  next: state.State,
  outcomes: List(state.AppendOutcome),
) -> Promise(tool.ToolResult) {
  use outcome <- promise.await(local_file.replace(
    path,
    original_text,
    next_text,
    maximum_bytes,
    signal,
  ))
  case outcome {
    local_file.Replaced(bytes) ->
      tool.text_result(
        "Journal JSONL import committed events="
          <> string.inspect(list.length(outcomes))
          <> " revision="
          <> string.inspect(state.revision(next)),
        render.import_json(next, outcomes, bytes, path),
      )
      |> promise.resolve
    local_file.StorageChanged(bytes) ->
      conflict_result(
        "import",
        "storage_changed_after_read",
        state.revision(next) - count_stored(outcomes),
        bytes,
      )
    local_file.StorageBusy ->
      conflict_result(
        "import",
        "exclusive_storage_lock_busy",
        state.revision(next) - count_stored(outcomes),
        0,
      )
    local_file.ReplaceCancelled -> tool.reject("Journal import cancelled")
    local_file.ReplacementTooLarge(received, maximum) ->
      tool.reject(
        "Journal replacement exceeds byte bound received="
        <> string.inspect(received)
        <> " maximum="
        <> string.inspect(maximum),
      )
    local_file.ReplaceFailure(code) ->
      tool.reject("Journal storage replace failed code=" <> code)
    local_file.InvalidReplaceResult ->
      tool.reject("Journal storage returned an invalid replace result")
  }
}

fn load(
  outcome: local_file.ReadOutcome,
  maximum_bytes: Int,
) -> Result(#(String, Int, state.State), String) {
  case outcome {
    local_file.Missing -> Ok(#("", 0, state.empty()))
    local_file.Loaded(text, bytes) ->
      case state.decode_jsonl(text, state.maximum_revision, maximum_bytes) {
        Ok(value) -> Ok(#(text, bytes, value))
        Error(error) ->
          Error(
            "Local journal JSONL could not be replayed: "
            <> string.inspect(error),
          )
      }
    local_file.ReadCancelled -> Error("Journal read cancelled")
    local_file.ReadTooLarge(received, maximum) ->
      Error(
        "Journal file exceeds byte bound received="
        <> string.inspect(received)
        <> " maximum="
        <> string.inspect(maximum),
      )
    local_file.ReadFailure(code) ->
      Error("Journal storage read failed code=" <> code)
    local_file.InvalidReadResult ->
      Error("Journal storage returned an invalid read result")
  }
}

fn load_checked(
  outcome: local_file.ReadOutcome,
  maximum_bytes: Int,
  expected_journal_id: Option(String),
) -> Result(#(String, Int, state.State), String) {
  case load(outcome, maximum_bytes) {
    Error(message) -> Error(message)
    Ok(#(text, bytes, value)) ->
      case expected_journal_id, state.journal_id(value) {
        Some(expected), Some(actual) if expected != actual ->
          Error(
            "Journal identity mismatch expected="
            <> expected
            <> " received="
            <> actual,
          )
        _, _ -> Ok(#(text, bytes, value))
      }
  }
}

fn conflict_result(
  operation: String,
  reason: String,
  revision: Int,
  bytes: Int,
) -> Promise(tool.ToolResult) {
  tool.text_result(
    "Journal storage conflict operation="
      <> operation
      <> " reason="
      <> reason
      <> " loaded_revision="
      <> string.inspect(revision),
    render.conflict_json(operation, reason, revision, bytes),
  )
  |> promise.resolve
}

fn count_stored(values: List(state.AppendOutcome)) -> Int {
  values
  |> list.filter(fn(value) {
    case value {
      state.Stored(_) -> True
      state.AlreadyStored(_) -> False
    }
  })
  |> list.length
}

fn entry_schema() -> schema.Schema {
  schema.object([
    schema.Required("journalPath", bounded_string(1, 4096)),
    schema.Required("expectedRevision", bounded_integer(0, 100_000)),
    schema.Required("maximumJournalBytes", bounded_integer(1, 100_000_000)),
    schema.Required("journalId", bounded_string(1, 200)),
    schema.Required("eventId", bounded_string(1, 200)),
    schema.Required(
      "eventKind",
      schema.string_enum([
        "declaration",
        "observation_reference",
        "checklist_response",
        "review_conclusion",
        "correction",
        "redaction",
        "import_marker",
        "export_marker",
      ]),
    ),
    schema.Required(
      "identityScope",
      schema.string_enum([
        "journal_wide",
        "track_wide",
        "exact_listing",
        "unresolved_listing",
      ]),
    ),
    optional_nullable("track", schema.string_enum(["cn", "hk", "us"])),
    optional_nullable("listingId", bounded_string(1, 200)),
    optional_nullable("mic", bounded_string(1, 200)),
    optional_nullable("symbol", bounded_string(1, 200)),
    optional_nullable("workflowId", bounded_string(1, 200)),
    optional_nullable("positionId", bounded_string(1, 200)),
    optional_nullable("reviewId", bounded_string(1, 200)),
    schema.Required(
      "attributionKind",
      schema.string_enum([
        "user_declared",
        "llm_declared",
        "imported_declaration",
        "provider_observed",
        "broker_reported",
        "system_observed",
        "calculated",
      ]),
    ),
    optional_nullable("authorOrSourceId", bounded_string(1, 200)),
    optional_nullable("attributionReceipt", hash_schema()),
    optional_nullable("resultReceipt", hash_schema()),
    optional_nullable("contextReceipt", hash_schema()),
    optional_nullable("stage", bounded_string(1, 200)),
    schema.Required("payload", bounded_string(1, 65_536)),
    optional_nullable("occurrenceTimeUnixMs", schema.integer()),
    schema.Required("recordingTimeUnixMs", schema.integer()),
    optional_nullable("timezone", bounded_string(1, 200)),
    schema.Required(
      "privacy",
      schema.string_enum(["private", "review_visible", "exportable"]),
    ),
    schema.Required(
      "references",
      schema.array(reference_schema()) |> schema.with_array_length(0, 64),
    ),
    optional_nullable("supersedes", bounded_string(1, 200)),
    optional_nullable("importProvenance", bounded_string(1, 2000)),
    schema.Required("idempotencyKey", bounded_string(1, 200)),
  ])
}

fn search_schema() -> schema.Schema {
  schema.object([
    schema.Required("journalPath", bounded_string(1, 4096)),
    optional_nullable("journalId", bounded_string(1, 200)),
    optional_nullable("workflowId", bounded_string(1, 200)),
    schema.Required(
      "eventKinds",
      schema.array(
        schema.string_enum([
          "declaration",
          "observation_reference",
          "checklist_response",
          "review_conclusion",
          "correction",
          "redaction",
          "import_marker",
          "export_marker",
        ]),
      )
        |> schema.with_array_length(0, 8),
    ),
    schema.Required(
      "attributionKinds",
      schema.array(
        schema.string_enum([
          "user_declared",
          "llm_declared",
          "imported_declaration",
          "provider_observed",
          "broker_reported",
          "system_observed",
          "calculated",
        ]),
      )
        |> schema.with_array_length(0, 7),
    ),
    schema.Required(
      "privacyClassifications",
      schema.array(
        schema.string_enum([
          "private",
          "review_visible",
          "exportable",
        ]),
      )
        |> schema.with_array_length(0, 3),
    ),
    schema.Required("includeSuperseded", schema.boolean()),
    schema.Required("includePrivatePayloads", schema.boolean()),
    schema.Required("maximumEvents", bounded_integer(1, 1000)),
    schema.Required("maximumJournalBytes", bounded_integer(1, 100_000_000)),
  ])
}

fn context_schema() -> schema.Schema {
  schema.object([
    schema.Required("journalPath", bounded_string(1, 4096)),
    optional_nullable("journalId", bounded_string(1, 200)),
    schema.Required("includeSuperseded", schema.boolean()),
    schema.Required("maximumJournalBytes", bounded_integer(1, 100_000_000)),
  ])
}

fn export_schema() -> schema.Schema {
  schema.object([
    schema.Required("journalPath", bounded_string(1, 4096)),
    optional_nullable("journalId", bounded_string(1, 200)),
    schema.Required("includePrivate", schema.boolean()),
    schema.Required("includeReviewVisible", schema.boolean()),
    schema.Required("includeExportable", schema.boolean()),
    schema.Required("includeSuperseded", schema.boolean()),
    schema.Required("maximumEvents", bounded_integer(1, 50_000)),
    schema.Required("maximumJournalBytes", bounded_integer(1, 100_000_000)),
  ])
}

fn import_schema() -> schema.Schema {
  schema.object([
    schema.Required("journalPath", bounded_string(1, 4096)),
    schema.Required("expectedRevision", bounded_integer(0, 100_000)),
    schema.Required("jsonl", bounded_string(0, 100_000_000)),
    schema.Required("maximumImportEvents", bounded_integer(1, 10_000)),
    schema.Required("maximumJournalBytes", bounded_integer(1, 100_000_000)),
  ])
}

fn comparison_schema() -> schema.Schema {
  schema.object([
    schema.Required("instructionReceipt", hash_schema()),
    schema.Required("planReceipt", hash_schema()),
    schema.Required(
      "observationReceipts",
      schema.array(hash_schema()) |> schema.with_array_length(0, 64),
    ),
    schema.Required("missingPolicy", bounded_string(1, 200)),
    schema.Required("conflictPolicy", bounded_string(1, 200)),
    schema.Required(
      "fields",
      schema.array(comparison_field_schema())
        |> schema.with_array_length(1, 100),
    ),
  ])
}

fn comparison_field_schema() -> schema.Schema {
  schema.object([
    schema.Required("field", bounded_string(1, 200)),
    schema.Required("planned", information_schema()),
    schema.Required("observed", information_schema()),
    schema.Required("mode", comparison_mode_schema()),
    schema.Required("unit", bounded_string(1, 200)),
  ])
}

fn information_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum([
        "known",
        "unknown",
        "not_asked",
        "not_obtained",
        "declined",
        "not_applicable",
        "conflicting",
        "decode_failure",
        "redacted",
        "superseded",
      ]),
    ),
    optional_nullable("value", bounded_string(1, 20_000)),
    optional_nullable("reason", bounded_string(1, 2000)),
    schema.Optional(
      "alternatives",
      schema.array(bounded_string(1, 20_000))
        |> schema.with_array_length(0, 100),
    ),
    optional_nullable("raw", bounded_string(0, 20_000)),
  ])
}

fn comparison_mode_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum(["exact_equality", "decimal_delta"]),
    ),
    schema.Optional("scale", schema.nullable(bounded_integer(0, 18))),
    schema.Optional("rounding", schema.nullable(rounding_schema())),
  ])
}

fn metric_schema() -> schema.Schema {
  schema.object([
    schema.Required("instructionReceipt", hash_schema()),
    schema.Required("currency", bounded_string(1, 32)),
    schema.Required("scale", bounded_integer(0, 18)),
    schema.Required("rounding", rounding_schema()),
    schema.Required(
      "fills",
      schema.array(fill_schema()) |> schema.with_array_length(1, 1000),
    ),
    schema.Required(
      "costs",
      schema.array(cost_schema()) |> schema.with_array_length(0, 1000),
    ),
  ])
}

fn fill_schema() -> schema.Schema {
  schema.object([
    schema.Required("fillId", bounded_string(1, 200)),
    schema.Required("role", schema.string_enum(["entry", "exit"])),
    schema.Required("quantityLexeme", bounded_string(1, 200)),
    schema.Required("priceLexeme", bounded_string(1, 200)),
    schema.Required("sourceReceipt", hash_schema()),
  ])
}

fn cost_schema() -> schema.Schema {
  schema.object([
    schema.Required("costId", bounded_string(1, 200)),
    schema.Required("amountLexeme", bounded_string(1, 200)),
    schema.Required("sourceReceipt", hash_schema()),
  ])
}

fn rounding_schema() -> schema.Schema {
  schema.string_enum([
    "toward_zero",
    "away_from_zero",
    "half_up",
    "half_even",
  ])
}

fn reference_schema() -> schema.Schema {
  schema.object([
    schema.Required("kind", bounded_string(1, 200)),
    schema.Required("hash", hash_schema()),
  ])
}

fn optional_nullable(name: String, value: schema.Schema) -> schema.Property {
  schema.Optional(name, schema.nullable(value))
}

fn hash_schema() -> schema.Schema {
  bounded_string(64, 64)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Int, maximum: Int) -> schema.Schema {
  schema.integer()
  |> schema.with_number_range(int.to_float(minimum), int.to_float(maximum))
}

fn notify(ctx: pi.Context, message: String, kind: ui.Notification) -> Nil {
  case context.has_ui(ctx) {
    True -> ui.notify(context.ui(ctx), message, kind)
    False -> Nil
  }
}
