import finance_local_import
import finance_text_analysis/sentiment
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
    "sentiment_analyze",
    "Run transparent finance lexicon classification",
    "Apply only finance_lexicon_v1 to caller-supplied exact token spans in bounded content-bound documents; expose per-label scores, every contributing span and offset, model parameters, conflicts, warnings, rights, and reproducible hashes",
    "Choose the documents and aggregation policy yourself; scores are lexical classifications, never truth, credibility, market impact, mood, or trading signals",
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
          case sentiment.analyze(input.expected_sha256, text) {
            Error(error) -> tool.reject(sentiment.error_message(error))
            Ok(value) ->
              tool.text_result(
                sentiment.summary(value),
                sentiment.details(value),
              )
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
      "Sentiment import exceeds maximumBytes; total bytes: "
      <> int.to_string(total)
    finance_local_import.Cancelled -> "Sentiment import was cancelled"
    finance_local_import.Missing -> "Sentiment import file was not found"
    finance_local_import.InvalidUtf8 -> "Sentiment import requires strict UTF-8"
    finance_local_import.Failure(code) ->
      "Sentiment import failed safely: " <> code
    finance_local_import.InvalidResult ->
      "Sentiment import effect returned an invalid result"
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
