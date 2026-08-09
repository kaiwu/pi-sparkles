import finance_core/time
import finance_provenance/hash
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option, None, Some}
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_portfolio/domain
import pi_sparkles_portfolio/effect/environment
import pi_sparkles_portfolio/effect/store
import pi_sparkles_portfolio_local_file as local_file

type PositionRequest {
  PositionRequest(
    snapshot_id: String,
    cursor: Int,
    limit: Int,
    filter: domain.PositionFilter,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let snapshots = store.new(domain.new_state())
  register_import(api, snapshots)
  register_summary(api, snapshots)
  register_positions(api, snapshots)
  promise.resolve(Nil)
}

fn register_import(
  api: pi.ExtensionApi,
  snapshots: store.Store(domain.State),
) -> Nil {
  tool.register(
    api,
    "portfolio_import",
    "Import bounded portfolio facts",
    "Read one exact caller-supplied local CSV or JSON file under explicit budgets; preserve snapshot, identity, currency, time, row, source-value, information-state, privacy, truncation, and reconciliation facts in a bounded non-durable session store",
    "Use only for unauthenticated read-only import; parsing does not prove broker origin, completeness, settlement, freshness, tradability, portfolio sufficiency, or correctness",
    tool.parameters(import_schema(), import_decoder()),
    tool.Sequential,
    fn(_id, plan, signal, _updates, _ctx) {
      use outcome <- promise.await(local_file.read(
        plan.path,
        plan.maximum_file_bytes,
        raw.dynamic(signal),
      ))
      case outcome {
        local_file.Loaded(text, bytes) ->
          finish_import(snapshots, plan, text, bytes, bytes, False)
        local_file.Truncated(text, bytes, total) ->
          finish_import(snapshots, plan, text, bytes, total, True)
        local_file.Cancelled -> tool.reject("Portfolio import was cancelled")
        local_file.Missing -> tool.reject("Portfolio import file was not found")
        local_file.InvalidUtf8 ->
          tool.reject("Portfolio import requires strict UTF-8 input")
        local_file.Failure(code) ->
          tool.reject("Portfolio file read failed safely: " <> code)
        local_file.InvalidResult ->
          tool.reject("Portfolio file read returned an invalid effect result")
      }
    },
  )
}

fn finish_import(
  snapshots: store.Store(domain.State),
  plan: domain.ImportPlan,
  text: String,
  retained_bytes: Int,
  total_bytes: Int,
  byte_truncated: Bool,
) -> Promise(tool.ToolResult) {
  case hash.text(text), time.instant(environment.now_milliseconds()) {
    Error(_), _ ->
      tool.reject("Portfolio import bytes could not be content-bound")
    _, Error(_) -> tool.reject("Portfolio import clock was invalid")
    Ok(digest), Ok(imported_at) ->
      case
        domain.decode_document(
          plan,
          text,
          retained_bytes,
          total_bytes,
          byte_truncated,
          digest,
          imported_at,
        )
      {
        Error(error) -> tool.reject(domain.error_message(error))
        Ok(snapshot) ->
          case domain.store_snapshot(store.read(snapshots), snapshot) {
            Error(error) -> tool.reject(domain.error_message(error))
            Ok(domain.Stored(next, stored)) -> {
              store.write(snapshots, next)
              complete_summary(stored, "portfolio_import", "Imported")
            }
            Ok(domain.Existing(_, existing)) ->
              complete_summary(existing, "portfolio_import", "Reused exact")
          }
      }
  }
}

fn register_summary(
  api: pi.ExtensionApi,
  snapshots: store.Store(domain.State),
) -> Nil {
  tool.register(
    api,
    "portfolio_summary",
    "Inspect imported portfolio summary",
    "Return the compact exact summary of one immutable snapshot already imported into this bounded extension instance without rereading a file or persisting state",
    "Supply the exact snapshotId returned by portfolio_import; the LLM interprets every reconciliation, omission, conflict, and next operation",
    tool.parameters(snapshot_schema(), snapshot_decoder()),
    tool.Sequential,
    fn(_id, snapshot_id, _signal, _updates, _ctx) {
      case domain.lookup(store.read(snapshots), snapshot_id) {
        None -> tool.reject("Portfolio snapshot was not found in this session")
        Some(snapshot) ->
          complete_summary(snapshot, "portfolio_summary", "Inspected")
      }
    },
  )
}

fn register_positions(
  api: pi.ExtensionApi,
  snapshots: store.Store(domain.State),
) -> Nil {
  tool.register(
    api,
    "portfolio_positions",
    "Page exact imported position rows",
    "Return a bounded filtered page of retained source rows with per-field information states, exact lexemes and provenance, unsupported/conflict flags, source-reported facts, and independently calculated value when possible",
    "Drill by exact snapshot and optional exact filters; rows remain unaggregated and no portfolio judgment or action is selected",
    tool.parameters(positions_schema(), positions_decoder()),
    tool.Sequential,
    fn(_id, request, _signal, _updates, _ctx) {
      case domain.lookup(store.read(snapshots), request.snapshot_id) {
        None -> tool.reject("Portfolio snapshot was not found in this session")
        Some(snapshot) ->
          case
            domain.positions_page(
              snapshot,
              request.cursor,
              request.limit,
              request.filter,
            )
          {
            Error(message) -> tool.reject(message)
            Ok(details) ->
              tool.text_result(
                "Exact retained portfolio rows for " <> request.snapshot_id,
                details,
              )
              |> promise.resolve
          }
      }
    },
  )
}

fn complete_summary(
  snapshot: domain.Snapshot,
  operation: String,
  verb: String,
) -> Promise(tool.ToolResult) {
  tool.text_result(
    verb
      <> " unauthenticated portfolio snapshot "
      <> snapshot.snapshot_id
      <> "; inspect reconciliation, truncation, unsupported, conflict, decode, identity, currency, and time facts before any LLM/user decision.",
    domain.summary(snapshot, operation),
  )
  |> promise.resolve
}

fn import_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "path",
      bounded_string(1, 4096)
        |> schema.described(
          "Exact caller-authorized local regular-file path; always redacted from results",
        ),
    ),
    schema.Required("format", schema.string_enum(["csv", "json"])),
    schema.Required(
      "delimiter",
      schema.string_enum(["comma", "tab", "semicolon"])
        |> schema.described("Required explicit CSV delimiter; ignored for JSON"),
    ),
    schema.Required(
      "decimalConvention",
      schema.string_enum([
        "plain_dot",
        "comma_grouped_dot_decimal",
        "space_grouped_comma_decimal",
      ]),
    ),
    schema.Required("maximumBytes", bounded_integer(1, 10_000_000)),
    schema.Required("maximumRows", bounded_integer(1, 10_000)),
    schema.Required("maximumColumns", bounded_integer(1, 100)),
    schema.Required("maximumFieldBytes", bounded_integer(1, 4096)),
    schema.Required("maximumJsonDepth", bounded_integer(1, 10)),
    schema.Required("maximumJsonElements", bounded_integer(1, 10_000)),
    schema.Required(
      "reconciliationTolerance",
      bounded_string(1, 100)
        |> schema.described(
          "Exact non-negative decimal in the declared convention",
        ),
    ),
    schema.Required(
      "accountVisibility",
      schema.string_enum(["redacted", "review_visible"]),
    ),
  ])
}

fn snapshot_schema() -> schema.Schema {
  schema.object([schema.Required("snapshotId", bounded_string(1, 1024))])
}

fn positions_schema() -> schema.Schema {
  schema.object([
    schema.Required("snapshotId", bounded_string(1, 1024)),
    schema.Required("cursor", bounded_integer(0, 10_000)),
    schema.Required("limit", bounded_integer(1, 200)),
    optional_string("positionId", 1024),
    optional_string("sourceRowId", 1024),
    optional_string("track", 16),
    optional_string("currency", 16),
    optional_string("securityType", 100),
    optional_bool("identityResolved"),
    optional_bool("unsupported"),
    optional_bool("conflicting"),
    optional_bool("hasDecodeFailure"),
  ])
}

fn import_decoder() -> decode.Decoder(domain.ImportPlan) {
  use path <- decode.field("path", decode.string)
  use format <- decode.field("format", decode.string)
  use delimiter <- decode.field("delimiter", decode.string)
  use convention <- decode.field("decimalConvention", decode.string)
  use maximum_bytes <- decode.field("maximumBytes", decode.int)
  use maximum_rows <- decode.field("maximumRows", decode.int)
  use maximum_columns <- decode.field("maximumColumns", decode.int)
  use maximum_field_bytes <- decode.field("maximumFieldBytes", decode.int)
  use maximum_json_depth <- decode.field("maximumJsonDepth", decode.int)
  use maximum_json_elements <- decode.field("maximumJsonElements", decode.int)
  use tolerance <- decode.field("reconciliationTolerance", decode.string)
  use visibility <- decode.field("accountVisibility", decode.string)
  case
    domain.import_plan(
      path,
      format,
      delimiter,
      convention,
      maximum_bytes,
      maximum_rows,
      maximum_columns,
      maximum_field_bytes,
      maximum_json_depth,
      maximum_json_elements,
      tolerance,
      visibility,
    )
  {
    Ok(plan) -> decode.success(plan)
    Error(error) -> decode.failure(fallback_plan(), domain.error_message(error))
  }
}

fn snapshot_decoder() -> decode.Decoder(String) {
  use snapshot_id <- decode.field("snapshotId", decode.string)
  decode.success(snapshot_id)
}

fn positions_decoder() -> decode.Decoder(PositionRequest) {
  use snapshot_id <- decode.field("snapshotId", decode.string)
  use cursor <- decode.field("cursor", decode.int)
  use limit <- decode.field("limit", decode.int)
  use position_id <- optional_string_decoder("positionId")
  use source_row_id <- optional_string_decoder("sourceRowId")
  use track <- optional_string_decoder("track")
  use currency <- optional_string_decoder("currency")
  use security_type <- optional_string_decoder("securityType")
  use identity_resolved <- optional_bool_decoder("identityResolved")
  use unsupported <- optional_bool_decoder("unsupported")
  use conflicting <- optional_bool_decoder("conflicting")
  use has_decode_failure <- optional_bool_decoder("hasDecodeFailure")
  decode.success(PositionRequest(
    snapshot_id,
    cursor,
    limit,
    domain.PositionFilter(
      position_id,
      source_row_id,
      track,
      currency,
      security_type,
      identity_resolved,
      unsupported,
      conflicting,
      has_decode_failure,
    ),
  ))
}

fn optional_string_decoder(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn optional_bool_decoder(
  name: String,
  next: fn(Option(Bool)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.bool), next)
}

fn fallback_plan() -> domain.ImportPlan {
  let assert Ok(plan) =
    domain.import_plan(
      "/invalid",
      "csv",
      "comma",
      "plain_dot",
      1,
      1,
      1,
      1,
      1,
      1,
      "0",
      "redacted",
    )
  plan
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Int, maximum: Int) -> schema.Schema {
  schema.integer()
  |> schema.with_number_range(int.to_float(minimum), int.to_float(maximum))
}

fn optional_string(name: String, maximum: Int) -> schema.Property {
  schema.Optional(name, schema.nullable(bounded_string(1, maximum)))
}

fn optional_bool(name: String) -> schema.Property {
  schema.Optional(name, schema.nullable(schema.boolean()))
}
