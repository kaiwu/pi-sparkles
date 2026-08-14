import finance_cache_contract as cache
import finance_cache_contract/http as cache_http
import finance_core/time
import finance_eastmoney
import finance_eastmoney/quote as eastmoney_quote
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
import pi_sparkles_cn_stock_quote/domain
import pi_sparkles_cn_stock_quote/effect/environment

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
  tool.register(
    api,
    "cn_stock_quote",
    "CN stock price snapshot",
    "Fetch one dated mainland A-share price snapshot through an explicitly selected Eastmoney quote or Tushare Pro end-of-day adapter while retaining unavailable fields and a content receipt",
    "Call directly when the caller supplies an exact mainland venue and code; do not repeat symbol search or CNINFO discovery. Tushare daily is labelled end-of-day rather than realtime; no selected-provider failure triggers fallback",
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

fn fetch_eastmoney(api, provider, plan, id, cancellation) {
  case provider {
    EastmoneyUnavailable(reason) -> tool.reject(reason)
    EastmoneyReady(access, runtime) ->
      case domain.eastmoney_plan(plan) {
        Error(error) -> tool.reject(domain.error_message(error))
        Ok(provider_plan) ->
          case eastmoney_request.quote(access, provider_plan) {
            Error(_) -> tool.reject("Eastmoney quote request was invalid")
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
                    eastmoney_quote.decode(body, for: provider_plan),
                    metadata(body)
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
                            http_request.origin(request)
                              <> http_request.path(request),
                            300_000,
                            "public_local_analysis_no_redistribution",
                            "eastmoney_provider_terms",
                          )
                          render(output)
                        }
                      }
                    }
                    Error(_), _ ->
                      tool.reject(
                        "Eastmoney returned an invalid or mismatched quote",
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

fn fetch_tushare(api, provider, plan, id, cancellation) {
  case provider {
    TushareUnavailable(reason) -> tool.reject(reason)
    TushareReady(access, runtime) ->
      case domain.tushare_plan(plan) {
        Error(error) -> tool.reject(domain.error_message(error))
        Ok(provider_plan) ->
          case tushare_request.daily(access, provider_plan) {
            Error(_) ->
              tool.reject("Tushare daily snapshot request was invalid")
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
                    metadata(body)
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
                            tushare_query.daily_source_reference(provider_plan),
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

fn metadata(body: String) {
  case time.instant(environment.now_milliseconds()), hash.text(body) {
    Ok(retrieved_at), Ok(digest) -> Ok(#(retrieved_at, digest))
    Error(_), _ -> Error("retrieval clock was invalid")
    _, Error(_) -> Error("response content receipt could not be hashed")
  }
}

fn render(output: domain.Output) -> Promise(tool.ToolResult) {
  tool.text_result(domain.summary(output), domain.details(output))
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
      "asOfDate",
      schema.string() |> schema.with_string_length(10, 10),
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
  use date_text <- decode.field("asOfDate", decode.string)
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
    )
  case parse_date(date_text) {
    Error(_) -> decode.failure(placeholder, "valid Gregorian asOfDate")
    Ok(date) ->
      case
        domain.plan(track, provider, venue, code, share_class, evidence, date)
      {
        Ok(value) -> decode.success(value)
        Error(error) -> decode.failure(placeholder, domain.error_message(error))
      }
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
