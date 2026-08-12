import finance_local_import
import finance_quant/common
import finance_quant/event_study
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool

pub type Input {
  Input(path: String, expected_sha256: String, maximum_bytes: Int)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "stock_event_study",
    "Calculate an exact point-in-time event study",
    "Verify canonical universe and dataset manifests, calculate security and benchmark returns, caller-selected expected and abnormal returns, CAR, AAR, model coefficients, unperformed events, and explicitly requested statistics",
    "The caller selects event identities, clusters, windows, model, benchmark series, missing policy, trial, and interpretation; this tool makes no causal, significance, edge, recommendation, or deployment claim",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      use outcome <- promise.await(finance_local_import.read(
        input.path,
        input.maximum_bytes,
        raw.dynamic(signal),
      ))
      finish(outcome, input.expected_sha256)
    },
  )
  promise.resolve(Nil)
}

fn finish(
  outcome: finance_local_import.Outcome,
  expected: String,
) -> Promise(tool.ToolResult) {
  case outcome {
    finance_local_import.Loaded(text, _) ->
      case event_study.calculate(text, expected) {
        Ok(value) ->
          tool.text_result(common.summary(value), common.details(value))
          |> promise.resolve
        Error(error) -> tool.reject(common.error_message(error))
      }
    finance_local_import.Truncated(_, total) ->
      tool.reject(
        "Event-study packet exceeds maximumBytes: " <> int.to_string(total),
      )
    finance_local_import.Cancelled ->
      tool.reject("Event-study import was cancelled")
    finance_local_import.Missing ->
      tool.reject("Event-study packet was not found")
    finance_local_import.InvalidUtf8 ->
      tool.reject("Event-study packet requires strict UTF-8")
    finance_local_import.Failure(code) ->
      tool.reject("Event-study import failed safely: " <> code)
    finance_local_import.InvalidResult ->
      tool.reject("Event-study import returned an invalid effect result")
  }
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "path",
      schema.string() |> schema.with_string_length(1, 4096),
    ),
    schema.Required(
      "expectedSha256",
      schema.string() |> schema.with_string_length(64, 64),
    ),
    schema.Required(
      "maximumBytes",
      schema.integer() |> schema.with_number_range(1.0, 5_000_000.0),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use path <- decode.field("path", decode.string)
  use digest <- decode.field("expectedSha256", decode.string)
  use maximum <- decode.field("maximumBytes", decode.int)
  decode.success(Input(path, digest, maximum))
}
