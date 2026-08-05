import finance_cn_identity/identity
import finance_core/time
import finance_eastmoney
import finance_eastmoney/history
import finance_eastmoney/query
import finance_eastmoney/quote
import finance_eastmoney/request as provider_request
import finance_eastmoney/runtime
import finance_http/response as http_response
import finance_http/transport
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_market_data/effect/environment

pub type QuoteInput {
  QuoteInput(market: query.Market, code: String)
}

pub type HistoryInput {
  HistoryInput(
    market: query.Market,
    code: String,
    start_date: time.Date,
    end_date: time.Date,
    limit: Int,
  )
}

type Provider {
  Ready(access: finance_eastmoney.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "cn_stock_quote",
    "CN raw vendor quote",
    "Fetch an exact-code Eastmoney mainland A-share quote after an explicit SSE/SZSE/BSE choice; expose exact scaled prices, provider timestamp, retrieval time, unknown latency/rights, and unverified volume semantics",
    "Get a bounded current or delayed raw vendor quote for an independently proven mainland A-share identity",
    tool.parameters(quote_schema(), quote_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case query.quote(finance_track.Cn, input.market, input.code) {
            Error(_) ->
              tool.reject("Invalid explicit CN Eastmoney quote identity")
            Ok(plan) -> {
              use outcome <- promise.await(fetch_quote(
                provider_runtime,
                access,
                plan,
                id,
                transport.from_abort_signal(raw.dynamic(signal)),
              ))
              case outcome {
                Error(message) -> tool.reject(message)
                Ok(value) ->
                  tool.text_result(
                    render_quote(input, value),
                    quote_json(input, value, environment.now_milliseconds()),
                  )
                  |> promise.resolve
              }
            }
          }
      }
    },
  )
  tool.register(
    api,
    "cn_stock_history",
    "CN raw vendor history",
    "Fetch bounded Eastmoney raw unadjusted mainland A-share daily bars for an explicit SSE/SZSE/BSE identity; preserve every numeric source lexeme and visible provider/rights limits",
    "Get raw unadjusted daily bars without inventing suspensions or adjustment factors",
    tool.parameters(history_schema(), history_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case
            query.history(
              finance_track.Cn,
              input.market,
              input.code,
              input.start_date,
              input.end_date,
              input.limit,
            )
          {
            Error(_) ->
              tool.reject("Invalid explicit CN Eastmoney history query")
            Ok(plan) -> {
              use outcome <- promise.await(fetch_history(
                provider_runtime,
                access,
                plan,
                id,
                transport.from_abort_signal(raw.dynamic(signal)),
              ))
              case outcome {
                Error(message) -> tool.reject(message)
                Ok(value) ->
                  tool.text_result(
                    render_history(input, value),
                    history_json(input, value, environment.now_milliseconds()),
                  )
                  |> promise.resolve
              }
            }
          }
      }
    },
  )
  promise.resolve(Nil)
}

fn provider() -> Provider {
  case finance_eastmoney.access(environment.product(), environment.contact()) {
    Error(_) ->
      InvalidConfiguration(
        "Eastmoney access requires EASTMONEY_USER_AGENT_CONTACT (for example ops@example.com); EASTMONEY_USER_AGENT_PRODUCT is optional",
      )
    Ok(access) ->
      case runtime.new(access) {
        Ok(value) -> Ready(access, value)
        Error(_) ->
          InvalidConfiguration(
            "Eastmoney bounded runtime could not initialize safely",
          )
      }
  }
}

fn fetch_quote(provider_runtime, access, plan, id, cancellation) {
  case provider_request.quote(access, plan) {
    Error(_) -> promise.resolve(Error("Eastmoney quote request was invalid"))
    Ok(request) -> {
      use outcome <- promise.await(runtime.send(
        provider_runtime,
        id,
        request,
        cancellation,
      ))
      case checked_body(outcome, "quote") {
        Error(message) -> promise.resolve(Error(message))
        Ok(body) ->
          case quote.decode(body, for: plan) {
            Ok(value) -> promise.resolve(Ok(value))
            Error(_) ->
              promise.resolve(Error(
                "Eastmoney returned an invalid or mismatched quote",
              ))
          }
      }
    }
  }
}

fn fetch_history(provider_runtime, access, plan, id, cancellation) {
  case provider_request.history(access, plan) {
    Error(_) -> promise.resolve(Error("Eastmoney history request was invalid"))
    Ok(request) -> {
      use outcome <- promise.await(runtime.send(
        provider_runtime,
        id,
        request,
        cancellation,
      ))
      case checked_body(outcome, "history") {
        Error(message) -> promise.resolve(Error(message))
        Ok(body) ->
          case history.decode(body, for: plan) {
            Ok(value) -> promise.resolve(Ok(value))
            Error(_) ->
              promise.resolve(Error(
                "Eastmoney returned invalid or mismatched daily bars",
              ))
          }
      }
    }
  }
}

fn checked_body(outcome, resource: String) -> Result(String, String) {
  case outcome {
    Error(error) ->
      Error(
        "Eastmoney "
        <> resource
        <> " request failed safely: "
        <> string.inspect(error),
      )
    Ok(response) -> {
      let status = http_response.status(response)
      case status >= 200 && status < 300 {
        True -> Ok(http_response.body(response))
        False ->
          Error(
            "Eastmoney "
            <> resource
            <> " request returned HTTP "
            <> int.to_string(status),
          )
      }
    }
  }
}

fn quote_schema() -> schema.Schema {
  schema.object([
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
  ])
}

fn history_schema() -> schema.Schema {
  schema.object([
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
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

fn quote_decoder() -> decode.Decoder(QuoteInput) {
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  case market_from_name(venue) {
    Ok(market) -> decode.success(QuoteInput(market, code))
    Error(_) ->
      decode.failure(QuoteInput(query.CnSse, "000001"), "valid CN venue")
  }
}

fn history_decoder() -> decode.Decoder(HistoryInput) {
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  use start <- decode.field("startDate", decode.string)
  use end <- decode.field("endDate", decode.string)
  use limit <- decode.optional_field("limit", 250, decode.int)
  let assert Ok(placeholder) = time.date(2026, 1, 1)
  case market_from_name(venue), parse_date(start), parse_date(end) {
    Ok(market), Ok(start_date), Ok(end_date) ->
      decode.success(HistoryInput(market, code, start_date, end_date, limit))
    _, _, _ ->
      decode.failure(
        HistoryInput(query.CnSse, "000001", placeholder, placeholder, 250),
        "valid CN history query",
      )
  }
}

fn market_from_name(value: String) -> Result(query.Market, Nil) {
  case value {
    "sse" -> Ok(query.CnSse)
    "szse" -> Ok(query.CnSzse)
    "bse" -> Ok(query.CnBse)
    _ -> Error(Nil)
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

fn result_context(
  market: query.Market,
  scope: String,
) -> track_context.Context {
  let venue = case market {
    query.CnSse -> identity.Sse
    query.CnSzse -> identity.Szse
    query.CnBse -> identity.Bse
    _ -> identity.Sse
  }
  let assert Ok(zone) = time.timezone("Asia/Shanghai")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Cn,
      market_scope: scope,
      venue_mic: Some(identity.venue_mic(venue)),
      board: None,
      timezone: Some(zone),
      source_language: "zh-CN",
      providers: ["eastmoney"],
      entitlement: "public_web_local_analysis",
      limitations: limitations(),
    )
  value
}

fn limitations() -> List(String) {
  [
    "vendor_origin_not_exchange_evidence",
    "a_share_identity_and_cny_scope_must_be_independently_proven",
    "realtime_and_delay_status_unknown",
    "provider_volume_unit_not_verified",
    "service_level_and_redistribution_rights_unknown",
    "no_stale_fallback",
  ]
}

fn render_quote(input: QuoteInput, value: quote.Quote) -> String {
  "CN track | Eastmoney raw quote | "
  <> query.market_name(input.market)
  <> " "
  <> quote.code(value)
  <> " "
  <> quote.name(value)
  <> " | last "
  <> quote.last(value)
  <> " declared CNY | latency unknown"
}

fn render_history(input: HistoryInput, value: history.History) -> String {
  "CN track | Eastmoney raw unadjusted daily history | "
  <> query.market_name(input.market)
  <> " "
  <> history.code(value)
  <> " "
  <> history.name(value)
  <> " | "
  <> int.to_string(list.length(history.bars(value)))
  <> " bars"
}

fn quote_json(
  input: QuoteInput,
  value: quote.Quote,
  retrieved_at: Int,
) -> json.Json {
  json.object(
    list.append(
      track_json.result_fields(result_context(input.market, "cn_stock_quote")),
      [
        #("provider", json.string("eastmoney")),
        #("route", json.string("direct")),
        #("market", json.string(query.market_name(input.market))),
        #("code", json.string(quote.code(value))),
        #("name", json.string(quote.name(value))),
        #("declaredCurrency", json.string("CNY")),
        #("last", json.string(quote.last(value))),
        #("open", json.string(quote.open(value))),
        #("high", json.string(quote.high(value))),
        #("low", json.string(quote.low(value))),
        #("previousClose", json.string(quote.previous_close(value))),
        #("providerVolume", json.int(quote.provider_volume(value))),
        #("providerVolumeUnit", json.null()),
        #("priceLimitUp", option_json(quote.price_limit_up(value))),
        #("priceLimitDown", option_json(quote.price_limit_down(value))),
        #("providerUnixSeconds", json.int(quote.provider_unix_seconds(value))),
        #("retrievedAtUnixMilliseconds", json.int(retrieved_at)),
        #("latency", json.string("unknown")),
        #("entitlement", json.string("public_web_local_analysis")),
        #("redistribution", json.string("unknown")),
        #("limitations", json.array(limitations(), json.string)),
      ],
    ),
  )
}

fn history_json(
  input: HistoryInput,
  value: history.History,
  retrieved_at: Int,
) -> json.Json {
  json.object(
    list.append(
      track_json.result_fields(result_context(input.market, "cn_stock_history")),
      [
        #("provider", json.string("eastmoney")),
        #("route", json.string("direct")),
        #("market", json.string(query.market_name(input.market))),
        #("code", json.string(history.code(value))),
        #("name", json.string(history.name(value))),
        #("declaredCurrency", json.string("CNY")),
        #("frequency", json.string("daily")),
        #("adjustment", json.string("raw_unadjusted_fqt_0")),
        #("retrievedAtUnixMilliseconds", json.int(retrieved_at)),
        #("bars", json.array(history.bars(value), bar_json)),
        #("entitlement", json.string("public_web_local_analysis")),
        #("redistribution", json.string("unknown")),
        #("limitations", json.array(limitations(), json.string)),
      ],
    ),
  )
}

fn bar_json(value: history.Bar) -> json.Json {
  json.object([
    #("date", json.string(date_text(history.date(value)))),
    #("open", json.string(history.open(value))),
    #("close", json.string(history.close(value))),
    #("high", json.string(history.high(value))),
    #("low", json.string(history.low(value))),
    #("volume", json.string(history.volume(value))),
    #("amount", json.string(history.amount(value))),
    #("amplitudePercent", json.string(history.amplitude_percent(value))),
    #("changePercent", json.string(history.change_percent(value))),
    #("change", json.string(history.change(value))),
    #("turnoverPercent", json.string(history.turnover_percent(value))),
  ])
}

fn option_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn date_text(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
