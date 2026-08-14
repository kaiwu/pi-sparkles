import finance_cache_contract as cache
import finance_cache_contract/http as cache_http
import finance_core/time
import finance_eastmoney
import finance_eastmoney/history as eastmoney_history
import finance_eastmoney/query as eastmoney_query
import finance_eastmoney/request as eastmoney_request
import finance_eastmoney/runtime as eastmoney_runtime
import finance_http/request as http_request
import finance_http/response as http_response
import finance_http/transport
import finance_provenance/hash
import finance_tushare
import finance_tushare/daily as tushare_daily
import finance_tushare/query as tushare_query
import finance_tushare/request as tushare_request
import finance_tushare/runtime as tushare_runtime
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/result
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_stock_history/domain
import pi_sparkles_cn_stock_history/effect/environment

type EastmoneyProvider {
  EastmoneyReady(finance_eastmoney.Access, eastmoney_runtime.Runtime)
  EastmoneyUnavailable(String)
}

type TushareProvider {
  TushareReady(finance_tushare.Access, tushare_runtime.Runtime)
  TushareUnavailable(String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let eastmoney = eastmoney_provider()
  let tushare = tushare_provider()
  tool.register_compact(
    api,
    "cn_stock_history",
    "CN stock history",
    "Fetch bounded raw unadjusted daily bars for one exact mainland A-share through an explicitly selected Eastmoney or Tushare Pro adapter with a content-bound canonical receipt",
    "Call directly when the caller supplies an exact mainland venue and code; do not repeat symbol search or CNINFO discovery. Provider failure never triggers fallback, gap filling, adjustment, or suspension inference",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, plan, signal, _updates, _ctx) {
      let cancellation = transport.from_abort_signal(raw.dynamic(signal))
      case domain.provider(plan) {
        domain.Eastmoney ->
          fetch_eastmoney(api, eastmoney, plan, id, cancellation)
        domain.Tushare -> fetch_tushare(api, tushare, plan, id, cancellation)
      }
    },
  )
  promise.resolve(Nil)
}

fn eastmoney_provider() -> EastmoneyProvider {
  case
    finance_eastmoney.access(
      environment.eastmoney_product(),
      environment.eastmoney_contact(),
    )
  {
    Error(_) ->
      EastmoneyUnavailable(
        "Selected Eastmoney adapter requires AGENT_CONTACT; no fallback was attempted",
      )
    Ok(access) ->
      case eastmoney_runtime.new(access) {
        Ok(runtime) -> EastmoneyReady(access, runtime)
        Error(_) ->
          EastmoneyUnavailable(
            "Selected Eastmoney adapter could not initialize safely; no fallback was attempted",
          )
      }
  }
}

fn tushare_provider() -> TushareProvider {
  case finance_tushare.access(environment.tushare_token()) {
    Error(_) ->
      TushareUnavailable(
        "Selected Tushare adapter requires a valid caller-owned TUSHARE_TOKEN; no fallback was attempted",
      )
    Ok(access) ->
      case tushare_runtime.new(access) {
        Ok(runtime) -> TushareReady(access, runtime)
        Error(_) ->
          TushareUnavailable(
            "Selected Tushare adapter could not initialize safely; no fallback was attempted",
          )
      }
  }
}

fn fetch_eastmoney(
  api: pi.ExtensionApi,
  provider: EastmoneyProvider,
  plan: domain.Plan,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(tool.ToolResult) {
  case provider {
    EastmoneyUnavailable(reason) -> tool.reject(reason)
    EastmoneyReady(access, runtime) ->
      case domain.eastmoney_plan(plan) {
        Error(error) -> tool.reject(domain.error_message(error))
        Ok(provider_plan) ->
          case eastmoney_request.history(access, provider_plan) {
            Error(_) -> tool.reject("Eastmoney history request was invalid")
            Ok(request) -> {
              let created_at = environment.now_milliseconds()
              use outcome <- promise.await(eastmoney_runtime.send(
                runtime,
                id,
                request,
                cancellation,
              ))
              case checked_response(outcome, "Eastmoney") {
                Error(message) -> tool.reject(message)
                Ok(response) -> {
                  let body = http_response.body(response)
                  case
                    eastmoney_history.decode(body, for: provider_plan),
                    capture_metadata(body, response)
                  {
                    Ok(value), Ok(#(retrieved_at, digest)) -> {
                      let assembled =
                        domain.assemble_eastmoney(
                          plan,
                          value,
                          retrieved_at,
                          http_response.byte_length(response),
                          digest,
                        )
                      case assembled {
                        Error(error) -> tool.reject(domain.error_message(error))
                        Ok(output) -> {
                          record_cache(
                            api,
                            request,
                            response,
                            created_at,
                            retrieved_at,
                            "eastmoney",
                            eastmoney_history_source(provider_plan),
                            86_400_000,
                            "public_local_analysis_no_redistribution",
                            "eastmoney_provider_terms",
                          )
                          render(output)
                        }
                      }
                    }
                    Error(_), _ ->
                      tool.reject(
                        "Eastmoney returned invalid or mismatched daily bars",
                      )
                    _, Error(message) -> tool.reject(message)
                  }
                }
              }
            }
          }
      }
  }
}

fn fetch_tushare(
  api: pi.ExtensionApi,
  provider: TushareProvider,
  plan: domain.Plan,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(tool.ToolResult) {
  case provider {
    TushareUnavailable(reason) -> tool.reject(reason)
    TushareReady(access, runtime) ->
      case domain.tushare_plan(plan) {
        Error(error) -> tool.reject(domain.error_message(error))
        Ok(provider_plan) ->
          case tushare_request.daily(access, provider_plan) {
            Error(_) -> tool.reject("Tushare daily request was invalid")
            Ok(request) -> {
              let created_at = environment.now_milliseconds()
              use outcome <- promise.await(tushare_runtime.send(
                runtime,
                id,
                request,
                cancellation,
              ))
              case checked_response(outcome, "Tushare") {
                Error(message) -> tool.reject(message)
                Ok(response) -> {
                  let body = http_response.body(response)
                  case
                    tushare_daily.decode(body, for: provider_plan),
                    capture_metadata(body, response)
                  {
                    Ok(value), Ok(#(retrieved_at, digest)) -> {
                      let assembled =
                        domain.assemble_tushare(
                          plan,
                          value,
                          retrieved_at,
                          http_response.byte_length(response),
                          digest,
                        )
                      case assembled {
                        Error(error) -> tool.reject(domain.error_message(error))
                        Ok(output) -> {
                          record_cache(
                            api,
                            request,
                            response,
                            created_at,
                            retrieved_at,
                            "tushare",
                            tushare_daily_source(provider_plan),
                            86_400_000,
                            "caller_entitled_local_analysis_no_redistribution",
                            "tushare_pro_terms",
                          )
                          render(output)
                        }
                      }
                    }
                    Error(error), _ ->
                      tool.reject(tushare_daily.error_message(error))
                    _, Error(message) -> tool.reject(message)
                  }
                }
              }
            }
          }
      }
  }
}

fn checked_response(
  outcome,
  provider: String,
) -> Result(http_response.Response, String) {
  case outcome {
    Error(error) ->
      Error(provider <> " request failed safely: " <> string.inspect(error))
    Ok(response) -> {
      let status = http_response.status(response)
      case status >= 200 && status < 300 {
        True -> Ok(response)
        False ->
          Error(provider <> " request returned HTTP " <> int.to_string(status))
      }
    }
  }
}

fn capture_metadata(body: String, _response: http_response.Response) {
  case time.instant(environment.now_milliseconds()), hash.text(body) {
    Ok(retrieved_at), Ok(digest) -> Ok(#(retrieved_at, digest))
    Error(_), _ -> Error("retrieval clock was invalid")
    _, Error(_) -> Error("response content receipt could not be hashed")
  }
}

fn render(output: domain.Output) -> Promise(tool.ToolResult) {
  tool.text_result(domain.model_content(output), domain.details(output))
  |> promise.resolve
}

fn record_cache(
  api: pi.ExtensionApi,
  request: http_request.Request,
  response: http_response.Response,
  created_at: Int,
  retrieved_at: time.Instant,
  provider: String,
  source: String,
  ttl_milliseconds: Int,
  entitlement: String,
  licence: String,
) -> Nil {
  let retrieved = time.unix_milliseconds(retrieved_at)
  case
    cache_http.capture(
      request,
      response,
      provider,
      source,
      created_at,
      retrieved,
      retrieved + ttl_milliseconds,
      entitlement,
      licence,
      "schema_validated",
    )
  {
    Error(_) -> Nil
    Ok(entry) ->
      pi.append_entry(
        api,
        cache.event_type,
        raw.dynamic(cache.encode_event(cache.stored(entry))),
      )
  }
}

fn eastmoney_history_source(plan: eastmoney_query.HistoryQuery) -> String {
  eastmoney_query.history_source_reference(plan)
}

fn tushare_daily_source(plan: tushare_query.DailyQuery) -> String {
  tushare_query.daily_source_reference(plan)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn"])),
    schema.Required("provider", schema.string_enum(["eastmoney", "tushare"])),
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
    schema.Required("shareClass", schema.string_enum(["a_share"])),
    schema.Required(
      "identityEvidenceId",
      schema.string() |> schema.with_string_length(1, 256),
    ),
    schema.Required(
      "startDate",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Required(
      "endDate",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Optional(
      "limit",
      schema.integer() |> schema.with_number_range(1.0, 1000.0),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(domain.Plan) {
  use track <- decode.field("track", decode.string)
  use provider <- decode.field("provider", decode.string)
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  use evidence <- decode.field("identityEvidenceId", decode.string)
  use start_text <- decode.field("startDate", decode.string)
  use end_text <- decode.field("endDate", decode.string)
  use limit <- decode.optional_field("limit", 250, decode.int)
  let assert Ok(placeholder_date) = time.date(2026, 1, 1)
  let assert Ok(placeholder) =
    domain.plan(
      "cn",
      "eastmoney",
      "sse",
      "600000",
      "a_share",
      "placeholder",
      placeholder_date,
      placeholder_date,
      250,
    )
  case parse_date(start_text), parse_date(end_text) {
    Ok(start_date), Ok(end_date) ->
      case
        domain.plan(
          track,
          provider,
          venue,
          code,
          share_class,
          evidence,
          start_date,
          end_date,
          limit,
        )
      {
        Ok(value) -> decode.success(value)
        Error(error) -> decode.failure(placeholder, domain.error_message(error))
      }
    _, _ -> decode.failure(placeholder, "valid inclusive Gregorian date range")
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
