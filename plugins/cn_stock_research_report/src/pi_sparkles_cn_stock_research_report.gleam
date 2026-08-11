import finance_local_import
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_stock_research_report/report

pub type PageInput {
  PageInput(
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
    section_id: String,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "inspect_cn_research_report",
    "Inspect CN research report receipts",
    "Deterministically compose caller-selected CN identity, disclosure, financial, peer, comparable, valuation, and industry receipt sections while preserving exact facts, source roles, conflicts, omissions, Chinese originals, and separately attributed translations",
    "Select every input receipt and make every interpretation yourself; missing sections remain missing",
    tool.parameters(page_schema(), page_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      run_page(input, raw.dynamic(signal))
    },
  )
  tool.register(
    api,
    "drill_cn_report_section",
    "Drill CN research report section",
    "Return one exact caller-selected report section with all fact states, source handles, conflicts, omissions, receipt hash, and original/translation lineage",
    "Treat Chinese originals as controlling; translations are labelled projections only",
    tool.parameters(drill_schema(), drill_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      run_drill(input, raw.dynamic(signal))
    },
  )
  promise.resolve(Nil)
}

fn run_page(input: PageInput, signal: Dynamic) -> Promise(tool.ToolResult) {
  use value <- promise.await(load(
    input.path,
    input.expected_sha256,
    input.maximum_bytes,
    signal,
  ))
  case value {
    Error(message) -> tool.reject(message)
    Ok(value) ->
      case report.inspect(value, input.offset, input.limit) {
        Error(error) -> tool.reject(report.error_message(error))
        Ok(details) ->
          tool.text_result(report.summary(value), details) |> promise.resolve
      }
  }
}

fn run_drill(input: DrillInput, signal: Dynamic) -> Promise(tool.ToolResult) {
  use value <- promise.await(load(
    input.path,
    input.expected_sha256,
    input.maximum_bytes,
    signal,
  ))
  case value {
    Error(message) -> tool.reject(message)
    Ok(value) ->
      case report.drill(value, input.section_id) {
        Error(error) -> tool.reject(report.error_message(error))
        Ok(details) ->
          tool.text_result(
            "Exact CN report section " <> input.section_id,
            details,
          )
          |> promise.resolve
      }
  }
}

fn load(
  path: String,
  expected: String,
  maximum: Int,
  signal: Dynamic,
) -> Promise(Result(report.Report, String)) {
  use outcome <- promise.await(finance_local_import.read(path, maximum, signal))
  case outcome {
    finance_local_import.Loaded(text, _) ->
      case report.compose(expected, text) {
        Ok(value) -> promise.resolve(Ok(value))
        Error(error) -> promise.resolve(Error(report.error_message(error)))
      }
    other -> promise.resolve(Error(import_error(other)))
  }
}

fn import_error(value: finance_local_import.Outcome) -> String {
  case value {
    finance_local_import.Truncated(_, total) ->
      "CN report import exceeds maximumBytes; total bytes: "
      <> int.to_string(total)
    finance_local_import.Cancelled -> "CN report import was cancelled"
    finance_local_import.Missing -> "CN report import file was not found"
    finance_local_import.InvalidUtf8 -> "CN report import requires strict UTF-8"
    finance_local_import.Failure(code) ->
      "CN report import failed safely: " <> code
    finance_local_import.InvalidResult ->
      "CN report import effect returned an invalid result"
    finance_local_import.Loaded(_, _) -> "unreachable"
  }
}

fn page_schema() -> schema.Schema {
  schema.object([
    schema.Required("path", bounded_string(1, 4096)),
    schema.Required("expectedSha256", bounded_string(64, 64)),
    schema.Required(
      "maximumBytes",
      schema.integer() |> schema.with_number_range(1.0, 5_000_000.0),
    ),
    schema.Required(
      "offset",
      schema.integer() |> schema.with_number_range(0.0, 20.0),
    ),
    schema.Required(
      "limit",
      schema.integer() |> schema.with_number_range(1.0, 20.0),
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
    schema.Required("sectionId", bounded_string(1, 500)),
  ])
}

fn page_decoder() -> decode.Decoder(PageInput) {
  use path <- decode.field("path", decode.string)
  use expected <- decode.field("expectedSha256", decode.string)
  use maximum <- decode.field("maximumBytes", decode.int)
  use offset <- decode.field("offset", decode.int)
  use limit <- decode.field("limit", decode.int)
  decode.success(PageInput(path, expected, maximum, offset, limit))
}

fn drill_decoder() -> decode.Decoder(DrillInput) {
  use path <- decode.field("path", decode.string)
  use expected <- decode.field("expectedSha256", decode.string)
  use maximum <- decode.field("maximumBytes", decode.int)
  use section <- decode.field("sectionId", decode.string)
  decode.success(DrillInput(path, expected, maximum, section))
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}
