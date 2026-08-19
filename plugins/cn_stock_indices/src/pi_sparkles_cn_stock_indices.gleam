import finance_http/response as http_response
import finance_http/transport
import finance_local_import
import finance_provenance/hash
import finance_provenance/identity as provenance_identity
import finance_research_contract as research
import finance_sse_index
import finance_sse_index/composition as sse_composition
import finance_sse_index/constituents as sse_constituents
import finance_sse_index/query as sse_query
import finance_sse_index/request as sse_request
import finance_sse_index/runtime as sse_runtime
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_stock_indices/domain
import pi_sparkles_cn_stock_indices/effect/environment
import pi_sparkles_cn_stock_indices/live_composition
import pi_sparkles_cn_stock_indices/live_constituents

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

pub type ConstituentInput {
  ConstituentInput(venue: String, code: String)
}

type SseProvider {
  SseReady(finance_sse_index.Access, sse_runtime.Runtime)
  SseInvalidConfiguration(String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_inspect(api)
  register_drill(api)
  let provider = sse_provider()
  register_current_constituents(api, provider)
  register_industry_composition(api, provider)
  promise.resolve(Nil)
}

fn register_industry_composition(
  api: pi.ExtensionApi,
  provider: SseProvider,
) -> Nil {
  tool.register_compact(
    api,
    "cn_index_industry_composition",
    "Acquire current CN index industry composition",
    "Fetch one bounded credential-free industry-composition snapshot from the official Shanghai Stock Exchange public index service for an exact reviewed index identity, preserving effective date, sector member counts, exact provider weight lexemes, response hash, request count, and explicit omissions",
    "Use with cn_index_constituents when the user asks to analyze the current STAR 50 or 000688 composition. The reviewed registry currently contains sse 000688 only. Equivalent hk and us acquisition is explicitly track_partial and must not be inferred or substituted. This tool returns provider aggregate sectors, not per-stock classifications, price performance, causal attribution, recommendation, Eastmoney fallback, or Tushare data",
    tool.parameters(constituent_schema(), constituent_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      acquire_industry_composition(provider, id, input, signal)
    },
  )
}

fn register_current_constituents(
  api: pi.ExtensionApi,
  provider: SseProvider,
) -> Nil {
  tool.register_compact(
    api,
    "cn_index_constituents",
    "Acquire current CN index constituents",
    "Fetch one bounded credential-free constituent manifest from the official Shanghai Stock Exchange public index service for an exact reviewed index identity, preserving publication date, provider order, listing codes, names, response hash, request count, and explicit omissions",
    "Use this directly when the user asks for the current STAR 50 or 000688 member list. The reviewed registry currently contains sse 000688 only. Equivalent hk and us acquisition is explicitly track_partial and must not be inferred or substituted. This tool performs no quote fan-out, weighting, historical reconstruction, causal analysis, recommendation, Eastmoney fallback, or Tushare call",
    tool.parameters(constituent_schema(), constituent_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      acquire_current_constituents(provider, id, input, signal)
    },
  )
}

fn sse_provider() -> SseProvider {
  case finance_sse_index.access(environment.product(), environment.contact()) {
    Error(_) ->
      SseInvalidConfiguration(
        "Official SSE index acquisition requires AGENT_CONTACT; no fallback was attempted",
      )
    Ok(access) ->
      case sse_runtime.new(access) {
        Ok(runtime) -> SseReady(access, runtime)
        Error(_) ->
          SseInvalidConfiguration(
            "Official SSE index runtime could not initialize safely; no fallback was attempted",
          )
      }
  }
}

fn acquire_current_constituents(
  provider: SseProvider,
  id: String,
  input: ConstituentInput,
  signal,
) -> Promise(tool.ToolResult) {
  case sse_query.constituents(input.venue, input.code) {
    Error(_) ->
      reject_sse(
        "unsupported_index_identity",
        "cn_index_constituents is limited to the exact reviewed SSE index registry",
      )
    Ok(query) -> acquire_reviewed_constituents(provider, id, query, signal)
  }
}

fn acquire_reviewed_constituents(
  provider: SseProvider,
  id: String,
  query: sse_query.Query,
  signal,
) -> Promise(tool.ToolResult) {
  case provider {
    SseInvalidConfiguration(message) ->
      reject_sse("provider_configuration_invalid", message)
    SseReady(access, runtime) ->
      case sse_request.constituents(access, query) {
        Error(_) ->
          reject_sse(
            "invalid_sse_request",
            "Official SSE constituent request could not be constructed safely",
          )
        Ok(request) -> {
          use outcome <- promise.await(sse_runtime.send(
            runtime,
            id,
            request,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(error) ->
              reject_sse(
                "sse_constituent_request_failed",
                "Official SSE constituent request failed safely: "
                  <> string.inspect(error),
              )
            Ok(response) -> {
              let status = http_response.status(response)
              case status >= 200 && status < 300 {
                False ->
                  reject_sse(
                    "sse_constituent_http_error",
                    "Official SSE constituent request returned HTTP "
                      <> int.to_string(status),
                  )
                True -> {
                  let body = http_response.body(response)
                  case
                    sse_constituents.decode(body, for: query),
                    hash.text(body)
                  {
                    Error(_), _ ->
                      reject_sse(
                        "invalid_sse_constituent_response",
                        "Official SSE response was invalid, incomplete, identity-conflicting, or not the exact reviewed member count",
                      )
                    _, Error(_) ->
                      reject_sse(
                        "sse_constituent_receipt_failed",
                        "Official SSE constituent response could not be content-bound",
                      )
                    Ok(value), Ok(digest) ->
                      tool.text_result(
                        live_constituents.content(query, value),
                        live_constituents.details(
                          query,
                          value,
                          environment.now_milliseconds(),
                          http_response.byte_length(response),
                          provenance_identity.sha256_value(digest),
                        ),
                      )
                      |> promise.resolve
                  }
                }
              }
            }
          }
        }
      }
  }
}

fn acquire_industry_composition(
  provider: SseProvider,
  id: String,
  input: ConstituentInput,
  signal,
) -> Promise(tool.ToolResult) {
  case sse_query.constituents(input.venue, input.code) {
    Error(_) ->
      reject_sse(
        "unsupported_index_identity",
        "cn_index_industry_composition is limited to the exact reviewed SSE index registry",
      )
    Ok(query) -> acquire_reviewed_composition(provider, id, query, signal)
  }
}

fn acquire_reviewed_composition(
  provider: SseProvider,
  id: String,
  query: sse_query.Query,
  signal,
) -> Promise(tool.ToolResult) {
  case provider {
    SseInvalidConfiguration(message) ->
      reject_sse("provider_configuration_invalid", message)
    SseReady(access, runtime) ->
      case sse_request.industry_composition(access, query) {
        Error(_) ->
          reject_sse(
            "invalid_sse_request",
            "Official SSE industry-composition request could not be constructed safely",
          )
        Ok(request) -> {
          use outcome <- promise.await(sse_runtime.send(
            runtime,
            id,
            request,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(error) ->
              reject_sse(
                "sse_composition_request_failed",
                "Official SSE industry-composition request failed safely: "
                  <> string.inspect(error),
              )
            Ok(response) -> {
              let status = http_response.status(response)
              case status >= 200 && status < 300 {
                False ->
                  reject_sse(
                    "sse_composition_http_error",
                    "Official SSE industry-composition request returned HTTP "
                      <> int.to_string(status),
                  )
                True -> {
                  let body = http_response.body(response)
                  case
                    sse_composition.decode(body, for: query),
                    hash.text(body)
                  {
                    Error(_), _ ->
                      reject_sse(
                        "invalid_sse_composition_response",
                        "Official SSE industry-composition response was invalid, incomplete, identity-conflicting, or did not cover the exact reviewed member count",
                      )
                    _, Error(_) ->
                      reject_sse(
                        "sse_composition_receipt_failed",
                        "Official SSE industry-composition response could not be content-bound",
                      )
                    Ok(value), Ok(digest) ->
                      tool.text_result(
                        live_composition.content(query, value),
                        live_composition.details(
                          query,
                          value,
                          environment.now_milliseconds(),
                          http_response.byte_length(response),
                          provenance_identity.sha256_value(digest),
                        ),
                      )
                      |> promise.resolve
                  }
                }
              }
            }
          }
        }
      }
  }
}

fn reject_sse(code: String, message: String) -> Promise(value) {
  tool.reject_typed(
    code,
    message,
    json.object([
      #("provider", json.string("Shanghai Stock Exchange")),
      #("fallbackAttempted", json.bool(False)),
    ]),
  )
}

fn register_inspect(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "cn_index_records",
    "Inspect CN index identities and membership",
    "Read and validate one exact content-bound cn research packet from a caller-owned regular UTF-8 file; return compact source facts, omissions, and stable record handles without interpretation",
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
    "cn_index_record",
    "Drill one CN index identities and membership record",
    "Reread the same exact content-bound import and return one complete record with source fields and correction lineage",
    "Use the packet hash and recordId returned by cn_index_records; no latest-record or preferred-source choice is made",
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

fn constituent_schema() -> schema.Schema {
  schema.object([
    schema.Required("venue", schema.string_enum(["sse"])),
    schema.Required("code", bounded_string(6, 6)),
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

fn constituent_decoder() -> decode.Decoder(ConstituentInput) {
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  decode.success(ConstituentInput(venue, code))
}
