import finance_local_import
import finance_research_calculation as calculation
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_consensus_estimates/domain

pub type Input {
  Input(path: String, expected_sha256: String, maximum_bytes: Int)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "consensus_estimate_calculation",
    "Calculate consensus estimate calculation",
    "Read one exact content-bound request from a caller-owned UTF-8 file and perform only the named exact-decimal consensus estimate calculation mechanics with complete source leaves, context proof, expression, and canonical receipt",
    "The caller selects every source, operation, period, assumption, unit, currency, scale, and rounding policy; the LLM owns interpretation and every investment decision",
    tool.parameters(input_schema(), input_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      use outcome <- promise.await(finance_local_import.read(
        input.path,
        input.maximum_bytes,
        raw.dynamic(signal),
      ))
      case outcome {
        finance_local_import.Loaded(text, _) ->
          complete(calculation.calculate(
            domain.descriptor(),
            calculation.input(input.path, input.expected_sha256),
            text,
          ))
        finance_local_import.Truncated(_, total) ->
          tool.reject(
            "Calculation import exceeds maximumBytes; total bytes: "
            <> int.to_string(total),
          )
        finance_local_import.Cancelled ->
          tool.reject("Calculation import was cancelled")
        finance_local_import.Missing ->
          tool.reject("Calculation import file was not found")
        finance_local_import.InvalidUtf8 ->
          tool.reject("Calculation import requires strict UTF-8")
        finance_local_import.Failure(code) ->
          tool.reject("Calculation import failed safely: " <> code)
        finance_local_import.InvalidResult ->
          tool.reject("Calculation import effect returned an invalid result")
      }
    },
  )
  promise.resolve(Nil)
}

fn complete(
  value: Result(calculation.Response, calculation.CalculationError),
) -> Promise(tool.ToolResult) {
  case value {
    Ok(value) ->
      tool.text_result(calculation.summary(value), calculation.details(value))
      |> promise.resolve
    Error(error) -> tool.reject(calculation.error_message(error))
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
  use expected_sha256 <- decode.field("expectedSha256", decode.string)
  use maximum_bytes <- decode.field("maximumBytes", decode.int)
  decode.success(Input(path, expected_sha256, maximum_bytes))
}
