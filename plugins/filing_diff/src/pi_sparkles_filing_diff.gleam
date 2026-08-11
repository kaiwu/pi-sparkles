import finance_local_import
import finance_research_diff as diff
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_filing_diff/domain

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
    change_id: String,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_page(api, "diff_filings", "Compare exact filing versions")
  register_page(api, "list_changed_sections", "List changed filing sections")
  tool.register(
    api,
    "drill_change",
    "Drill one exact filing change",
    "Read one exact content-bound comparison packet and return both raw section versions, exact anchors, the named normalized projection, document identities, correction lineage, and hashes for one changeId",
    "Interpret materiality and meaning yourself; this tool reports deterministic text changes only",
    tool.parameters(drill_schema(), drill_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      run_drill(input, raw.dynamic(signal))
    },
  )
  promise.resolve(Nil)
}

fn register_page(api: pi.ExtensionApi, name: String, label: String) -> Nil {
  tool.register(
    api,
    name,
    label,
    "Read one exact content-bound comparison packet and page deterministic insert, delete, replace, and move facts under the caller-selected raw or whitespace_v1 view",
    "Select the exact filing versions and view; the LLM owns all semantic, materiality, and investment interpretation",
    tool.parameters(page_schema(), page_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      run_page(input, raw.dynamic(signal))
    },
  )
}

fn run_page(input: PageInput, signal: Dynamic) -> Promise(tool.ToolResult) {
  use outcome <- promise.await(finance_local_import.read(
    input.path,
    input.maximum_bytes,
    signal,
  ))
  case outcome {
    finance_local_import.Loaded(text, _) ->
      case diff.compare(domain.descriptor(), input.expected_sha256, text) {
        Error(error) -> tool.reject(diff.error_message(error))
        Ok(value) ->
          case diff.list_changes(value, input.offset, input.limit) {
            Error(error) -> tool.reject(diff.error_message(error))
            Ok(details) ->
              tool.text_result(diff.summary(value), details) |> promise.resolve
          }
      }
    other -> tool.reject(import_error(other))
  }
}

fn run_drill(input: DrillInput, signal: Dynamic) -> Promise(tool.ToolResult) {
  use outcome <- promise.await(finance_local_import.read(
    input.path,
    input.maximum_bytes,
    signal,
  ))
  case outcome {
    finance_local_import.Loaded(text, _) ->
      case diff.compare(domain.descriptor(), input.expected_sha256, text) {
        Error(error) -> tool.reject(diff.error_message(error))
        Ok(value) ->
          case diff.drill_change(value, input.change_id) {
            Error(error) -> tool.reject(diff.error_message(error))
            Ok(details) ->
              tool.text_result(
                "Exact filing change " <> input.change_id,
                details,
              )
              |> promise.resolve
          }
      }
    other -> tool.reject(import_error(other))
  }
}

fn import_error(value: finance_local_import.Outcome) -> String {
  case value {
    finance_local_import.Truncated(_, total) ->
      "Diff import exceeds maximumBytes; total bytes: " <> int.to_string(total)
    finance_local_import.Cancelled -> "Diff import was cancelled"
    finance_local_import.Missing -> "Diff import file was not found"
    finance_local_import.InvalidUtf8 -> "Diff import requires strict UTF-8"
    finance_local_import.Failure(code) -> "Diff import failed safely: " <> code
    finance_local_import.InvalidResult ->
      "Diff import effect returned an invalid result"
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
    schema.Required("changeId", bounded_string(1, 500)),
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
  use change_id <- decode.field("changeId", decode.string)
  decode.success(DrillInput(path, expected, maximum, change_id))
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}
