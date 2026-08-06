import finance_cn_identity/identity
import finance_core/adjustment
import finance_core/currency.{type Currency}
import finance_core/decimal
import finance_core/market
import finance_core/observation.{type Observation}
import finance_core/source
import finance_core/time
import finance_eastmoney
import finance_eastmoney/history
import finance_eastmoney/query
import finance_eastmoney/request as provider_request
import finance_eastmoney/runtime
import finance_http/response as http_response
import finance_http/transport
import finance_ohlcv
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_ohlcv/effect/environment
import pi_sparkles_cn_ohlcv/normalization

pub type Input {
  Input(
    market: query.Market,
    board: String,
    share_class: String,
    code: String,
    declared_currency: Currency,
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
    "cn_stock_ohlcv",
    "CN exact daily OHLCV",
    "Fetch bounded raw Eastmoney mainland daily bars for an exact caller-declared venue, board, share class, code, and currency; preserve provider rows and expose unknown volume/session/calendar/rights facts",
    "Retrieve exact raw mainland OHLCV without cross-venue fallback, adjustment, synthetic bars, or guessed timestamps and suspensions",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case plan(input) {
            Error(_) ->
              tool.reject("Invalid exact CN Eastmoney OHLCV identity or query")
            Ok(query_plan) -> {
              use fetched <- promise.await(fetch(
                provider_runtime,
                access,
                query_plan,
                id,
                transport.from_abort_signal(raw.dynamic(signal)),
              ))
              case fetched {
                Error(message) -> tool.reject(message)
                Ok(provider_value) -> {
                  let assert Ok(retrieved_at) =
                    time.instant(environment.now_milliseconds())
                  case
                    normalization.batch(
                      query_plan,
                      provider_value,
                      retrieved_at,
                      input.declared_currency,
                    )
                  {
                    Error(error) ->
                      tool.reject(
                        "Eastmoney rows failed exact CN OHLCV validation: "
                        <> string.inspect(error),
                      )
                    Ok(batch) ->
                      tool.text_result(
                        render(input, provider_value, batch),
                        result_json(
                          input,
                          query_plan,
                          provider_value,
                          batch,
                          retrieved_at,
                        ),
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
        "CN OHLCV requires EASTMONEY_USER_AGENT_CONTACT; EASTMONEY_USER_AGENT_PRODUCT is optional",
      )
    Ok(access) ->
      case runtime.new(access) {
        Ok(provider_runtime) -> Ready(access, provider_runtime)
        Error(_) ->
          InvalidConfiguration(
            "Eastmoney bounded market-data runtime could not initialize safely",
          )
      }
  }
}

fn plan(input: Input) -> Result(query.HistoryQuery, Nil) {
  case
    normalization.valid_identity(
      input.market,
      input.board,
      input.share_class,
      input.declared_currency,
    )
  {
    False -> Error(Nil)
    True ->
      query.history(
        finance_track.Cn,
        input.market,
        input.code,
        input.start_date,
        input.end_date,
        input.limit,
      )
      |> result.map_error(fn(_) { Nil })
  }
}

fn fetch(provider_runtime, access, plan, id, cancellation) {
  case provider_request.history(access, plan) {
    Error(_) -> promise.resolve(Error("Eastmoney history request was invalid"))
    Ok(request_value) -> {
      use outcome <- promise.await(runtime.send(
        provider_runtime,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      case outcome {
        Error(error) ->
          promise.resolve(Error(
            "Eastmoney history request failed safely: " <> string.inspect(error),
          ))
        Ok(response_value) -> {
          let status = http_response.status(response_value)
          case status >= 200 && status < 300 {
            False ->
              promise.resolve(Error(
                "Eastmoney history request returned HTTP "
                <> int.to_string(status),
              ))
            True ->
              case
                history.decode(http_response.body(response_value), for: plan)
              {
                Ok(value) -> promise.resolve(Ok(value))
                Error(_) ->
                  promise.resolve(Error(
                    "Eastmoney returned invalid, mismatched, or over-budget daily bars",
                  ))
              }
          }
        }
      }
    }
  }
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required(
      "board",
      schema.string_enum(["main", "star", "chinext", "beijing"]),
    ),
    schema.Required("shareClass", schema.string_enum(["a_share", "b_share"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
    schema.Required("currency", schema.string_enum(["CNY", "HKD", "USD"])),
    schema.Required(
      "startDate",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Inclusive YYYY-MM-DD start"),
    ),
    schema.Required(
      "endDate",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Inclusive YYYY-MM-DD end"),
    ),
    schema.Optional(
      "limit",
      schema.integer()
        |> schema.with_number_range(1.0, 1000.0)
        |> schema.described("Maximum provider rows; defaults to 250"),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use venue <- decode.field("venue", decode.string)
  use board <- decode.field("board", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  use code <- decode.field("code", decode.string)
  use currency_code <- decode.field("currency", decode.string)
  use start <- decode.field("startDate", decode.string)
  use end <- decode.field("endDate", decode.string)
  use limit <- decode.optional_field("limit", 250, decode.int)
  let assert Ok(placeholder) = time.date(1970, 1, 1)
  let assert Ok(cny) = currency.from_code("CNY")
  case
    market_from_name(venue),
    currency.from_code(currency_code),
    parse_date(start),
    parse_date(end)
  {
    Ok(market), Ok(declared_currency), Ok(start_date), Ok(end_date) ->
      decode.success(Input(
        market,
        board,
        share_class,
        code,
        declared_currency,
        start_date,
        end_date,
        limit,
      ))
    _, _, _, _ ->
      decode.failure(
        Input(
          query.CnSse,
          "main",
          "a_share",
          "600000",
          cny,
          placeholder,
          placeholder,
          250,
        ),
        "valid CN OHLCV identity and dates",
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

fn result_context(input: Input) -> track_context.Context {
  let assert Ok(zone) = time.timezone("Asia/Shanghai")
  let venue = case input.market {
    query.CnSse -> identity.Sse
    query.CnSzse -> identity.Szse
    query.CnBse -> identity.Bse
    _ -> identity.Sse
  }
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Cn,
      market_scope: "cn_stock_ohlcv",
      venue_mic: Some(identity.venue_mic(venue)),
      board: Some(input.board),
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
    "venue_board_share_class_and_currency_are_caller_declared",
    "provider_date_has_no_source_instant",
    "provider_daily_session_membership_not_independently_verified",
    "provider_volume_unit_not_verified",
    "provider_amount_and_turnover_units_not_normalized",
    "reviewed_cn_calendar_and_status_source_not_composed",
    "missing_sessions_are_not_classified",
    "service_level_and_redistribution_rights_unknown",
    "no_provider_or_venue_fallback",
  ]
}

fn render(
  input: Input,
  provider_value: history.History,
  batch: finance_ohlcv.Batch,
) -> String {
  "CN track | Eastmoney raw daily OHLCV | "
  <> query.market_name(input.market)
  <> " "
  <> history.code(provider_value)
  <> " "
  <> history.name(provider_value)
  <> " | "
  <> int.to_string(list.length(finance_ohlcv.observations(batch)))
  <> " bars | volume unit and calendar gaps unknown | "
  <> pagination_name(finance_ohlcv.pagination(batch))
}

fn result_json(
  input: Input,
  plan: query.HistoryQuery,
  provider_value: history.History,
  batch: finance_ohlcv.Batch,
  retrieved_at: time.Instant,
) -> json.Json {
  json.object(
    list.append(track_json.result_fields(result_context(input)), [
      #("provider", json.string("eastmoney")),
      #("route", json.string("direct")),
      #("venue", json.string(query.market_name(input.market))),
      #("board", json.string(input.board)),
      #("shareClass", json.string(input.share_class)),
      #("code", json.string(history.code(provider_value))),
      #("name", json.string(history.name(provider_value))),
      #(
        "identityEvidence",
        json.string("caller_declared_not_provider_verified"),
      ),
      #("startDate", json.string(date_text(query.history_start(plan)))),
      #("endDate", json.string(date_text(query.history_end(plan)))),
      #("interval", json.string("1_day")),
      #("session", json.string(session_name(finance_ohlcv.session(batch)))),
      #("sessionTimezone", json.string("Asia/Shanghai")),
      #("currency", json.string(currency.code(finance_ohlcv.currency(batch)))),
      #(
        "currencyEvidence",
        json.string("caller_declared_not_provider_verified"),
      ),
      #(
        "volumeUnit",
        json.string(volume_unit_name(finance_ohlcv.volume_unit(batch))),
      ),
      #("providerVolumeUnit", json.null()),
      #(
        "adjustment",
        json.string(adjustment_name(finance_ohlcv.adjustment(batch))),
      ),
      #(
        "retrievedAtUnixMilliseconds",
        json.int(time.unix_milliseconds(retrieved_at)),
      ),
      #("pagesFetched", json.int(1)),
      #("pagination", pagination_json(finance_ohlcv.pagination(batch))),
      #(
        "availability",
        json.string(availability_name(finance_ohlcv.availability(batch))),
      ),
      #(
        "duplicatesCollapsed",
        json.int(finance_ohlcv.duplicates_collapsed(batch)),
      ),
      #(
        "calendarCompleteness",
        calendar_json(finance_ohlcv.calendar_assessment(batch)),
      ),
      #(
        "gapStates",
        json.array(
          [
            "market_closure",
            "suspension",
            "provider_omission",
            "unavailable_history",
          ],
          json.string,
        ),
      ),
      #(
        "providerRows",
        json.array(history.bars(provider_value), provider_row_json),
      ),
      #("bars", json.array(finance_ohlcv.observations(batch), bar_json)),
      #("entitlement", json.string("public_web_local_analysis")),
      #("redistribution", json.string("unknown")),
      #("limitations", json.array(limitations(), json.string)),
    ]),
  )
}

fn provider_row_json(value: history.Bar) -> json.Json {
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

fn bar_json(value: Observation(finance_ohlcv.Bar)) -> json.Json {
  let bar = value.value
  json.object([
    #("providerDate", json.string(finance_ohlcv.source_timestamp(bar))),
    #("asOfBasis", json.string(time_basis_name(finance_ohlcv.time_basis(bar)))),
    #("asOfUnixMilliseconds", json.int(time.unix_milliseconds(value.as_of))),
    #("sessionDate", json.string(date_text(finance_ohlcv.session_date(bar)))),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(value.retrieved_at)),
    ),
    #(
      "source",
      json.object([
        #("provider", json.string(source.provider(value.source))),
        #("reference", json.string(source.reference(value.source))),
      ]),
    ),
    #(
      "raw",
      json.object([
        #("open", json.string(finance_ohlcv.raw(finance_ohlcv.open(bar)))),
        #("high", json.string(finance_ohlcv.raw(finance_ohlcv.high(bar)))),
        #("low", json.string(finance_ohlcv.raw(finance_ohlcv.low(bar)))),
        #("close", json.string(finance_ohlcv.raw(finance_ohlcv.close(bar)))),
        #("volume", json.string(finance_ohlcv.raw(finance_ohlcv.volume(bar)))),
        #("tradeCount", json.null()),
        #("vwap", json.null()),
      ]),
    ),
    #(
      "normalized",
      json.object([
        #("open", decimal_json(finance_ohlcv.open(bar))),
        #("high", decimal_json(finance_ohlcv.high(bar))),
        #("low", decimal_json(finance_ohlcv.low(bar))),
        #("close", decimal_json(finance_ohlcv.close(bar))),
        #("volume", decimal_json(finance_ohlcv.volume(bar))),
        #("tradeCount", json.null()),
        #("vwap", json.null()),
      ]),
    ),
  ])
}

fn pagination_json(value: finance_ohlcv.Pagination) -> json.Json {
  json.object([
    #("state", json.string(pagination_name(value))),
    #("continuationTokenAvailable", json.bool(False)),
    #("maximumPages", case value {
      finance_ohlcv.TruncatedByPageBudget(maximum) -> json.int(maximum)
      _ -> json.null()
    }),
    #("maximumBars", case value {
      finance_ohlcv.TruncatedByBarBudget(maximum) -> json.int(maximum)
      _ -> json.null()
    }),
  ])
}

fn pagination_name(value: finance_ohlcv.Pagination) -> String {
  case value {
    finance_ohlcv.AllPages -> "complete"
    finance_ohlcv.TruncatedByPageBudget(_) -> "truncated_by_page_budget"
    finance_ohlcv.TruncatedByBarBudget(_) -> "truncated_by_bar_budget"
  }
}

fn calendar_json(value: finance_ohlcv.CalendarAssessment) -> json.Json {
  case value {
    finance_ohlcv.CalendarNotAssessed(reason) ->
      json.object([
        #("state", json.string("calendar_not_assessed")),
        #("reason", json.string(reason)),
        #("gaps", json.array([], fn(value) { value })),
      ])
    finance_ohlcv.CalendarAssessed(gaps) ->
      json.object([
        #("state", json.string("calendar_assessed")),
        #("reason", json.null()),
        #("gaps", json.array(gaps, gap_json)),
      ])
  }
}

fn gap_json(value: finance_ohlcv.Gap) -> json.Json {
  let finance_ohlcv.Gap(session_date, state, evidence) = value
  json.object([
    #("sessionDate", json.string(date_text(session_date))),
    #("state", json.string(gap_name(state))),
    #("evidenceReference", json.nullable(evidence, json.string)),
  ])
}

fn gap_name(value: finance_ohlcv.GapState) -> String {
  case value {
    finance_ohlcv.MarketClosure -> "market_closure"
    finance_ohlcv.Suspension -> "suspension"
    finance_ohlcv.ProviderOmission -> "provider_omission"
    finance_ohlcv.UnavailableHistory -> "unavailable_history"
  }
}

fn availability_name(value: finance_ohlcv.Availability) -> String {
  case value {
    finance_ohlcv.BarsReturned -> "bars_returned"
    finance_ohlcv.NoBarsReturned -> "no_bars_returned_unclassified"
  }
}

fn time_basis_name(value: finance_ohlcv.TimeBasis) -> String {
  case value {
    finance_ohlcv.SourceInstant -> "source_instant"
    finance_ohlcv.SessionDateAnchor -> "session_date_anchor"
  }
}

fn volume_unit_name(value: finance_ohlcv.VolumeUnit) -> String {
  case value {
    finance_ohlcv.Shares -> "shares"
    finance_ohlcv.UnknownVolumeUnit -> "unknown"
  }
}

fn adjustment_name(value: adjustment.Adjustment) -> String {
  case value {
    adjustment.Raw -> "raw"
    adjustment.SplitAdjusted -> "split_adjusted"
    adjustment.DividendAdjusted -> "dividend_adjusted"
    adjustment.TotalReturnAdjusted -> "total_return_adjusted"
    adjustment.ProviderAdjusted(_) -> "provider_adjusted"
  }
}

fn session_name(value: market.Session) -> String {
  case value {
    market.PreMarket -> "pre_market"
    market.Regular -> "regular"
    market.AfterHours -> "after_hours"
    market.Auction -> "auction"
    market.Closed -> "closed"
    market.OtherSession(label) -> market.label(label)
  }
}

fn decimal_json(value: finance_ohlcv.ExactValue) -> json.Json {
  value |> finance_ohlcv.normalized |> decimal.to_string |> json.string
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
