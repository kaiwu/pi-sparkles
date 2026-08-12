import finance_local_import
import finance_local_state
import finance_portfolio_review/review
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import pi
import pi/raw
import pi/schema
import pi/tool

pub type RecordInput {
  RecordInput(
    journal_path: String,
    maximum_journal_bytes: Int,
    expected_revision: Int,
    event_id: String,
    idempotency_key: String,
    packet_path: String,
    expected_sha256: String,
    maximum_packet_bytes: Int,
  )
}

pub type InspectInput {
  InspectInput(
    journal_path: String,
    maximum_journal_bytes: Int,
    review_id: String,
    include_private: Bool,
    maximum_history: Int,
  )
}

pub fn register(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "portfolio_review_record",
    "Record immutable portfolio review receipt",
    "Atomically append one content-bound portfolio review linking the exact imported snapshot and optional risk, attribution, scenario, rebalance, tax-lot and conclusion receipts with prior-review and correction lineage",
    "Every linked calculation and conclusion is supplied by receipt; the portfolio plugin stores no recommendation and never mutates holdings, broker state, orders, or source files",
    tool.parameters(record_schema(), record_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      record(input, raw.dynamic(signal))
    },
  )
  tool.register(
    api,
    "portfolio_review_inspect",
    "Inspect durable portfolio review",
    "Replay one bounded user-owned append-only review journal and return an exact immutable review, receipt inventory, correction lineage and bounded history with privacy filtering",
    "Inspection does not import a portfolio again, rerun calculations, infer conclusions, or change state",
    tool.parameters(inspect_schema(), inspect_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      inspect(input, raw.dynamic(signal))
    },
  )
}

fn record(input: RecordInput, signal: Dynamic) -> Promise(tool.ToolResult) {
  use packet <- promise.await(finance_local_import.read(
    input.packet_path,
    input.maximum_packet_bytes,
    signal,
  ))
  case packet {
    finance_local_import.Loaded(text, _) -> {
      use loaded <- promise.await(load(
        input.journal_path,
        input.maximum_journal_bytes,
        signal,
      ))
      case loaded {
        Error(message) -> tool.reject(message)
        Ok(#(original, state)) ->
          case
            review.append(
              state,
              input.expected_revision,
              input.event_id,
              input.idempotency_key,
              text,
              input.expected_sha256,
            )
          {
            Error(error) -> tool.reject(review.error_message(error))
            Ok(#(next, review.AlreadyStored(event_id), details)) ->
              tool.text_result(
                "Portfolio review already stored eventId="
                  <> event_id
                  <> " journalRevision="
                  <> int.to_string(review.revision(next)),
                details,
              )
              |> promise.resolve
            Ok(#(next, review.Stored(event_id), details)) -> {
              use replaced <- promise.await(finance_local_state.replace(
                input.journal_path,
                original,
                review.encode_state(next),
                input.maximum_journal_bytes,
                signal,
              ))
              finish_replace(replaced, next, event_id, details)
            }
          }
      }
    }
    finance_local_import.Truncated(_, total) ->
      tool.reject(
        "Portfolio review packet exceeds maximumPacketBytes: "
        <> int.to_string(total),
      )
    finance_local_import.Cancelled ->
      tool.reject("Portfolio review packet read was cancelled")
    finance_local_import.Missing ->
      tool.reject("Portfolio review packet was not found")
    finance_local_import.InvalidUtf8 ->
      tool.reject("Portfolio review packet requires strict UTF-8")
    finance_local_import.Failure(code) ->
      tool.reject("Portfolio review packet read failed safely: " <> code)
    finance_local_import.InvalidResult ->
      tool.reject("Portfolio review packet read returned an invalid result")
  }
}

fn finish_replace(
  outcome: finance_local_state.ReplaceOutcome,
  state: review.State,
  event_id: String,
  details: json.Json,
) -> Promise(tool.ToolResult) {
  case outcome {
    finance_local_state.Replaced(_) ->
      tool.text_result(
        "Portfolio review stored eventId="
          <> event_id
          <> " journalRevision="
          <> int.to_string(review.revision(state)),
        details,
      )
      |> promise.resolve
    finance_local_state.Changed(bytes) ->
      tool.reject(
        "Portfolio review journal changed concurrently; current bytes="
        <> int.to_string(bytes),
      )
    finance_local_state.Busy ->
      tool.reject(
        "Portfolio review journal is busy; reload and retry with a fresh revision",
      )
    finance_local_state.CancelledReplace ->
      tool.reject("Portfolio review journal replacement was cancelled")
    finance_local_state.TooLargeReplacement(bytes, maximum) ->
      tool.reject(
        "Portfolio review journal replacement exceeds maximumJournalBytes: "
        <> int.to_string(bytes)
        <> "/"
        <> int.to_string(maximum),
      )
    finance_local_state.InvalidUtf8Current ->
      tool.reject("Portfolio review journal changed to invalid UTF-8")
    finance_local_state.ReplaceFailure(code) ->
      tool.reject(
        "Portfolio review journal replacement failed safely: " <> code,
      )
    finance_local_state.InvalidReplaceResult ->
      tool.reject(
        "Portfolio review journal replacement returned an invalid result",
      )
  }
}

fn inspect(input: InspectInput, signal: Dynamic) -> Promise(tool.ToolResult) {
  use loaded <- promise.await(load(
    input.journal_path,
    input.maximum_journal_bytes,
    signal,
  ))
  case loaded {
    Error(message) -> tool.reject(message)
    Ok(#(_, state)) ->
      case
        review.inspect(
          state,
          input.review_id,
          input.include_private,
          input.maximum_history,
        )
      {
        Error(error) -> tool.reject(review.error_message(error))
        Ok(details) ->
          tool.text_result(
            "Durable portfolio review "
              <> input.review_id
              <> " journalRevision="
              <> int.to_string(review.revision(state)),
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
) -> Promise(Result(#(String, review.State), String)) {
  use outcome <- promise.await(finance_local_state.read(path, maximum, signal))
  case outcome {
    finance_local_state.Missing -> promise.resolve(Ok(#("", review.empty())))
    finance_local_state.Loaded(text, _) ->
      case review.decode_jsonl(text) {
        Ok(state) -> promise.resolve(Ok(#(text, state)))
        Error(error) -> promise.resolve(Error(review.error_message(error)))
      }
    finance_local_state.Cancelled ->
      promise.resolve(Error("Portfolio review journal read was cancelled"))
    finance_local_state.TooLarge(bytes, limit) ->
      promise.resolve(Error(
        "Portfolio review journal exceeds maximumJournalBytes: "
        <> int.to_string(bytes)
        <> "/"
        <> int.to_string(limit),
      ))
    finance_local_state.InvalidUtf8 ->
      promise.resolve(Error("Portfolio review journal requires strict UTF-8"))
    finance_local_state.Failure(code) ->
      promise.resolve(Error(
        "Portfolio review journal read failed safely: " <> code,
      ))
    finance_local_state.InvalidResult ->
      promise.resolve(Error(
        "Portfolio review journal read returned an invalid result",
      ))
  }
}

fn record_schema() -> schema.Schema {
  schema.object([
    schema.Required("journalPath", bounded_string(1, 4096)),
    schema.Required("maximumJournalBytes", bounded_integer(1, 10_000_000)),
    schema.Required("expectedRevision", bounded_integer(0, 10_000)),
    schema.Required("eventId", bounded_string(1, 500)),
    schema.Required("idempotencyKey", bounded_string(1, 500)),
    schema.Required("packetPath", bounded_string(1, 4096)),
    schema.Required("expectedSha256", bounded_string(64, 64)),
    schema.Required("maximumPacketBytes", bounded_integer(1, 5_000_000)),
  ])
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Required("journalPath", bounded_string(1, 4096)),
    schema.Required("maximumJournalBytes", bounded_integer(1, 10_000_000)),
    schema.Required("reviewId", bounded_string(1, 500)),
    schema.Required("includePrivate", schema.boolean()),
    schema.Required("maximumHistory", bounded_integer(0, 10_000)),
  ])
}

fn record_decoder() -> decode.Decoder(RecordInput) {
  use path <- decode.field("journalPath", decode.string)
  use maximum <- decode.field("maximumJournalBytes", decode.int)
  use expected <- decode.field("expectedRevision", decode.int)
  use event_id <- decode.field("eventId", decode.string)
  use idempotency <- decode.field("idempotencyKey", decode.string)
  use packet_path <- decode.field("packetPath", decode.string)
  use digest <- decode.field("expectedSha256", decode.string)
  use packet_maximum <- decode.field("maximumPacketBytes", decode.int)
  decode.success(RecordInput(
    path,
    maximum,
    expected,
    event_id,
    idempotency,
    packet_path,
    digest,
    packet_maximum,
  ))
}

fn inspect_decoder() -> decode.Decoder(InspectInput) {
  use path <- decode.field("journalPath", decode.string)
  use maximum <- decode.field("maximumJournalBytes", decode.int)
  use review_id <- decode.field("reviewId", decode.string)
  use private <- decode.field("includePrivate", decode.bool)
  use history <- decode.field("maximumHistory", decode.int)
  decode.success(InspectInput(path, maximum, review_id, private, history))
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Int, maximum: Int) -> schema.Schema {
  schema.integer()
  |> schema.with_number_range(int.to_float(minimum), int.to_float(maximum))
}
