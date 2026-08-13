import finance_core/adjustment
import finance_core/currency.{type Currency}
import finance_core/decimal
import finance_core/identifier
import finance_core/instrument
import finance_core/market
import finance_core/observation.{type Observation}
import finance_core/source
import finance_core/time
import finance_eastmoney
import finance_eastmoney/history
import finance_eastmoney/query
import finance_eastmoney/request as provider_request
import finance_eastmoney/runtime
import finance_hk_identity/identity
import finance_hk_ohlcv/gap_receipt
import finance_http/response as http_response
import finance_http/transport
import finance_ohlcv
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
import gleam/option.{Some}
import gleam/result
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_hk_ohlcv/effect/environment
import pi_sparkles_hk_ohlcv/normalization

pub type Input {
  Input(
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

type FetchOutcome {
  FetchOutcome(history: history.History, page_receipt: gap_receipt.Page)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register_compact(
    api,
    "hk_stock_ohlcv",
    "HK exact daily OHLCV",
    "Fetch bounded raw Eastmoney Hong Kong daily bars for an exact caller-declared board, share class, five-digit code, and currency; use OHLCV evidence by default for ordinary buy-now, sell-timing, entry, exit, stop, target, trend, momentum, or volatility questions even when the user does not explicitly request tools; preserve provider rows and expose unknown volume/session/calendar/rights facts",
    "Retrieve exact raw HK OHLCV for current-data-dependent opinions without currency fallback, adjustment, synthetic bars, or guessed timestamps, half-days, and suspensions",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case plan(input) {
            Error(_) ->
              tool.reject("Invalid exact HK Eastmoney OHLCV identity or query")
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
                Ok(outcome) -> {
                  let assert Ok(retrieved_at) =
                    time.instant(environment.now_milliseconds())
                  case
                    normalization.batch(
                      query_plan,
                      outcome.history,
                      retrieved_at,
                      input.declared_currency,
                    )
                  {
                    Error(error) ->
                      tool.reject(
                        "Eastmoney rows failed exact HK OHLCV validation: "
                        <> string.inspect(error),
                      )
                    Ok(batch) ->
                      case
                        build_gap_receipt(
                          input,
                          query_plan,
                          batch,
                          outcome.page_receipt,
                          retrieved_at,
                        )
                      {
                        Error(message) -> tool.reject(message)
                        Ok(#(receipt, digest)) -> {
                          let details =
                            result_json(
                              input,
                              query_plan,
                              outcome.history,
                              batch,
                              retrieved_at,
                              receipt,
                              digest,
                            )
                          tool.text_result(
                            model_content(
                              render(outcome.history, batch),
                              input,
                              outcome.history,
                              retrieved_at,
                              receipt,
                              digest,
                            ),
                            details,
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
    },
  )
  promise.resolve(Nil)
}

fn provider() -> Provider {
  case finance_eastmoney.access(environment.product(), environment.contact()) {
    Error(_) -> InvalidConfiguration("HK OHLCV requires AGENT_CONTACT")
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
  case normalization.valid_identity(input.board, input.share_class) {
    False -> Error(Nil)
    True ->
      query.history(
        finance_track.Hk,
        query.Hk,
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
              case response_page_receipt(response_value) {
                Error(message) -> promise.resolve(Error(message))
                Ok(page_receipt) ->
                  case
                    history.decode(
                      http_response.body(response_value),
                      for: plan,
                    )
                  {
                    Ok(value) ->
                      promise.resolve(Ok(FetchOutcome(value, page_receipt)))
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
}

fn response_page_receipt(
  response: http_response.Response,
) -> Result(gap_receipt.Page, String) {
  use content_hash <- result.try(
    hash.text(http_response.body(response))
    |> result.map_error(fn(_) {
      "Eastmoney response content could not be hashed safely"
    }),
  )
  gap_receipt.page(
    1,
    http_response.first_header(response, name: "x-request-id"),
    http_response.byte_length(response),
    content_hash,
  )
  |> result.map_error(fn(_) {
    "Eastmoney response page receipt was structurally invalid"
  })
}

fn build_gap_receipt(
  input: Input,
  plan: query.HistoryQuery,
  batch: finance_ohlcv.Batch,
  page_receipt: gap_receipt.Page,
  retrieved_at: time.Instant,
) -> Result(#(gap_receipt.Receipt, provenance_identity.Sha256), String) {
  use listing <- result.try(receipt_listing(input))
  let bar_dates =
    batch
    |> finance_ohlcv.observations
    |> list.map(fn(observation) {
      observation.value |> finance_ohlcv.session_date
    })
  use receipt <- result.try(
    gap_receipt.new(
      listing: listing,
      start_date: query.history_start(plan),
      end_date: query.history_end(plan),
      limit: query.history_limit(plan),
      source_reference: query.history_source_reference(plan),
      retrieved_at: retrieved_at,
      pagination: receipt_pagination(finance_ohlcv.pagination(batch)),
      pages: [page_receipt],
      bar_dates: bar_dates,
    )
    |> result.map_error(fn(_) {
      "Eastmoney HK gap-assessment receipt was structurally invalid"
    }),
  )
  use digest <- result.try(
    receipt
    |> gap_receipt.canonical_text
    |> hash.text
    |> result.map_error(fn(_) {
      "Eastmoney HK gap-assessment receipt could not be hashed safely"
    }),
  )
  Ok(#(receipt, digest))
}

fn receipt_listing(input: Input) -> Result(identity.Listing, String) {
  use instrument_id <- result.try(
    identifier.instrument_id("eastmoney:hk:" <> input.code)
    |> result.map_error(fn(_) { "Invalid HK receipt instrument identity" }),
  )
  use board <- result.try(receipt_board(input.board))
  use share_class <- result.try(receipt_share_class(input.share_class))
  identity.new(
    instrument_id,
    input.code,
    board,
    share_class,
    input.declared_currency,
    instrument.UnknownStatus,
  )
  |> result.map_error(fn(_) { "Invalid HK receipt listing identity" })
}

fn receipt_board(value: String) -> Result(identity.Board, String) {
  case value {
    "main" -> Ok(identity.MainBoard)
    "gem" -> Ok(identity.Gem)
    _ -> Error("Invalid HK receipt board identity")
  }
}

fn receipt_share_class(value: String) -> Result(identity.ShareClass, String) {
  case value {
    "ordinary_share" -> Ok(identity.OrdinaryShare)
    "depositary_receipt" -> Ok(identity.DepositaryReceipt)
    _ -> Error("Invalid HK receipt share class")
  }
}

fn receipt_pagination(
  value: finance_ohlcv.Pagination,
) -> gap_receipt.Pagination {
  case value {
    finance_ohlcv.AllPages -> gap_receipt.Complete
    finance_ohlcv.TruncatedByBarBudget(_) -> gap_receipt.TruncatedByBarBudget
    finance_ohlcv.TruncatedByPageBudget(_) -> gap_receipt.TruncatedByBarBudget
  }
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("board", schema.string_enum(["main", "gem"])),
    schema.Required(
      "shareClass",
      schema.string_enum(["ordinary_share", "depositary_receipt"]),
    ),
    schema.Required("code", schema.string() |> schema.with_string_length(5, 5)),
    schema.Required("currency", schema.string_enum(["HKD", "CNY", "USD"])),
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
  use board <- decode.field("board", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  use code <- decode.field("code", decode.string)
  use currency_code <- decode.field("currency", decode.string)
  use start <- decode.field("startDate", decode.string)
  use end <- decode.field("endDate", decode.string)
  use limit <- decode.optional_field("limit", 250, decode.int)
  let assert Ok(placeholder) = time.date(1970, 1, 1)
  let assert Ok(hkd) = currency.from_code("HKD")
  case currency.from_code(currency_code), parse_date(start), parse_date(end) {
    Ok(declared_currency), Ok(start_date), Ok(end_date) ->
      decode.success(Input(
        board,
        share_class,
        code,
        declared_currency,
        start_date,
        end_date,
        limit,
      ))
    _, _, _ ->
      decode.failure(
        Input(
          "main",
          "ordinary_share",
          "00700",
          hkd,
          placeholder,
          placeholder,
          250,
        ),
        "valid HK OHLCV identity and dates",
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

fn result_context(input: Input) -> track_context.Context {
  let assert Ok(zone) = time.timezone("Asia/Hong_Kong")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Hk,
      market_scope: "hk_stock_ohlcv",
      venue_mic: Some(identity.venue_mic()),
      board: Some(input.board),
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
    "board_share_class_and_currency_are_caller_declared",
    "provider_date_has_no_source_instant",
    "provider_daily_session_and_half_day_membership_not_independently_verified",
    "provider_volume_unit_not_verified",
    "provider_amount_and_turnover_units_not_normalized",
    "reviewed_hk_calendar_and_status_source_not_composed",
    "missing_sessions_are_not_classified",
    "service_level_and_redistribution_rights_unknown",
    "no_currency_or_provider_fallback",
  ]
}

fn render(
  provider_value: history.History,
  batch: finance_ohlcv.Batch,
) -> String {
  "HK track | Eastmoney raw daily OHLCV | "
  <> history.code(provider_value)
  <> " "
  <> history.name(provider_value)
  <> " | "
  <> int.to_string(list.length(finance_ohlcv.observations(batch)))
  <> " bars | volume unit and calendar gaps unknown | "
  <> pagination_name(finance_ohlcv.pagination(batch))
}

fn model_content(
  summary: String,
  input: Input,
  value: history.History,
  retrieved_at: time.Instant,
  receipt: gap_receipt.Receipt,
  receipt_digest: provenance_identity.Sha256,
) -> String {
  summary
  <> "\nComplete bounded daily rows follow as CSV. For requested indicators, call the installed Pi tools sma, rsi, and atr with these exact rows; do not write or execute a program and do not calculate the indicators yourself. Map close to sma/rsi observations and high,low,close to atr bars.\n"
  <> "track=hk;provider=eastmoney;venue=XHKG;board="
  <> input.board
  <> ";shareClass="
  <> input.share_class
  <> ";code="
  <> history.code(value)
  <> ";currency="
  <> currency.code(input.declared_currency)
  <> ";currencyEvidence=caller_declared_not_provider_verified;frequency=daily;adjustment=raw;retrievedAtUnixMilliseconds="
  <> int.to_string(time.unix_milliseconds(retrieved_at))
  <> ";gapAssessmentReceiptDigest="
  <> provenance_identity.sha256_value(receipt_digest)
  <> ";acquisitionReceipt="
  <> provenance_identity.sha256_value(receipt_digest)
  <> ";sourceReference="
  <> gap_receipt.source_reference(receipt)
  <> "\ndate,open,high,low,close,volume,amount\n"
  <> {
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
  }
}

fn result_json(
  input: Input,
  plan: query.HistoryQuery,
  provider_value: history.History,
  batch: finance_ohlcv.Batch,
  retrieved_at: time.Instant,
  receipt: gap_receipt.Receipt,
  receipt_digest: provenance_identity.Sha256,
) -> json.Json {
  json.object(
    list.append(track_json.result_fields(result_context(input)), [
      #("provider", json.string("eastmoney")),
      #("route", json.string("direct")),
      #("venue", json.string("hk")),
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
      #("sessionTimezone", json.string("Asia/Hong_Kong")),
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
        "gapAssessmentReceipt",
        gap_assessment_receipt_json(receipt, receipt_digest),
      ),
      #("sourceReference", json.string(gap_receipt.source_reference(receipt))),
      #(
        "acquisitionReceipt",
        json.string(provenance_identity.sha256_value(receipt_digest)),
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

fn gap_assessment_receipt_json(
  value: gap_receipt.Receipt,
  digest: provenance_identity.Sha256,
) -> json.Json {
  json.object([
    #("schema", json.string(gap_receipt.schema_name)),
    #("schemaVersion", json.int(gap_receipt.schema_version)),
    #("digestAlgorithm", json.string(gap_receipt.digest_algorithm)),
    #("digest", json.string(provenance_identity.sha256_value(digest))),
    #("provider", json.string(gap_receipt.provider(value))),
    #("venue", json.string(gap_receipt.venue_name())),
    #("board", json.string(gap_receipt.board_name(gap_receipt.board(value)))),
    #(
      "shareClass",
      json.string(gap_receipt.share_class_name(gap_receipt.share_class(value))),
    ),
    #("currency", json.string(value |> gap_receipt.currency |> currency.code)),
    #("code", json.string(gap_receipt.code(value))),
    #("startDate", json.string(date_text(gap_receipt.start_date(value)))),
    #("endDate", json.string(date_text(gap_receipt.end_date(value)))),
    #("limit", json.int(gap_receipt.limit(value))),
    #("sourceReference", json.string(gap_receipt.source_reference(value))),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(gap_receipt.retrieved_at(value))),
    ),
    #(
      "pagination",
      json.string(gap_receipt.pagination_name(gap_receipt.pagination(value))),
    ),
    #("pages", json.array(gap_receipt.pages(value), receipt_page_json)),
    #(
      "barDates",
      json.array(gap_receipt.bar_dates(value), fn(value) {
        value |> date_text |> json.string
      }),
    ),
    #(
      "integrity",
      json.object([
        #("state", json.string("sha256_content_bound")),
        #("scope", json.string("canonical_hk_gap_projection_v1")),
        #("providerAuthenticated", json.bool(False)),
      ]),
    ),
  ])
}

fn receipt_page_json(value: gap_receipt.Page) -> json.Json {
  json.object([
    #("sequence", json.int(gap_receipt.page_sequence(value))),
    #(
      "requestId",
      json.nullable(gap_receipt.page_request_id(value), json.string),
    ),
    #("byteLength", json.int(gap_receipt.page_byte_length(value))),
    #(
      "contentSha256",
      value
        |> gap_receipt.page_content_sha256
        |> provenance_identity.sha256_value
        |> json.string,
    ),
  ])
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
