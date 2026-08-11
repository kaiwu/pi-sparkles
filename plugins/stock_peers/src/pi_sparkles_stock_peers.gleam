import finance_local_import
import finance_peer_set
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool

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
    candidate_id: String,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "inspect_peer_set",
    "Inspect caller-defined peer set",
    "Validate an exact target, candidate universe, evidence date, and explicit predicates; preserve every candidate and mechanically project accepted, rejected, or unresolved without discovery, ranking, weighting, or silent removal",
    "Choose the universe and every predicate yourself; use unresolved and rejected rows as evidence, not as hidden omissions",
    tool.parameters(page_schema(), page_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      run_page(input, raw.dynamic(signal))
    },
  )
  tool.register(
    api,
    "drill_peer_candidate",
    "Drill one peer candidate",
    "Return one candidate's exact identity, classifications, currency, fiscal period, every predicate state, observed lexeme, and source receipt from a content-bound peer set",
    "Interpret comparability and peer usefulness yourself; the plugin exposes only caller-selected predicate facts",
    tool.parameters(drill_schema(), drill_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      run_drill(input, raw.dynamic(signal))
    },
  )
  promise.resolve(Nil)
}

fn run_page(input: PageInput, signal: Dynamic) -> Promise(tool.ToolResult) {
  use loaded <- promise.await(load(
    input.path,
    input.expected_sha256,
    input.maximum_bytes,
    signal,
  ))
  case loaded {
    Error(message) -> tool.reject(message)
    Ok(value) ->
      case finance_peer_set.inspect(value, input.offset, input.limit) {
        Error(error) -> tool.reject(finance_peer_set.error_message(error))
        Ok(details) ->
          tool.text_result(finance_peer_set.summary(value), details)
          |> promise.resolve
      }
  }
}

fn run_drill(input: DrillInput, signal: Dynamic) -> Promise(tool.ToolResult) {
  use loaded <- promise.await(load(
    input.path,
    input.expected_sha256,
    input.maximum_bytes,
    signal,
  ))
  case loaded {
    Error(message) -> tool.reject(message)
    Ok(value) ->
      case finance_peer_set.drill(value, input.candidate_id) {
        Error(error) -> tool.reject(finance_peer_set.error_message(error))
        Ok(details) ->
          tool.text_result(
            "Exact peer candidate " <> input.candidate_id,
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
) -> Promise(Result(finance_peer_set.PeerSet, String)) {
  use outcome <- promise.await(finance_local_import.read(path, maximum, signal))
  case outcome {
    finance_local_import.Loaded(text, _) ->
      case finance_peer_set.project(expected, text) {
        Ok(value) -> promise.resolve(Ok(value))
        Error(error) ->
          promise.resolve(Error(finance_peer_set.error_message(error)))
      }
    other -> promise.resolve(Error(import_error(other)))
  }
}

fn import_error(value: finance_local_import.Outcome) -> String {
  case value {
    finance_local_import.Truncated(_, total) ->
      "Peer-set import exceeds maximumBytes; total bytes: "
      <> int.to_string(total)
    finance_local_import.Cancelled -> "Peer-set import was cancelled"
    finance_local_import.Missing -> "Peer-set import file was not found"
    finance_local_import.InvalidUtf8 -> "Peer-set import requires strict UTF-8"
    finance_local_import.Failure(code) ->
      "Peer-set import failed safely: " <> code
    finance_local_import.InvalidResult ->
      "Peer-set import effect returned an invalid result"
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
      schema.integer() |> schema.with_number_range(0.0, 200.0),
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
    schema.Required("candidateId", bounded_string(1, 500)),
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
  use candidate <- decode.field("candidateId", decode.string)
  decode.success(DrillInput(path, expected, maximum, candidate))
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}
