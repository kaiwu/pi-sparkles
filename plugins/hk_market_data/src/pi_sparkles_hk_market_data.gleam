import finance_core/time
import finance_eastmoney
import finance_eastmoney/history
import finance_eastmoney/query
import finance_eastmoney/quote
import finance_eastmoney/request as provider_request
import finance_eastmoney/runtime
import finance_hk_identity/identity
import finance_http/response as http_response
import finance_http/transport
import finance_provenance/hash
import finance_provenance/identity as provenance_identity
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
import pi_sparkles_hk_market_data/effect/environment

pub type Currency {
  Hkd
  Cny
  Usd
}

pub type QuoteInput {
  QuoteInput(code: String, currency: Currency)
}

pub type HistoryInput {
  HistoryInput(
    code: String,
    currency: Currency,
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
  tool.register_compact(
    api,
    "hk_stock_quote",
    "HK raw vendor quote",
    "Fetch an exact five-digit Eastmoney Hong Kong quote with a mandatory independently verified declared currency; use current quote evidence by default for ordinary buy-now, sell-timing, entry, exit, stop, or target questions even when the user does not explicitly request tools; expose exact scaled prices, timestamps, unknown latency/rights, and unverified volume semantics",
    "Get a bounded current or delayed raw vendor quote for a current-price-dependent opinion without assuming every HK listing trades in HKD",
    tool.parameters(quote_schema(), quote_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case query.quote(finance_track.Hk, query.Hk, input.code) {
            Error(_) -> tool.reject("Invalid exact HK Eastmoney quote identity")
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
  tool.register_compact(
    api,
    "hk_stock_history",
    "HK raw vendor history",
    "Fetch bounded Eastmoney raw unadjusted Hong Kong daily bars with a mandatory independently verified declared currency; use recent history by default for ordinary buy-now, sell-timing, entry, exit, stop, target, trend, or momentum questions even when the user does not explicitly request tools; preserve every numeric source lexeme and visible provider/rights limits",
    "Get raw unadjusted HK daily bars for current-data-dependent opinions without assuming HKD or inventing suspensions and adjustment factors",
    tool.parameters(history_schema(), history_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case
            query.history(
              finance_track.Hk,
              query.Hk,
              input.code,
              input.start_date,
              input.end_date,
              input.limit,
            )
          {
            Error(_) -> tool.reject("Invalid exact HK Eastmoney history query")
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
                Ok(value) -> {
                  let retrieved_at = environment.now_milliseconds()
                  tool.text_result(
                    history_model_content(
                      render_history(input, value),
                      input,
                      value,
                      retrieved_at,
                    ),
                    history_json(input, value, retrieved_at),
                  )
                  |> promise.resolve
                }
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
        "Eastmoney access requires AGENT_CONTACT (for example ops@example.com)",
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
    schema.Required("code", schema.string() |> schema.with_string_length(5, 5)),
    schema.Required(
      "currency",
      schema.string_enum(["HKD", "CNY", "USD"])
        |> schema.described(
          "Independently verified listing/counter currency; Eastmoney does not prove it",
        ),
    ),
  ])
}

fn history_schema() -> schema.Schema {
  schema.object([
    schema.Required("code", schema.string() |> schema.with_string_length(5, 5)),
    schema.Required("currency", schema.string_enum(["HKD", "CNY", "USD"])),
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
  use code <- decode.field("code", decode.string)
  use currency <- decode.field("currency", decode.string)
  case currency_from_name(currency) {
    Ok(currency) -> decode.success(QuoteInput(code, currency))
    Error(_) ->
      decode.failure(QuoteInput("00001", Hkd), "valid declared HK currency")
  }
}

fn history_decoder() -> decode.Decoder(HistoryInput) {
  use code <- decode.field("code", decode.string)
  use currency <- decode.field("currency", decode.string)
  use start <- decode.field("startDate", decode.string)
  use end <- decode.field("endDate", decode.string)
  use limit <- decode.optional_field("limit", 250, decode.int)
  let assert Ok(placeholder) = time.date(2026, 1, 1)
  case currency_from_name(currency), parse_date(start), parse_date(end) {
    Ok(currency), Ok(start_date), Ok(end_date) ->
      decode.success(HistoryInput(code, currency, start_date, end_date, limit))
    _, _, _ ->
      decode.failure(
        HistoryInput("00001", Hkd, placeholder, placeholder, 250),
        "valid HK history query",
      )
  }
}

fn currency_from_name(value: String) -> Result(Currency, Nil) {
  case value {
    "HKD" -> Ok(Hkd)
    "CNY" -> Ok(Cny)
    "USD" -> Ok(Usd)
    _ -> Error(Nil)
  }
}

fn currency_name(value: Currency) -> String {
  case value {
    Hkd -> "HKD"
    Cny -> "CNY"
    Usd -> "USD"
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

fn result_context(scope: String) -> track_context.Context {
  let assert Ok(zone) = time.timezone("Asia/Hong_Kong")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Hk,
      market_scope: scope,
      venue_mic: Some(identity.venue_mic()),
      board: None,
      timezone: Some(zone),
      source_language: "zh-HK",
      providers: ["eastmoney"],
      entitlement: "public_web_local_analysis",
      limitations: limitations(),
    )
  value
}

fn limitations() -> List(String) {
  [
    "vendor_origin_not_hkex_evidence",
    "currency_is_caller_declared_and_must_be_independently_proven",
    "realtime_and_delay_status_unknown",
    "provider_volume_unit_not_verified",
    "service_level_and_redistribution_rights_unknown",
    "no_stale_fallback",
  ]
}

fn render_quote(input: QuoteInput, value: quote.Quote) -> String {
  "HK track | Eastmoney raw quote | "
  <> quote.code(value)
  <> " "
  <> quote.name(value)
  <> " | last "
  <> quote.last(value)
  <> " declared "
  <> currency_name(input.currency)
  <> " | latency unknown"
}

fn render_history(input: HistoryInput, value: history.History) -> String {
  "HK track | Eastmoney raw unadjusted daily history | "
  <> history.code(value)
  <> " "
  <> history.name(value)
  <> " | declared "
  <> currency_name(input.currency)
  <> " | "
  <> int.to_string(list.length(history.bars(value)))
  <> " bars"
}

fn history_model_content(
  summary: String,
  input: HistoryInput,
  value: history.History,
  retrieved_at: Int,
) -> String {
  let #(source_reference, receipt_digest, rows) =
    history_handoff(input, value, retrieved_at)
  summary
  <> "\nComplete bounded daily rows follow as CSV. For requested indicators, call the installed Pi tools sma, rsi, and atr with these exact rows; do not write or execute a program and do not calculate the indicators yourself. Map close to sma/rsi observations and high,low,close to atr bars.\n"
  <> "track=hk;provider=eastmoney;venue=XHKG;code="
  <> history.code(value)
  <> ";currency="
  <> currency_name(input.currency)
  <> ";currencyEvidence=caller_declared_not_provider_verified;frequency=daily;adjustment=raw;retrievedAtUnixMilliseconds="
  <> int.to_string(retrieved_at)
  <> ";sourceReference="
  <> source_reference
  <> ";acquisitionReceiptCanonicalSha256="
  <> receipt_digest
  <> ";acquisitionReceipt="
  <> receipt_digest
  <> "\ndate,open,high,low,close,volume,amount\n"
  <> rows
}

fn history_handoff(
  input: HistoryInput,
  value: history.History,
  retrieved_at: Int,
) -> #(String, String, String) {
  let rows =
    history.bars(value)
    |> list.map(fn(bar) {
      [
        date_text(history.date(bar)),
        history.open(bar),
        history.high(bar),
        history.low(bar),
        history.close(bar),
        history.volume(bar),
        history.amount(bar),
      ]
      |> string.join(",")
    })
    |> string.join("\n")
  let source_reference =
    "eastmoney:hk:XHKG:"
    <> history.code(value)
    <> ":"
    <> date_text(input.start_date)
    <> ":"
    <> date_text(input.end_date)
    <> ":raw_unadjusted_fqt_0"
  let canonical =
    source_reference
    <> "\nretrievedAtUnixMilliseconds="
    <> int.to_string(retrieved_at)
    <> "\ndate,open,high,low,close,volume,amount\n"
    <> rows
  let assert Ok(digest) = hash.text(canonical)
  #(source_reference, provenance_identity.sha256_value(digest), rows)
}

fn quote_json(
  input: QuoteInput,
  value: quote.Quote,
  retrieved_at: Int,
) -> json.Json {
  json.object(
    list.append(track_json.result_fields(result_context("hk_stock_quote")), [
      #("provider", json.string("eastmoney")),
      #("route", json.string("direct")),
      #("market", json.string("hk")),
      #("code", json.string(quote.code(value))),
      #("name", json.string(quote.name(value))),
      #("declaredCurrency", json.string(currency_name(input.currency))),
      #(
        "currencyEvidence",
        json.string("caller_declared_not_provider_verified"),
      ),
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
    ]),
  )
}

fn history_json(
  input: HistoryInput,
  value: history.History,
  retrieved_at: Int,
) -> json.Json {
  let #(source_reference, receipt_digest, _) =
    history_handoff(input, value, retrieved_at)
  json.object(
    list.append(track_json.result_fields(result_context("hk_stock_history")), [
      #("provider", json.string("eastmoney")),
      #("route", json.string("direct")),
      #("market", json.string("hk")),
      #("code", json.string(history.code(value))),
      #("name", json.string(history.name(value))),
      #("declaredCurrency", json.string(currency_name(input.currency))),
      #(
        "currencyEvidence",
        json.string("caller_declared_not_provider_verified"),
      ),
      #("frequency", json.string("daily")),
      #("adjustment", json.string("raw_unadjusted_fqt_0")),
      #("retrievedAtUnixMilliseconds", json.int(retrieved_at)),
      #("sourceReference", json.string(source_reference)),
      #(
        "acquisitionReceipt",
        json.object([
          #("canonicalSha256", json.string(receipt_digest)),
          #("scope", json.string("bounded_raw_daily_csv_v1")),
          #("providerAuthenticated", json.bool(False)),
        ]),
      ),
      #("bars", json.array(history.bars(value), bar_json)),
      #("entitlement", json.string("public_web_local_analysis")),
      #("redistribution", json.string("unknown")),
      #("limitations", json.array(limitations(), json.string)),
    ]),
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
