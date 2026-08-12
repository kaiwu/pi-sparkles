import finance_local_import
import finance_portfolio_review as review
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_portfolio_scenarios/domain

pub type Input {
  Input(path: String, expected_sha256: String, maximum_bytes: Int)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "run_scenario",
    "Run caller-defined portfolio scenario",
    "Apply exact caller-defined price shocks to a content-bound mixed-track portfolio receipt packet and return per-position and aggregate impacts, unaffected rows, formulas, assumptions, and a canonical receipt",
    "The caller selects every shock and FX receipt; results are never forecasts, probabilities, worst cases, or capital-adequacy judgments",
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
      case
        review.calculate(domain.descriptor(), "run_scenario", text, expected)
      {
        Ok(value) ->
          tool.text_result(review.summary(value), review.details(value))
          |> promise.resolve
        Error(error) -> tool.reject(review.error_message(error))
      }
    finance_local_import.Truncated(_, total) ->
      tool.reject(
        "Scenario packet exceeds maximumBytes: " <> int.to_string(total),
      )
    finance_local_import.Cancelled ->
      tool.reject("Scenario import was cancelled")
    finance_local_import.Missing -> tool.reject("Scenario packet was not found")
    finance_local_import.InvalidUtf8 ->
      tool.reject("Scenario packet requires strict UTF-8")
    finance_local_import.Failure(code) ->
      tool.reject("Scenario import failed safely: " <> code)
    finance_local_import.InvalidResult ->
      tool.reject("Scenario import returned an invalid effect result")
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
