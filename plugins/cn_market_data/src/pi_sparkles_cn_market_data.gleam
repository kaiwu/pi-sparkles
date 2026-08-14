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
import pi_sparkles_cn_market_data/effect/environment

pub type QuoteInput {
  QuoteInput(
    market: query.Market,
    code: String,
    instrument_kind: InstrumentKind,
  )
}

pub type InstrumentKind {
  ListedSecurity
  BenchmarkIndex
  SectorIndex
}

pub type HistoryInput {
  HistoryInput(
    market: query.Market,
    code: String,
    start_date: time.Date,
    end_date: time.Date,
    limit: Int,
    instrument_kind: InstrumentKind,
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
    "cn_raw_vendor_quote",
    "CN raw vendor quote",
    "Fetch an exact-code Eastmoney mainland listed-security quote after an explicit SSE/SZSE/BSE choice; reviewed benchmark and sector indices are rejected locally before network access",
    "Use only for an independently identified listed security. Use cn_market_overview for today's broad Shanghai/Shenzhen market and cn_sector_trends for industry-sector comparisons",
    tool.parameters(quote_schema(), quote_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case
            input.instrument_kind,
            reviewed_benchmark(input.market, input.code),
            reviewed_sector(input.market, input.code)
          {
            SectorIndex, _, _ | _, _, True -> reject_sector_quote(input)
            BenchmarkIndex, _, _ | _, True, _ -> reject_index_quote(input)
            ListedSecurity, False, False ->
              case query.quote(finance_track.Cn, input.market, input.code) {
                Error(_) ->
                  reject_input(
                    "invalid_quote_identity",
                    "Invalid explicit CN Eastmoney listed-security quote identity",
                    input.market,
                    input.code,
                    input.instrument_kind,
                  )
                Ok(plan) -> {
                  use outcome <- promise.await(fetch_quote(
                    provider_runtime,
                    access,
                    plan,
                    id,
                    transport.from_abort_signal(raw.dynamic(signal)),
                  ))
                  case outcome {
                    Error(message) ->
                      reject_input(
                        "provider_quote_failed",
                        message,
                        input.market,
                        input.code,
                        input.instrument_kind,
                      )
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
      }
    },
  )
  tool.register_compact(
    api,
    "cn_raw_vendor_history",
    "CN raw vendor history",
    "Fetch bounded Eastmoney raw unadjusted daily bars for an exact caller-identified SSE/SZSE/BSE listed security, reviewed benchmark index, or reviewed CSI sector index",
    "Use for one exact series only. Label reviewed indices explicitly; use cn_market_overview for the current broad market and cn_sector_trends once for sector comparisons instead of guessing or probing codes",
    tool.parameters(history_schema(), history_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case
            input.instrument_kind,
            reviewed_benchmark(input.market, input.code),
            reviewed_sector(input.market, input.code)
          {
            BenchmarkIndex, True, True | SectorIndex, True, True ->
              reject_input(
                "conflicting_index_identity",
                "Instrument code matched conflicting reviewed index registries",
                input.market,
                input.code,
                input.instrument_kind,
              )
            ListedSecurity, True, _ ->
              reject_input(
                "instrument_kind_mismatch",
                "Reviewed benchmark code requires instrumentKind=benchmark_index for daily history or cn_market_overview for the current market",
                input.market,
                input.code,
                BenchmarkIndex,
              )
            ListedSecurity, _, True ->
              reject_input(
                "instrument_kind_mismatch",
                "Reviewed CSI sector code requires instrumentKind=sector_index for one exact history series or cn_sector_trends for the complete comparison",
                input.market,
                input.code,
                SectorIndex,
              )
            BenchmarkIndex, False, _ ->
              reject_input(
                "unsupported_index_identity",
                "benchmark_index is limited to the exact reviewed benchmark registry",
                input.market,
                input.code,
                BenchmarkIndex,
              )
            SectorIndex, _, False ->
              reject_input(
                "unsupported_sector_identity",
                "sector_index is limited to the exact pinned CSI 800 level-one registry; use cn_sector_trends for the complete comparison",
                input.market,
                input.code,
                SectorIndex,
              )
            ListedSecurity, False, False
            | BenchmarkIndex, True, False
            | SectorIndex, False, True
            ->
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
                  reject_input(
                    "invalid_history_identity",
                    "Invalid explicit CN Eastmoney history identity",
                    input.market,
                    input.code,
                    input.instrument_kind,
                  )
                Ok(plan) -> {
                  use outcome <- promise.await(fetch_history(
                    provider_runtime,
                    access,
                    plan,
                    id,
                    transport.from_abort_signal(raw.dynamic(signal)),
                  ))
                  case outcome {
                    Error(message) ->
                      reject_input(
                        "provider_history_failed",
                        message,
                        input.market,
                        input.code,
                        input.instrument_kind,
                      )
                    Ok(value) -> {
                      let retrieved_at = environment.now_milliseconds()
                      let details = history_json(input, value, retrieved_at)
                      tool.text_result(
                        history_model_content(input, value, retrieved_at),
                        details,
                      )
                      |> promise.resolve
                    }
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
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
    schema.Optional(
      "instrumentKind",
      schema.string_enum(["listed_security", "benchmark_index", "sector_index"])
        |> schema.with_default(json.string("listed_security")),
    ),
  ])
}

fn history_schema() -> schema.Schema {
  schema.object([
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
    schema.Optional(
      "instrumentKind",
      schema.string_enum(["listed_security", "benchmark_index", "sector_index"])
        |> schema.with_default(json.string("listed_security")),
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

fn quote_decoder() -> decode.Decoder(QuoteInput) {
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  use kind <- decode.optional_field(
    "instrumentKind",
    "listed_security",
    decode.string,
  )
  case market_from_name(venue), instrument_kind_from_name(kind) {
    Ok(market), Ok(instrument_kind) ->
      decode.success(QuoteInput(market, code, instrument_kind))
    _, _ ->
      decode.failure(
        QuoteInput(query.CnSse, "600519", ListedSecurity),
        "valid CN listed-security quote identity",
      )
  }
}

fn history_decoder() -> decode.Decoder(HistoryInput) {
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  use kind <- decode.optional_field(
    "instrumentKind",
    "listed_security",
    decode.string,
  )
  use start <- decode.field("startDate", decode.string)
  use end <- decode.field("endDate", decode.string)
  use limit <- decode.optional_field("limit", 250, decode.int)
  let assert Ok(placeholder) = time.date(2026, 1, 1)
  case
    market_from_name(venue),
    parse_date(start),
    parse_date(end),
    instrument_kind_from_name(kind)
  {
    Ok(market), Ok(start_date), Ok(end_date), Ok(instrument_kind) ->
      decode.success(HistoryInput(
        market,
        code,
        start_date,
        end_date,
        limit,
        instrument_kind,
      ))
    _, _, _, _ ->
      decode.failure(
        HistoryInput(
          query.CnSse,
          "600519",
          placeholder,
          placeholder,
          250,
          ListedSecurity,
        ),
        "valid CN history query",
      )
  }
}

fn instrument_kind_from_name(value: String) -> Result(InstrumentKind, Nil) {
  case value {
    "listed_security" -> Ok(ListedSecurity)
    "benchmark_index" -> Ok(BenchmarkIndex)
    "sector_index" -> Ok(SectorIndex)
    _ -> Error(Nil)
  }
}

fn instrument_kind_name(value: InstrumentKind) -> String {
  case value {
    ListedSecurity -> "listed_security"
    BenchmarkIndex -> "benchmark_index"
    SectorIndex -> "sector_index"
  }
}

fn reviewed_benchmark(market: query.Market, code: String) -> Bool {
  case market, code {
    query.CnSse, "000001" | query.CnSse, "000300" -> True
    query.CnSzse, "399001" | query.CnSzse, "399006" -> True
    _, _ -> False
  }
}

fn reviewed_sector(market: query.Market, code: String) -> Bool {
  query.cn_sector_indices()
  |> list.any(fn(index) {
    query.cn_sector_market(index) == market
    && query.cn_sector_code(index) == code
  })
}

fn reject_index_quote(input: QuoteInput) -> Promise(value) {
  reject_input(
    "unsupported_instrument_kind",
    "cn_raw_vendor_quote supports listed securities only; use cn_market_overview for the reviewed Shanghai/Shenzhen benchmark set",
    input.market,
    input.code,
    BenchmarkIndex,
  )
}

fn reject_sector_quote(input: QuoteInput) -> Promise(value) {
  reject_input(
    "unsupported_instrument_kind",
    "cn_raw_vendor_quote supports listed securities only; use cn_sector_trends for the pinned CSI industry-sector comparison",
    input.market,
    input.code,
    SectorIndex,
  )
}

fn reject_input(
  code: String,
  message: String,
  market: query.Market,
  security_code: String,
  instrument_kind: InstrumentKind,
) -> Promise(value) {
  tool.reject_typed(
    code,
    message,
    json.object([
      #("code", json.string(code)),
      #("track", json.string("cn")),
      #("market", json.string(query.market_name(market))),
      #("instrumentCode", json.string(security_code)),
      #("instrumentKind", json.string(instrument_kind_name(instrument_kind))),
      #(
        "recommendedTool",
        json.string(case instrument_kind {
          BenchmarkIndex -> "cn_market_overview"
          SectorIndex -> "cn_sector_trends"
          ListedSecurity -> "cn_raw_vendor_quote_or_history"
        }),
      ),
    ]),
  )
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
    "security_kind_identity_and_cny_scope_must_be_independently_proven",
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

fn history_model_content(
  input: HistoryInput,
  value: history.History,
  retrieved_at: Int,
) -> String {
  let #(source_reference, receipt_digest, rows) =
    history_handoff(input, value, retrieved_at)
  render_history(input, value)
  <> "\nComplete bounded daily rows follow as CSV. These daily bars do not establish intraday ordering, market breadth, fund flow, or sector rotation.\n"
  <> "track=cn;provider=eastmoney;market="
  <> query.market_name(input.market)
  <> ";code="
  <> history.code(value)
  <> ";instrumentKind="
  <> instrument_kind_name(input.instrument_kind)
  <> ";currency=CNY;frequency=daily;adjustment=raw_unadjusted_fqt_0;retrievedAtUnixMilliseconds="
  <> int.to_string(retrieved_at)
  <> ";sourceReference="
  <> source_reference
  <> ";acquisitionReceiptCanonicalSha256="
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
    "eastmoney:cn:"
    <> query.market_name(input.market)
    <> ":"
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
    list.append(
      track_json.result_fields(result_context(
        input.market,
        "cn_raw_vendor_quote",
      )),
      [
        #("provider", json.string("eastmoney")),
        #("route", json.string("direct")),
        #("market", json.string(query.market_name(input.market))),
        #("code", json.string(quote.code(value))),
        #(
          "instrumentKind",
          json.string(instrument_kind_name(input.instrument_kind)),
        ),
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
  let #(source_reference, receipt_digest, _) =
    history_handoff(input, value, retrieved_at)
  json.object(
    list.append(
      track_json.result_fields(result_context(
        input.market,
        "cn_raw_vendor_history",
      )),
      [
        #("provider", json.string("eastmoney")),
        #("route", json.string("direct")),
        #("market", json.string(query.market_name(input.market))),
        #("code", json.string(history.code(value))),
        #(
          "instrumentKind",
          json.string(instrument_kind_name(input.instrument_kind)),
        ),
        #("name", json.string(history.name(value))),
        #("declaredCurrency", json.string("CNY")),
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
