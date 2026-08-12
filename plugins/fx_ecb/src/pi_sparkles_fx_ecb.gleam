import finance_local_import
import finance_multi_asset/common
import finance_multi_asset/fx as domain
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
    "ecb_fx_calculate",
    "Calculate one exact ECB reference-rate conversion",
    "Validate same-date ECB euro-reference legs and calculate exact cross, inverse and converted amounts with publication, TARGET-calendar, source, rights and receipt context",
    "The caller owns currencies, amount and interpretation; rates remain non-executable references with no stale carry, silent fallback or trading advice",
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
      case domain.calculate(text, expected) {
        Ok(value) ->
          tool.text_result(common.summary(value), common.details(value))
          |> promise.resolve
        Error(error) -> tool.reject(common.error_message(error))
      }
    finance_local_import.Truncated(_, total) ->
      tool.reject(
        "ECB FX packet exceeds maximumBytes: " <> int.to_string(total),
      )
    finance_local_import.Cancelled -> tool.reject("ECB FX import was cancelled")
    finance_local_import.Missing -> tool.reject("ECB FX packet was not found")
    finance_local_import.InvalidUtf8 ->
      tool.reject("ECB FX packet requires strict UTF-8")
    finance_local_import.Failure(code) ->
      tool.reject("ECB FX import failed safely: " <> code)
    finance_local_import.InvalidResult ->
      tool.reject("ECB FX import returned an invalid effect result")
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
