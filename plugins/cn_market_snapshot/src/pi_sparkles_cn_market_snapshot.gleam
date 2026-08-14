import finance_core/time
import finance_eastmoney
import finance_eastmoney/history as provider_history
import finance_eastmoney/overview as provider_overview
import finance_eastmoney/query as provider_query
import finance_eastmoney/request as provider_request
import finance_eastmoney/runtime as provider_runtime
import finance_http/response as http_response
import finance_http/transport
import finance_local_import
import finance_provenance/hash
import finance_provenance/identity as provenance_identity
import finance_quant/cn
import finance_quant/common
import finance_track
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_market_snapshot/effect/environment
import pi_sparkles_cn_market_snapshot/overview
import pi_sparkles_cn_market_snapshot/sector_trends

pub type Input {
  Input(path: String, expected_sha256: String, maximum_bytes: Int)
}

pub type SectorTrendInput {
  SectorTrendInput(start_date: time.Date, end_date: time.Date)
}

type Provider {
  Ready(finance_eastmoney.Access, provider_runtime.Runtime)
  InvalidConfiguration(String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "cn_market_snapshot",
    "Calculate an exact CN market snapshot",
    "Verify a content-bound SSE, SZSE, or BSE member packet and calculate observed breadth, exact CNY turnover, caller-defined group summaries, duplicate identities, coverage, and unresolved rows",
    "The caller supplies every identity, source, coverage, price, and group fact; this tool performs no acquisition, completion, flow inference, ranking, forecast, recommendation, or trade action",
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
  tool.register_compact(
    api,
    "cn_market_overview",
    "Acquire current Shanghai/Shenzhen market overview",
    "Fetch one bounded Eastmoney batch containing four reviewed CN benchmark snapshots plus provider index-associated SSE/SZSE breadth counts, exact numeric lexemes, a content receipt, and explicit evidence gaps",
    "Use this for today's overall Shanghai/Shenzhen market request. It replaces index calls to cn_raw_vendor_quote/history and does not justify intraday-ordering, fund-flow, sector-rotation, full-membership, or turnover-trend claims",
    tool.parameters(schema.object([]), decode.success(Nil)),
    tool.Parallel,
    fn(id, _input, signal, _updates, _ctx) {
      acquire_overview(provider, id, signal)
    },
  )
  tool.register_compact(
    api,
    "cn_sector_trends",
    "Compare CN industry-sector price trends",
    "Acquire the exact pinned 11-index CSI 800 level-one industry profile through bounded Eastmoney daily-history requests and mechanically calculate latest-session, five-session, and requested-window relative returns",
    "Use once for broad CN industry-sector or sector-rotation questions. Supply the requested analysis window; do not probe guessed sector codes through cn_raw_vendor_history. Results are price-only and never establish fund flow, constituent breadth, causal rotation, theme exposure, or trend reversal",
    tool.parameters(sector_trend_schema(), sector_trend_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      acquire_sector_trends(provider, id, input, signal)
    },
  )
  promise.resolve(Nil)
}

fn provider() -> Provider {
  case finance_eastmoney.access(environment.product(), environment.contact()) {
    Error(_) ->
      InvalidConfiguration(
        "Selected Eastmoney CN market adapters require AGENT_CONTACT; no fallback was attempted",
      )
    Ok(access) ->
      case provider_runtime.new(access) {
        Ok(runtime) -> Ready(access, runtime)
        Error(_) ->
          InvalidConfiguration(
            "Selected Eastmoney CN market adapters could not initialize safely; no fallback was attempted",
          )
      }
  }
}

fn acquire_sector_trends(
  provider: Provider,
  id: String,
  input: SectorTrendInput,
  signal,
) {
  case provider {
    InvalidConfiguration(message) ->
      reject_sector("provider_configuration_invalid", message)
    Ready(access, runtime) -> {
      use outcome <- promise.await(
        fetch_sector_series(
          access,
          runtime,
          id,
          input,
          query_sector_indices: provider_query.cn_sector_indices(),
          cancellation: transport.from_abort_signal(raw.dynamic(signal)),
          acquired: [],
          receipt_lines: [],
        ),
      )
      case outcome {
        Error(message) -> reject_sector("sector_acquisition_failed", message)
        Ok(#(series, receipt_lines)) ->
          case hash.text(receipt_lines |> list.reverse |> string.join("\n")) {
            Error(_) ->
              reject_sector(
                "receipt_hash_failed",
                "CN sector response manifest could not be hashed",
              )
            Ok(manifest_digest) ->
              case
                sector_trends.assemble(
                  series,
                  input.start_date,
                  input.end_date,
                  environment.now_milliseconds(),
                  manifest_digest,
                )
              {
                Error(error) ->
                  reject_sector(
                    "sector_assembly_failed",
                    sector_trends.error_message(error),
                  )
                Ok(output) ->
                  tool.text_result(
                    sector_trends.content(output),
                    sector_trends.details(output),
                  )
                  |> promise.resolve
              }
          }
      }
    }
  }
}

fn fetch_sector_series(
  access: finance_eastmoney.Access,
  runtime: provider_runtime.Runtime,
  id: String,
  input: SectorTrendInput,
  query_sector_indices indices: List(provider_query.CnSectorIndex),
  cancellation cancellation: transport.Cancellation,
  acquired acquired: List(sector_trends.AcquiredSeries),
  receipt_lines receipt_lines: List(String),
) -> Promise(
  Result(#(List(sector_trends.AcquiredSeries), List(String)), String),
) {
  case indices {
    [] -> promise.resolve(Ok(#(list.reverse(acquired), receipt_lines)))
    [index, ..rest] ->
      case
        provider_query.cn_sector_history(
          index,
          input.start_date,
          input.end_date,
          64,
        )
      {
        Error(_) ->
          promise.resolve(Error(
            "CSI sector history plan was invalid for "
            <> provider_query.cn_sector_code(index),
          ))
        Ok(plan) ->
          case provider_request.history(access, plan) {
            Error(_) ->
              promise.resolve(Error(
                "Eastmoney sector request was invalid for "
                <> provider_query.cn_sector_code(index),
              ))
            Ok(request) -> {
              use outcome <- promise.await(provider_runtime.send(
                runtime,
                id <> ":" <> provider_query.cn_sector_code(index),
                request,
                cancellation,
              ))
              case outcome {
                Error(error) ->
                  promise.resolve(Error(
                    "Eastmoney sector request failed safely for "
                    <> provider_query.cn_sector_code(index)
                    <> ": "
                    <> string.inspect(error),
                  ))
                Ok(response) -> {
                  let status = http_response.status(response)
                  case status >= 200 && status < 300 {
                    False ->
                      promise.resolve(Error(
                        "Eastmoney sector request returned HTTP "
                        <> int.to_string(status)
                        <> " for "
                        <> provider_query.cn_sector_code(index),
                      ))
                    True -> {
                      let body = http_response.body(response)
                      case
                        provider_history.decode(body, for: plan),
                        hash.text(body)
                      {
                        Error(_), _ ->
                          promise.resolve(Error(
                            "Eastmoney returned invalid or identity-mismatched sector bars for "
                            <> provider_query.cn_sector_code(index),
                          ))
                        _, Error(_) ->
                          promise.resolve(Error(
                            "Eastmoney sector response could not be hashed for "
                            <> provider_query.cn_sector_code(index),
                          ))
                        Ok(value), Ok(digest) -> {
                          let line =
                            provider_query.cn_sector_code(index)
                            <> ":"
                            <> provenance_identity.sha256_value(digest)
                          fetch_sector_series(
                            access,
                            runtime,
                            id,
                            input,
                            query_sector_indices: rest,
                            cancellation: cancellation,
                            acquired: [
                              sector_trends.AcquiredSeries(
                                index,
                                value,
                                provider_query.history_source_reference(plan),
                                http_response.byte_length(response),
                                digest,
                              ),
                              ..acquired
                            ],
                            receipt_lines: [line, ..receipt_lines],
                          )
                        }
                      }
                    }
                  }
                }
              }
            }
          }
      }
  }
}

fn reject_sector(code: String, message: String) -> Promise(value) {
  tool.reject_typed(
    code,
    message,
    json.object([
      #("code", json.string(code)),
      #("track", json.string("cn")),
      #("provider", json.string("eastmoney")),
      #("operation", json.string("acquire_cn_sector_trends")),
      #("profileId", json.string(provider_query.cn_sector_profile_id())),
      #("fallbackAttempted", json.bool(False)),
    ]),
  )
}

fn acquire_overview(provider: Provider, id: String, signal) {
  case provider {
    InvalidConfiguration(message) ->
      tool.reject_typed(
        "provider_configuration_invalid",
        message,
        json.object([
          #("code", json.string("provider_configuration_invalid")),
          #("track", json.string("cn")),
          #("provider", json.string("eastmoney")),
          #("fallbackAttempted", json.bool(False)),
        ]),
      )
    Ready(access, runtime) ->
      case provider_query.cn_overview(finance_track.Cn) {
        Error(_) ->
          reject_overview(
            "overview_plan_invalid",
            "CN overview plan was invalid",
          )
        Ok(plan) ->
          case provider_request.cn_overview(access, plan) {
            Error(_) ->
              reject_overview(
                "overview_request_invalid",
                "Eastmoney CN overview request was invalid",
              )
            Ok(request) -> {
              use outcome <- promise.await(provider_runtime.send(
                runtime,
                id,
                request,
                transport.from_abort_signal(raw.dynamic(signal)),
              ))
              case outcome {
                Error(error) ->
                  reject_overview(
                    "provider_request_failed",
                    "Eastmoney CN overview request failed safely: "
                      <> string.inspect(error),
                  )
                Ok(response) ->
                  case http_response.status(response) {
                    status if status >= 200 && status < 300 -> {
                      let body = http_response.body(response)
                      case
                        provider_overview.decode(body, for: plan),
                        hash.text(body)
                      {
                        Ok(value), Ok(digest) ->
                          case
                            overview.assemble(
                              value,
                              environment.now_milliseconds(),
                              http_response.byte_length(response),
                              digest,
                            )
                          {
                            Ok(output) ->
                              tool.text_result(
                                overview.content(output),
                                overview.details(output),
                              )
                              |> promise.resolve
                            Error(error) ->
                              reject_overview(
                                "overview_assembly_failed",
                                overview.error_message(error),
                              )
                          }
                        Error(error), _ ->
                          reject_overview(
                            "provider_decode_failed",
                            "Eastmoney returned an invalid or identity-mismatched CN overview: "
                              <> string.inspect(error),
                          )
                        _, Error(_) ->
                          reject_overview(
                            "receipt_hash_failed",
                            "Eastmoney CN overview response receipt could not be hashed",
                          )
                      }
                    }
                    status ->
                      reject_overview(
                        "provider_http_error",
                        "Eastmoney CN overview returned HTTP "
                          <> int.to_string(status),
                      )
                  }
              }
            }
          }
      }
  }
}

fn reject_overview(code: String, message: String) -> Promise(value) {
  tool.reject_typed(
    code,
    message,
    json.object([
      #("code", json.string(code)),
      #("track", json.string("cn")),
      #("provider", json.string("eastmoney")),
      #("operation", json.string("acquire_current_overview")),
      #("fallbackAttempted", json.bool(False)),
    ]),
  )
}

fn finish(
  outcome: finance_local_import.Outcome,
  expected: String,
) -> Promise(tool.ToolResult) {
  case outcome {
    finance_local_import.Loaded(text, _) ->
      case cn.market_snapshot(text, expected) {
        Ok(value) ->
          tool.text_result(common.summary(value), common.details(value))
          |> promise.resolve
        Error(error) -> tool.reject(common.error_message(error))
      }
    finance_local_import.Truncated(_, total) ->
      tool.reject(
        "CN market snapshot packet exceeds maximumBytes: "
        <> int.to_string(total),
      )
    finance_local_import.Cancelled ->
      tool.reject("CN market snapshot import was cancelled")
    finance_local_import.Missing ->
      tool.reject("CN market snapshot packet was not found")
    finance_local_import.InvalidUtf8 ->
      tool.reject("CN market snapshot packet requires strict UTF-8")
    finance_local_import.Failure(code) ->
      tool.reject("CN market snapshot import failed safely: " <> code)
    finance_local_import.InvalidResult ->
      tool.reject("CN market snapshot import returned an invalid effect result")
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

fn sector_trend_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "startDate",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Required(
      "endDate",
      schema.string() |> schema.with_string_length(10, 10),
    ),
  ])
}

fn sector_trend_decoder() -> decode.Decoder(SectorTrendInput) {
  use start <- decode.field("startDate", decode.string)
  use end <- decode.field("endDate", decode.string)
  let assert Ok(placeholder) = time.date(2026, 1, 1)
  case parse_date(start), parse_date(end) {
    Ok(start_date), Ok(end_date) ->
      decode.success(SectorTrendInput(start_date, end_date))
    _, _ ->
      decode.failure(
        SectorTrendInput(placeholder, placeholder),
        "valid CN sector trend date window",
      )
  }
}

fn parse_date(value: String) -> Result(time.Date, Nil) {
  case string.split(value, "-") {
    [year, month, day] -> {
      use year <- result.try(int.parse(year) |> result.map_error(fn(_) { Nil }))
      use month <- result.try(
        int.parse(month) |> result.map_error(fn(_) { Nil }),
      )
      use day <- result.try(int.parse(day) |> result.map_error(fn(_) { Nil }))
      time.date(year, month, day) |> result.map_error(fn(_) { Nil })
    }
    _ -> Error(Nil)
  }
}
