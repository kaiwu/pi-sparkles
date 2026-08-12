import finance_local_import
import finance_multi_asset/cn as domain
import finance_multi_asset/common
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
    "cn_macro_series",
    "Inspect one exact mainland macro series",
    "Select one official mainland macro vintage at a declared knowledge cutoff, retaining series identity, geography, frequency, unit, revisions, source rights and exact period-change calculation",
    "The caller owns series selection and interpretation; no vintage overwrite, frequency coercion, policy conclusion, forecast or recommendation occurs",
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
      case domain.macro_series(text, expected) {
        Ok(value) ->
          tool.text_result(common.summary(value), common.details(value))
          |> promise.resolve
        Error(error) -> tool.reject(common.error_message(error))
      }
    finance_local_import.Truncated(_, total) ->
      tool.reject(
        "CN macro packet exceeds maximumBytes: " <> int.to_string(total),
      )
    finance_local_import.Cancelled ->
      tool.reject("CN macro import was cancelled")
    finance_local_import.Missing -> tool.reject("CN macro packet was not found")
    finance_local_import.InvalidUtf8 ->
      tool.reject("CN macro packet requires strict UTF-8")
    finance_local_import.Failure(code) ->
      tool.reject("CN macro import failed safely: " <> code)
    finance_local_import.InvalidResult ->
      tool.reject("CN macro import returned an invalid effect result")
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
