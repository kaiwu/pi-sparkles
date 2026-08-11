import finance_local_import
import finance_research_contract as research
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_hk_stock_board_lot/domain

pub type InspectInput {
  InspectInput(
    path: String,
    expected_sha256: String,
    maximum_bytes: Int,
    offset: Int,
    limit: Int,
  )
}

pub type DrillInput {
  DrillInput(
    path: String,
    expected_sha256: String,
    maximum_bytes: Int,
    record_id: String,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_inspect(api)
  register_drill(api)
  promise.resolve(Nil)
}

fn register_inspect(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "hk_board_lots",
    "Inspect HK board-lot observations",
    "Read and validate one exact content-bound hk research packet from a caller-owned regular UTF-8 file; return compact source facts, omissions, and stable record handles without interpretation",
    "Supply a versioned import file and exact SHA-256; the LLM owns source interpretation and every investment decision",
    tool.parameters(inspect_schema(), inspect_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      use outcome <- promise.await(finance_local_import.read(
        input.path,
        input.maximum_bytes,
        raw.dynamic(signal),
      ))
      case outcome {
        finance_local_import.Loaded(text, _) ->
          complete(research.inspect(
            domain.descriptor(),
            research.input(
              input.path,
              input.expected_sha256,
              input.offset,
              input.limit,
            ),
            text,
          ))
        finance_local_import.Truncated(_, total) ->
          tool.reject(
            "Import exceeds maximumBytes; total bytes: " <> int.to_string(total),
          )
        finance_local_import.Cancelled -> tool.reject("Import was cancelled")
        finance_local_import.Missing -> tool.reject("Import file was not found")
        finance_local_import.InvalidUtf8 ->
          tool.reject("Import requires strict UTF-8")
        finance_local_import.Failure(code) ->
          tool.reject("Import failed safely: " <> code)
        finance_local_import.InvalidResult ->
          tool.reject("Import effect returned an invalid result")
      }
    },
  )
}

fn register_drill(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "hk_board_lot_record",
    "Drill one HK board-lot observations record",
    "Reread the same exact content-bound import and return one complete record with source fields and correction lineage",
    "Use the packet hash and recordId returned by hk_board_lots; no latest-record or preferred-source choice is made",
    tool.parameters(drill_schema(), drill_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      use outcome <- promise.await(finance_local_import.read(
        input.path,
        input.maximum_bytes,
        raw.dynamic(signal),
      ))
      case outcome {
        finance_local_import.Loaded(text, _) ->
          complete(research.drill(
            domain.descriptor(),
            research.drill_input(
              input.path,
              input.expected_sha256,
              input.record_id,
            ),
            text,
          ))
        finance_local_import.Truncated(_, total) ->
          tool.reject(
            "Import exceeds maximumBytes; total bytes: " <> int.to_string(total),
          )
        finance_local_import.Cancelled -> tool.reject("Import was cancelled")
        finance_local_import.Missing -> tool.reject("Import file was not found")
        finance_local_import.InvalidUtf8 ->
          tool.reject("Import requires strict UTF-8")
        finance_local_import.Failure(code) ->
          tool.reject("Import failed safely: " <> code)
        finance_local_import.InvalidResult ->
          tool.reject("Import effect returned an invalid result")
      }
    },
  )
}

fn complete(
  value: Result(research.Response, research.ContractError),
) -> Promise(tool.ToolResult) {
  case value {
    Ok(value) ->
      tool.text_result(research.summary(value), research.details(value))
      |> promise.resolve
    Error(error) -> tool.reject(research.error_message(error))
  }
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Required("path", bounded_string(1, 4096)),
    schema.Required("expectedSha256", bounded_string(64, 64)),
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
      schema.integer() |> schema.with_number_range(1.0, 100.0),
    ),
  ])
}

fn drill_schema() -> schema.Schema {
  schema.object([
    schema.Required("path", bounded_string(1, 4096)),
    schema.Required("expectedSha256", bounded_string(64, 64)),
    schema.Required(
      "maximumBytes",
      schema.integer() |> schema.with_number_range(1.0, 5_000_000.0),
    ),
    schema.Required("recordId", bounded_string(1, 4000)),
  ])
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn inspect_decoder() -> decode.Decoder(InspectInput) {
  use path <- decode.field("path", decode.string)
  use expected_sha256 <- decode.field("expectedSha256", decode.string)
  use maximum_bytes <- decode.field("maximumBytes", decode.int)
  use offset <- decode.field("offset", decode.int)
  use limit <- decode.field("limit", decode.int)
  decode.success(InspectInput(
    path,
    expected_sha256,
    maximum_bytes,
    offset,
    limit,
  ))
}

fn drill_decoder() -> decode.Decoder(DrillInput) {
  use path <- decode.field("path", decode.string)
  use expected_sha256 <- decode.field("expectedSha256", decode.string)
  use maximum_bytes <- decode.field("maximumBytes", decode.int)
  use record_id <- decode.field("recordId", decode.string)
  decode.success(DrillInput(path, expected_sha256, maximum_bytes, record_id))
}
