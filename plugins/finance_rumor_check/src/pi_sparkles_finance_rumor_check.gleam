import finance_local_import
import finance_text_analysis/rumor
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
    "rumor_check",
    "Compare a structured claim with supplied evidence",
    "Independently classify each caller-supplied bounded source as supports, contradicts, related, not_found, inaccessible, cannot_evaluate, or conflict using exact structured predicate/value/unit and negation/exclusivity mechanics; preserve passages, authority roles, provenance, circularity, scope, cutoff, omissions, and hashes",
    "Supply the structured claim and evidence search record yourself; NotFound never means false and the plugin never emits verified, debunked, credibility, materiality, recommendation, or trade verdicts",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      use outcome <- promise.await(finance_local_import.read(
        input.path,
        input.maximum_bytes,
        raw.dynamic(signal),
      ))
      case outcome {
        finance_local_import.Loaded(text, _) ->
          case rumor.check(input.expected_sha256, text) {
            Error(error) -> tool.reject(rumor.error_message(error))
            Ok(value) ->
              tool.text_result(rumor.summary(value), rumor.details(value))
              |> promise.resolve
          }
        other -> tool.reject(import_error(other))
      }
    },
  )
  promise.resolve(Nil)
}

fn import_error(value: finance_local_import.Outcome) -> String {
  case value {
    finance_local_import.Truncated(_, total) ->
      "Rumor-check import exceeds maximumBytes; total bytes: "
      <> int.to_string(total)
    finance_local_import.Cancelled -> "Rumor-check import was cancelled"
    finance_local_import.Missing -> "Rumor-check import file was not found"
    finance_local_import.InvalidUtf8 ->
      "Rumor-check import requires strict UTF-8"
    finance_local_import.Failure(code) ->
      "Rumor-check import failed safely: " <> code
    finance_local_import.InvalidResult ->
      "Rumor-check import effect returned an invalid result"
    finance_local_import.Loaded(_, _) -> "unreachable"
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
  use expected <- decode.field("expectedSha256", decode.string)
  use maximum <- decode.field("maximumBytes", decode.int)
  decode.success(Input(path, expected, maximum))
}
