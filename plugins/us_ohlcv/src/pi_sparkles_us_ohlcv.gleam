import finance_core/adjustment
import finance_core/currency
import finance_core/decimal
import finance_core/identifier as core_identifier
import finance_core/market
import finance_core/observation.{type Observation}
import finance_core/source
import finance_core/time
import finance_http/response as http_response
import finance_http/transport
import finance_market_alpaca
import finance_market_alpaca/bars as alpaca_bars
import finance_market_alpaca/query
import finance_market_alpaca/request as provider_request
import finance_market_alpaca/runtime
import finance_ohlcv
import finance_ohlcv/series_handoff
import finance_provenance/hash
import finance_provenance/identity
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import finance_us_ohlcv/gap_receipt
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
import pi_sparkles_us_ohlcv/effect/environment
import pi_sparkles_us_ohlcv/normalization

pub type Input {
  Input(
    symbol: String,
    mic: Option(String),
    start_date: time.Date,
    end_date: time.Date,
    as_of_date: time.Date,
    feed: query.Feed,
    page_size: Int,
    maximum_pages: Int,
    maximum_bars: Int,
  )
}

type Provider {
  Ready(access: finance_market_alpaca.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

type FetchOutcome {
  FetchOutcome(
    bars: List(alpaca_bars.RawBar),
    pages_fetched: Int,
    pagination: finance_ohlcv.Pagination,
    next_page_token: Option(String),
    request_ids: List(String),
    page_receipts: List(gap_receipt.Page),
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register_compact(
    api,
    "us_stock_ohlcv",
    "US exact daily OHLCV",
    "Fetch bounded raw-adjustment Alpaca daily US stock bars for an exact symbol/as-of identity and explicit IEX or SIP feed; use OHLCV evidence by default for ordinary buy-now, sell-timing, entry, exit, stop, target, trend, momentum, or volatility questions even when the user does not explicitly request tools; preserve source numeric lexemes, page-body hashes, a canonical gap-projection digest, pagination, entitlement, and unassessed calendar gaps",
    "Retrieve reproducible daily US OHLCV for current-data-dependent opinions without feed fallback, adjustment, synthetic bars, or guessed closures and suspensions",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case plan(input) {
            Error(_) -> tool.reject("Invalid bounded US Alpaca OHLCV query")
            Ok(query_plan) -> {
              use fetched <- promise.await(
                fetch_pages(
                  provider_runtime,
                  access,
                  query_plan,
                  id,
                  transport.from_abort_signal(raw.dynamic(signal)),
                  None,
                  [],
                  0,
                  [],
                  [],
                  [],
                ),
              )
              case fetched {
                Error(message) -> tool.reject(message)
                Ok(outcome) -> {
                  let assert Ok(retrieved_at) =
                    time.instant(environment.now_milliseconds())
                  case
                    normalization.batch(
                      query_plan,
                      outcome.bars,
                      retrieved_at,
                      outcome.pagination,
                    )
                  {
                    Error(error) ->
                      tool.reject(
                        "Alpaca bars failed exact OHLCV validation: "
                        <> string.inspect(error),
                      )
                    Ok(batch) ->
                      case
                        build_gap_receipt(
                          query_plan,
                          batch,
                          outcome,
                          retrieved_at,
                        )
                      {
                        Error(message) -> tool.reject(message)
                        Ok(#(receipt, digest)) ->
                          case
                            history_series_handoff(
                              input,
                              query_plan,
                              batch,
                              retrieved_at,
                              receipt,
                            )
                          {
                            Error(message) -> tool.reject(message)
                            Ok(series_value) -> {
                              case series_value {
                                Some(value) ->
                                  pi.append_entry(
                                    api,
                                    series_handoff.event_type,
                                    raw.dynamic(series_handoff.encode(value)),
                                  )
                                None -> Nil
                              }
                              let details =
                                result_json(
                                  input,
                                  query_plan,
                                  batch,
                                  outcome,
                                  retrieved_at,
                                  receipt,
                                  digest,
                                  series_value,
                                )
                              tool.text_result(
                                model_content(
                                  render(query_plan, batch, outcome),
                                  query_plan,
                                  batch,
                                  retrieved_at,
                                  receipt,
                                  digest,
                                  series_value,
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
      }
    },
  )
  promise.resolve(Nil)
}

fn provider() -> Provider {
  case
    finance_market_alpaca.access(
      environment.key_id(),
      environment.secret_key(),
      environment.product(),
      environment.contact(),
    )
  {
    Error(_) ->
      InvalidConfiguration(
        "Alpaca OHLCV requires AGENT_CONTACT, ALPACA_API_KEY_ID, and ALPACA_API_SECRET_KEY",
      )
    Ok(access) ->
      case runtime.new() {
        Ok(provider_runtime) -> Ready(access, provider_runtime)
        Error(_) ->
          InvalidConfiguration(
            "Alpaca bounded market-data runtime could not initialize safely",
          )
      }
  }
}

fn plan(input: Input) -> Result(query.DailyBarsQuery, query.QueryError) {
  query.daily_bars(
    input.symbol,
    input.start_date,
    input.end_date,
    input.as_of_date,
    input.feed,
    input.page_size,
    input.maximum_pages,
    input.maximum_bars,
  )
}

fn fetch_pages(
  provider_runtime: runtime.Runtime,
  access: finance_market_alpaca.Access,
  plan: query.DailyBarsQuery,
  id: String,
  cancellation: transport.Cancellation,
  page_token: Option(String),
  seen_tokens: List(String),
  pages_fetched: Int,
  accumulated: List(alpaca_bars.RawBar),
  request_ids: List(String),
  page_receipts: List(gap_receipt.Page),
) -> Promise(Result(FetchOutcome, String)) {
  let remaining = query.maximum_bars(plan) - list.length(accumulated)
  let page_limit = int.min(query.page_size(plan), remaining)
  case page_limit <= 0 {
    True ->
      promise.resolve(
        Ok(FetchOutcome(
          accumulated,
          pages_fetched,
          finance_ohlcv.TruncatedByBarBudget(query.maximum_bars(plan)),
          page_token,
          request_ids,
          page_receipts,
        )),
      )
    False ->
      case provider_request.daily_bars(access, plan, page_limit, page_token) {
        Error(_) -> promise.resolve(Error("Alpaca bars request was invalid"))
        Ok(request_value) -> {
          use response <- promise.await(runtime.send(
            provider_runtime,
            id: id <> ":page:" <> int.to_string(pages_fetched + 1),
            request: request_value,
            cancellation: cancellation,
          ))
          case checked_response(response) {
            Error(message) -> promise.resolve(Error(message))
            Ok(response_value) ->
              case response_page_receipt(response_value, pages_fetched + 1) {
                Error(message) -> promise.resolve(Error(message))
                Ok(page_receipt) ->
                  case
                    alpaca_bars.decode_page(
                      http_response.body(response_value),
                      for: plan,
                      page_limit: page_limit,
                    )
                  {
                    Error(_) ->
                      promise.resolve(Error(
                        "Alpaca returned invalid, mismatched, or over-budget daily bars",
                      ))
                    Ok(page) -> {
                      let combined =
                        list.append(accumulated, alpaca_bars.bars(page))
                      let next_pages = pages_fetched + 1
                      let next_page_receipts =
                        list.append(page_receipts, [page_receipt])
                      let next_request_ids = case
                        http_response.first_header(
                          response_value,
                          name: "x-request-id",
                        )
                      {
                        Some(value) -> list.append(request_ids, [value])
                        None -> request_ids
                      }
                      case alpaca_bars.next_page_token(page) {
                        None ->
                          promise.resolve(
                            Ok(FetchOutcome(
                              combined,
                              next_pages,
                              finance_ohlcv.AllPages,
                              None,
                              next_request_ids,
                              next_page_receipts,
                            )),
                          )
                        Some(next_token) ->
                          case
                            list.contains(seen_tokens, next_token)
                            || page_token == Some(next_token),
                            list.length(combined) >= query.maximum_bars(plan),
                            next_pages >= query.maximum_pages(plan)
                          {
                            True, _, _ ->
                              promise.resolve(Error(
                                "Alpaca repeated a pagination token; pagination stopped safely",
                              ))
                            _, True, _ ->
                              promise.resolve(
                                Ok(FetchOutcome(
                                  combined,
                                  next_pages,
                                  finance_ohlcv.TruncatedByBarBudget(
                                    query.maximum_bars(plan),
                                  ),
                                  Some(next_token),
                                  next_request_ids,
                                  next_page_receipts,
                                )),
                              )
                            _, _, True ->
                              promise.resolve(
                                Ok(FetchOutcome(
                                  combined,
                                  next_pages,
                                  finance_ohlcv.TruncatedByPageBudget(
                                    query.maximum_pages(plan),
                                  ),
                                  Some(next_token),
                                  next_request_ids,
                                  next_page_receipts,
                                )),
                              )
                            False, False, False ->
                              fetch_pages(
                                provider_runtime,
                                access,
                                plan,
                                id,
                                cancellation,
                                Some(next_token),
                                [next_token, ..seen_tokens],
                                next_pages,
                                combined,
                                next_request_ids,
                                next_page_receipts,
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

fn checked_response(
  outcome: Result(http_response.Response, runtime.SendError),
) -> Result(http_response.Response, String) {
  case outcome {
    Error(error) ->
      Error("Alpaca bars request failed safely: " <> string.inspect(error))
    Ok(value) -> {
      let status = http_response.status(value)
      case status >= 200 && status < 300 {
        True -> Ok(value)
        False if status == 401 || status == 403 ->
          Error(
            "Alpaca rejected the credentials or selected feed entitlement (HTTP "
            <> int.to_string(status)
            <> ")",
          )
        False ->
          Error("Alpaca bars request returned HTTP " <> int.to_string(status))
      }
    }
  }
}

fn response_page_receipt(
  response: http_response.Response,
  sequence: Int,
) -> Result(gap_receipt.Page, String) {
  use content_hash <- result.try(
    hash.text(http_response.body(response))
    |> result.map_error(fn(_) {
      "Alpaca response content could not be hashed safely"
    }),
  )
  gap_receipt.page(
    sequence,
    http_response.first_header(response, name: "x-request-id"),
    http_response.byte_length(response),
    content_hash,
  )
  |> result.map_error(fn(_) {
    "Alpaca response page receipt was structurally invalid"
  })
}

fn build_gap_receipt(
  plan: query.DailyBarsQuery,
  batch: finance_ohlcv.Batch,
  fetched: FetchOutcome,
  retrieved_at: time.Instant,
) -> Result(#(gap_receipt.Receipt, identity.Sha256), String) {
  let bar_dates =
    batch
    |> finance_ohlcv.observations
    |> list.map(fn(observation) {
      observation.value |> finance_ohlcv.session_date
    })
  use receipt <- result.try(
    gap_receipt.new(
      provider: "alpaca",
      symbol: query.symbol(plan),
      start_date: query.start_date(plan),
      end_date: query.end_date(plan),
      identity_as_of: query.as_of_date(plan),
      feed: query.feed_name(query.feed(plan)),
      source_reference: query.daily_bars_source_reference(plan),
      retrieved_at: retrieved_at,
      pagination: receipt_pagination(fetched.pagination),
      pages: fetched.page_receipts,
      bar_dates: bar_dates,
    )
    |> result.map_error(fn(_) {
      "Alpaca gap-assessment receipt was structurally invalid"
    }),
  )
  use digest <- result.try(
    receipt
    |> gap_receipt.canonical_text
    |> hash.text
    |> result.map_error(fn(_) {
      "Alpaca gap-assessment receipt could not be hashed safely"
    }),
  )
  Ok(#(receipt, digest))
}

fn receipt_pagination(
  value: finance_ohlcv.Pagination,
) -> gap_receipt.Pagination {
  case value {
    finance_ohlcv.AllPages -> gap_receipt.Complete
    finance_ohlcv.TruncatedByPageBudget(_) -> gap_receipt.TruncatedByPageBudget
    finance_ohlcv.TruncatedByBarBudget(_) -> gap_receipt.TruncatedByBarBudget
  }
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "symbol",
      schema.string()
        |> schema.with_string_length(1, 20)
        |> schema.described(
          "Exact uppercase Alpaca US stock symbol; not a company-name search",
        ),
    ),
    schema.Optional(
      "mic",
      schema.string_enum(["XNYS", "XNAS"])
        |> schema.described(
          "Exact caller-proven listing MIC. Supply it when indicators or charts need a session-bound seriesReceipt; Alpaca does not prove this venue",
        ),
    ),
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
    schema.Required(
      "asOf",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described(
          "YYYY-MM-DD identity date used by Alpaca for symbol-change mapping",
        ),
    ),
    schema.Required(
      "feed",
      schema.string_enum(["iex", "sip"])
        |> schema.described(
          "Explicit data feed; IEX and consolidated SIP coverage are not equivalent",
        ),
    ),
    schema.Optional(
      "pageSize",
      schema.integer()
        |> schema.with_number_range(1.0, 1000.0)
        |> schema.described("Maximum bars per provider page; defaults to 1000"),
    ),
    schema.Optional(
      "maxPages",
      schema.integer()
        |> schema.with_number_range(1.0, 10.0)
        |> schema.described("Maximum fetched pages; defaults to 5"),
    ),
    schema.Optional(
      "maxBars",
      schema.integer()
        |> schema.with_number_range(1.0, 5000.0)
        |> schema.described("Maximum source bars; defaults to 2000"),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use symbol <- decode.field("symbol", decode.string)
  use mic <- decode.optional_field("mic", None, decode.optional(decode.string))
  use start <- decode.field("startDate", decode.string)
  use end <- decode.field("endDate", decode.string)
  use as_of <- decode.field("asOf", decode.string)
  use feed <- decode.field("feed", decode.string)
  use page_size <- decode.optional_field("pageSize", 1000, decode.int)
  use maximum_pages <- decode.optional_field("maxPages", 5, decode.int)
  use maximum_bars <- decode.optional_field("maxBars", 2000, decode.int)
  let assert Ok(placeholder) = time.date(1970, 1, 1)
  case
    parse_mic(mic),
    parse_date(start),
    parse_date(end),
    parse_date(as_of),
    parse_feed(feed)
  {
    Ok(mic_value), Ok(start_date), Ok(end_date), Ok(as_of_date), Ok(feed_value)
    ->
      decode.success(Input(
        symbol,
        mic_value,
        start_date,
        end_date,
        as_of_date,
        feed_value,
        page_size,
        maximum_pages,
        maximum_bars,
      ))
    _, _, _, _, _ ->
      decode.failure(
        Input(
          "AAPL",
          None,
          placeholder,
          placeholder,
          placeholder,
          query.Iex,
          1000,
          5,
          2000,
        ),
        "valid US OHLCV dates and feed",
      )
  }
}

fn parse_mic(value: Option(String)) -> Result(Option(String), Nil) {
  case value {
    None -> Ok(None)
    Some("XNYS") -> Ok(Some("XNYS"))
    Some("XNAS") -> Ok(Some("XNAS"))
    Some(_) -> Error(Nil)
  }
}

fn parse_feed(value: String) -> Result(query.Feed, Nil) {
  case value {
    "iex" -> Ok(query.Iex)
    "sip" -> Ok(query.Sip)
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
  let assert Ok(zone) = time.timezone("America/New_York")
  let venue_mic = case input.mic {
    Some(value) -> {
      let assert Ok(mic) = core_identifier.mic(value)
      Some(mic)
    }
    None -> None
  }
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Us,
      market_scope: "us_stock_ohlcv",
      venue_mic: venue_mic,
      board: None,
      timezone: Some(zone),
      source_language: "en-US",
      providers: ["alpaca", query.feed_name(input.feed)],
      entitlement: entitlement(input.feed),
      limitations: limitations(input.feed),
    )
  value
}

fn entitlement(feed: query.Feed) -> String {
  case feed {
    query.Iex -> "credentialed_iex_historical"
    query.Sip -> "credentialed_sip_historical"
  }
}

fn limitations(feed: query.Feed) -> List(String) {
  [
    case feed {
      query.Iex -> "iex_only_not_consolidated_us_volume"
      query.Sip -> "sip_access_depends_on_user_subscription"
    },
    "alpaca_symbol_asof_is_not_authoritative_listing_identity",
    "raw_daily_provider_aggregation_only",
    "provider_1day_session_membership_not_independently_verified",
    "reviewed_us_calendar_and_status_source_not_composed",
    "missing_sessions_are_not_classified",
    "corporate_action_adjustments_unavailable",
    "redistribution_not_granted_by_plugin",
    "no_feed_fallback_or_stale_substitution",
  ]
}

fn render(
  plan: query.DailyBarsQuery,
  batch: finance_ohlcv.Batch,
  fetched: FetchOutcome,
) -> String {
  "US track | Alpaca "
  <> string.uppercase(query.feed_name(query.feed(plan)))
  <> " raw daily OHLCV | "
  <> query.symbol(plan)
  <> " | "
  <> int.to_string(list.length(finance_ohlcv.observations(batch)))
  <> " bars | calendar gaps not assessed | "
  <> pagination_name(fetched.pagination)
}

fn model_content(
  summary: String,
  plan: query.DailyBarsQuery,
  batch: finance_ohlcv.Batch,
  retrieved_at: time.Instant,
  receipt: gap_receipt.Receipt,
  receipt_digest: identity.Sha256,
  series_value: Option(series_handoff.Handoff),
) -> String {
  summary
  <> series_handoff_instruction(series_value)
  <> "track=us;provider=alpaca;feed="
  <> query.feed_name(query.feed(plan))
  <> ";symbol="
  <> query.symbol(plan)
  <> ";currency=USD;volumeUnit=shares;frequency=daily;adjustment=raw;retrievedAtUnixMilliseconds="
  <> int.to_string(time.unix_milliseconds(retrieved_at))
  <> ";gapAssessmentReceiptDigest="
  <> identity.sha256_value(receipt_digest)
  <> ";acquisitionReceipt="
  <> identity.sha256_value(receipt_digest)
  <> series_handoff_fields(series_value)
  <> ";sourceReference="
  <> gap_receipt.source_reference(receipt)
  <> "\ndate,provider_timestamp,open,high,low,close,volume,trade_count,vwap\n"
  <> {
    finance_ohlcv.observations(batch)
    |> list.map(fn(observation) {
      let bar = observation.value
      [
        date_text(finance_ohlcv.session_date(bar)),
        finance_ohlcv.source_timestamp(bar),
        finance_ohlcv.raw(finance_ohlcv.open(bar)),
        finance_ohlcv.raw(finance_ohlcv.high(bar)),
        finance_ohlcv.raw(finance_ohlcv.low(bar)),
        finance_ohlcv.raw(finance_ohlcv.close(bar)),
        finance_ohlcv.raw(finance_ohlcv.volume(bar)),
        optional_count_raw(finance_ohlcv.trade_count(bar)),
        optional_exact_raw(finance_ohlcv.vwap(bar)),
      ]
      |> string.join(",")
    })
    |> string.join("\n")
  }
}

fn optional_count_raw(value: Option(finance_ohlcv.ExactCount)) -> String {
  case value {
    Some(value) -> finance_ohlcv.count_raw(value)
    None -> ""
  }
}

fn optional_exact_raw(value: Option(finance_ohlcv.ExactValue)) -> String {
  case value {
    Some(value) -> finance_ohlcv.raw(value)
    None -> ""
  }
}

fn result_json(
  input: Input,
  plan: query.DailyBarsQuery,
  batch: finance_ohlcv.Batch,
  fetched: FetchOutcome,
  retrieved_at: time.Instant,
  receipt: gap_receipt.Receipt,
  receipt_digest: identity.Sha256,
  series_value: Option(series_handoff.Handoff),
) -> json.Json {
  json.object(
    list.append(track_json.result_fields(result_context(input)), [
      #("provider", json.string("alpaca")),
      #("route", json.string("direct")),
      #("feed", json.string(query.feed_name(query.feed(plan)))),
      #("symbol", json.string(query.symbol(plan))),
      #("identityAsOf", json.string(query.date_text(query.as_of_date(plan)))),
      #("startDate", json.string(query.date_text(query.start_date(plan)))),
      #("endDate", json.string(query.date_text(query.end_date(plan)))),
      #("interval", json.string("1_day")),
      #("session", json.string(session_name(finance_ohlcv.session(batch)))),
      #("sessionTimezone", json.string("America/New_York")),
      #("currency", json.string(currency.code(finance_ohlcv.currency(batch)))),
      #("volumeUnit", json.string("shares")),
      #(
        "adjustment",
        json.string(adjustment_name(finance_ohlcv.adjustment(batch))),
      ),
      #(
        "retrievedAtUnixMilliseconds",
        json.int(time.unix_milliseconds(retrieved_at)),
      ),
      #("pagesFetched", json.int(fetched.pages_fetched)),
      #("requestIds", json.array(fetched.request_ids, json.string)),
      #(
        "pagination",
        pagination_json(fetched.pagination, fetched.next_page_token),
      ),
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
        json.string(identity.sha256_value(receipt_digest)),
      ),
      #("seriesReceipt", case series_value {
        Some(value) -> json.string(series_handoff.receipt(value))
        None -> json.null()
      }),
      #("seriesHandoff", series_handoff_status_json(series_value)),
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
      #("bars", json.array(finance_ohlcv.observations(batch), bar_json)),
      #("entitlement", json.string(entitlement(query.feed(plan)))),
      #("redistribution", json.string("not_granted_by_plugin")),
      #("limitations", json.array(limitations(query.feed(plan)), json.string)),
    ]),
  )
}

fn history_series_handoff(
  input: Input,
  plan: query.DailyBarsQuery,
  batch: finance_ohlcv.Batch,
  retrieved_at: time.Instant,
  receipt: gap_receipt.Receipt,
) -> Result(Option(series_handoff.Handoff), String) {
  case input.mic {
    None -> Ok(None)
    Some(mic) -> {
      let bars =
        finance_ohlcv.observations(batch)
        |> list.map(fn(observation) {
          let bar = observation.value
          series_handoff.Bar(
            date: date_text(finance_ohlcv.session_date(bar)),
            open: finance_ohlcv.raw(finance_ohlcv.open(bar)),
            high: finance_ohlcv.raw(finance_ohlcv.high(bar)),
            low: finance_ohlcv.raw(finance_ohlcv.low(bar)),
            close: finance_ohlcv.raw(finance_ohlcv.close(bar)),
            volume: finance_ohlcv.raw(finance_ohlcv.volume(bar)),
            amount: "unknown",
          )
        })
      series_handoff.new(
        track: "us",
        instrument_id: query.symbol(plan),
        mic: mic,
        timezone: "America/New_York",
        source_language: "en-US",
        price_unit: "USD",
        volume_unit: "shares",
        adjustment: "raw",
        provider: "alpaca",
        source_reference: gap_receipt.source_reference(receipt),
        retrieved_at_unix_milliseconds: time.unix_milliseconds(retrieved_at),
        source_cutoff_unix_milliseconds: None,
        entitlement: entitlement(query.feed(plan)),
        limitations: list.append(limitations(query.feed(plan)), [
          "provider_amount_unavailable_for_series_handoff",
        ]),
        bars: bars,
      )
      |> result.map(Some)
      |> result.map_error(fn(error) {
        "US OHLCV series handoff could not be created: "
        <> series_handoff.error_message(error)
      })
    }
  }
}

fn series_handoff_instruction(value: Option(series_handoff.Handoff)) -> String {
  case value {
    Some(_) ->
      "\nComplete bounded, exact de-duplicated daily rows follow as CSV. This exact active-session series is already registered: for sma, rsi, atr, or chart_ohlcv pass only seriesReceipt with the requested calculation/chart fields. Never copy these rows into those installed tools, never use acquisitionReceipt or gapAssessmentReceiptDigest as seriesReceipt, and never manufacture an instructionRef or use a script for the handoff.\n"
    None ->
      "\nComplete bounded, exact de-duplicated daily rows follow as CSV. No session seriesReceipt was created because the request omitted an exact caller-proven XNYS or XNAS MIC and Alpaca does not prove listing venue. Never use acquisitionReceipt or gapAssessmentReceiptDigest as seriesReceipt and do not retry receipt-mode indicators or charts; retain this enrichment as unavailable unless exact MIC evidence is supplied in a new request.\n"
  }
}

fn series_handoff_fields(value: Option(series_handoff.Handoff)) -> String {
  case value {
    Some(series_value) ->
      ";seriesReceipt="
      <> series_handoff.receipt(series_value)
      <> ";seriesHandoff=session_bound_v1_use_receipt_for_sma_rsi_atr_chart"
    None ->
      ";seriesReceipt=unavailable;seriesHandoff=track_partial_missing_exact_mic"
  }
}

fn series_handoff_status_json(
  value: Option(series_handoff.Handoff),
) -> json.Json {
  case value {
    Some(_) ->
      json.object([
        #("state", json.string("supported")),
        #("reason", json.null()),
      ])
    None ->
      json.object([
        #("state", json.string("track_partial")),
        #("reason", json.string("missing_exact_caller_proven_mic")),
      ])
  }
}

fn gap_assessment_receipt_json(
  value: gap_receipt.Receipt,
  digest: identity.Sha256,
) -> json.Json {
  json.object([
    #("schema", json.string(gap_receipt.schema_name)),
    #("schemaVersion", json.int(gap_receipt.schema_version)),
    #("digestAlgorithm", json.string(gap_receipt.digest_algorithm)),
    #("digest", json.string(identity.sha256_value(digest))),
    #("provider", json.string(gap_receipt.provider(value))),
    #("symbol", json.string(gap_receipt.symbol(value))),
    #("startDate", json.string(date_text(gap_receipt.start_date(value)))),
    #("endDate", json.string(date_text(gap_receipt.end_date(value)))),
    #("identityAsOf", json.string(date_text(gap_receipt.identity_as_of(value)))),
    #("feed", json.string(gap_receipt.feed(value))),
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
        #("scope", json.string("canonical_gap_projection_v1")),
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
        |> identity.sha256_value
        |> json.string,
    ),
  ])
}

fn bar_json(value: Observation(finance_ohlcv.Bar)) -> json.Json {
  let bar = value.value
  json.object([
    #("providerTimestamp", json.string(finance_ohlcv.source_timestamp(bar))),
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
        #("tradeCount", count_raw_json(finance_ohlcv.trade_count(bar))),
        #("vwap", exact_raw_json(finance_ohlcv.vwap(bar))),
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
        #("tradeCount", count_json(finance_ohlcv.trade_count(bar))),
        #("vwap", exact_json(finance_ohlcv.vwap(bar))),
      ]),
    ),
  ])
}

fn pagination_json(
  value: finance_ohlcv.Pagination,
  next_token: Option(String),
) -> json.Json {
  json.object([
    #("state", json.string(pagination_name(value))),
    #("nextPageTokenAvailable", json.bool(next_token != None)),
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

fn exact_raw_json(value: Option(finance_ohlcv.ExactValue)) -> json.Json {
  case value {
    Some(value) -> json.string(finance_ohlcv.raw(value))
    None -> json.null()
  }
}

fn exact_json(value: Option(finance_ohlcv.ExactValue)) -> json.Json {
  case value {
    Some(value) -> decimal_json(value)
    None -> json.null()
  }
}

fn count_raw_json(value: Option(finance_ohlcv.ExactCount)) -> json.Json {
  case value {
    Some(value) -> json.string(finance_ohlcv.count_raw(value))
    None -> json.null()
  }
}

fn count_json(value: Option(finance_ohlcv.ExactCount)) -> json.Json {
  case value {
    Some(value) -> json.int(finance_ohlcv.count_normalized(value))
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
