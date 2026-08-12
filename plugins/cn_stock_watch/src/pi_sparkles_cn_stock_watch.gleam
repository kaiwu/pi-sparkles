import finance_local_import
import finance_monitoring/source
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_stock_watch/domain

pub type Input {
  Input(
    path: String,
    expected_sha256: String,
    maximum_bytes: Int,
    offset: Int,
    limit: Int,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "cn_stock_watch_query",
    "Query exact mainland disclosure events",
    "Validate and page exact CN announcement, performance, unlock, pledge, suspension, dated rule-state and Stock Connect receipts for one resolved mainland listing, retaining original Chinese metadata and date semantics",
    "The plugin never imports HK/US domains, changes identity, treats silence as no event, scores severity, interprets policy/risk, notifies, recommends, or trades",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      use outcome <- promise.await(finance_local_import.read(
        input.path,
        input.maximum_bytes,
        raw.dynamic(signal),
      ))
      finish(outcome, input)
    },
  )
  promise.resolve(Nil)
}

fn finish(
  outcome: finance_local_import.Outcome,
  input: Input,
) -> Promise(tool.ToolResult) {
  case outcome {
    finance_local_import.Loaded(text, _) ->
      case
        source.project(
          domain.descriptor(),
          text,
          input.expected_sha256,
          input.offset,
          input.limit,
        )
      {
        Ok(value) ->
          tool.text_result(source.summary(value), source.details(value))
          |> promise.resolve
        Error(error) -> tool.reject(source.error_message(error))
      }
    finance_local_import.Truncated(_, total) ->
      tool.reject(
        "CN watch receipt packet exceeds maximumBytes: " <> int.to_string(total),
      )
    finance_local_import.Cancelled ->
      tool.reject("CN watch receipt import was cancelled")
    finance_local_import.Missing ->
      tool.reject("CN watch receipt packet was not found")
    finance_local_import.InvalidUtf8 ->
      tool.reject("CN watch receipt packet requires strict UTF-8")
    finance_local_import.Failure(code) ->
      tool.reject("CN watch receipt import failed safely: " <> code)
    finance_local_import.InvalidResult ->
      tool.reject("CN watch receipt import returned an invalid effect result")
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
    schema.Required(
      "offset",
      schema.integer() |> schema.with_number_range(0.0, 10_000.0),
    ),
    schema.Required(
      "limit",
      schema.integer() |> schema.with_number_range(1.0, 200.0),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use path <- decode.field("path", decode.string)
  use digest <- decode.field("expectedSha256", decode.string)
  use maximum <- decode.field("maximumBytes", decode.int)
  use offset <- decode.field("offset", decode.int)
  use limit <- decode.field("limit", decode.int)
  decode.success(Input(path, digest, maximum, offset, limit))
}
