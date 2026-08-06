import finance_core/currency
import finance_core/decimal
import finance_core/observation.{type Observation}
import finance_core/source
import finance_core/time
import finance_http/response as http_response
import finance_http/transport
import finance_market_alpaca
import finance_market_alpaca/query
import finance_market_alpaca/quotes as alpaca_quotes
import finance_market_alpaca/request as provider_request
import finance_market_alpaca/runtime
import finance_quote
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_us_quote/effect/environment
import pi_sparkles_us_quote/normalization

pub type Input {
  Input(symbol: String, feed: query.Feed)
}

type Provider {
  Ready(access: finance_market_alpaca.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "us_stock_quote",
    "US exact latest quote",
    "Fetch one latest Alpaca US stock best bid and ask for an exact symbol and explicit IEX or SIP feed; preserve source numeric lexemes, market codes, entitlement scope, and unknown freshness",
    "Inspect a bounded latest US quote without feed fallback, symbol search, session inference, or guessed size units",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case query.latest_quote(input.symbol, input.feed) {
            Error(_) -> tool.reject("Invalid exact US Alpaca quote query")
            Ok(plan) -> {
              let assert Ok(request_value) =
                provider_request.latest_quote(access, plan)
              use sent <- promise.await(runtime.send(
                provider_runtime,
                id: id <> ":latest-quote",
                request: request_value,
                cancellation: transport.from_abort_signal(raw.dynamic(signal)),
              ))
              case checked_response(sent) {
                Error(message) -> tool.reject(message)
                Ok(response_value) ->
                  case
                    alpaca_quotes.decode(
                      http_response.body(response_value),
                      for: plan,
                    )
                  {
                    Error(_) ->
                      tool.reject(
                        "Alpaca returned an invalid or mismatched latest quote",
                      )
                    Ok(raw_quote) -> {
                      let assert Ok(retrieved_at) =
                        time.instant(environment.now_milliseconds())
                      case normalization.quote(plan, raw_quote, retrieved_at) {
                        Error(error) ->
                          tool.reject(
                            "Alpaca quote failed exact validation: "
                            <> string.inspect(error),
                          )
                        Ok(observed) ->
                          tool.text_result(
                            render(plan, observed),
                            result_json(
                              plan,
                              observed,
                              http_response.first_header(
                                response_value,
                                name: "x-request-id",
                              ),
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
        "Alpaca quote requires ALPACA_API_KEY_ID, ALPACA_API_SECRET_KEY, and ALPACA_USER_AGENT_CONTACT; ALPACA_USER_AGENT_PRODUCT is optional",
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

fn checked_response(
  outcome: Result(http_response.Response, runtime.SendError),
) -> Result(http_response.Response, String) {
  case outcome {
    Error(error) ->
      Error("Alpaca quote request failed safely: " <> string.inspect(error))
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
          Error("Alpaca quote request returned HTTP " <> int.to_string(status))
      }
    }
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
    schema.Required(
      "feed",
      schema.string_enum(["iex", "sip"])
        |> schema.described(
          "Explicit data feed; IEX and consolidated SIP coverage are not equivalent",
        ),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use symbol <- decode.field("symbol", decode.string)
  use feed <- decode.field("feed", decode.string)
  case parse_feed(feed) {
    Ok(feed_value) -> decode.success(Input(symbol, feed_value))
    Error(_) ->
      decode.failure(
        Input("AAPL", query.Iex),
        "valid explicit Alpaca quote feed",
      )
  }
}

fn parse_feed(value: String) -> Result(query.Feed, Nil) {
  case value {
    "iex" -> Ok(query.Iex)
    "sip" -> Ok(query.Sip)
    _ -> Error(Nil)
  }
}

fn result_context(feed: query.Feed) -> track_context.Context {
  let assert Ok(zone) = time.timezone("America/New_York")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Us,
      market_scope: "us_stock_quote",
      venue_mic: None,
      board: None,
      timezone: Some(zone),
      source_language: "en-US",
      providers: ["alpaca", query.feed_name(feed)],
      entitlement: entitlement(feed),
      limitations: limitations(feed),
    )
  value
}

fn entitlement(feed: query.Feed) -> String {
  case feed {
    query.Iex -> "credentialed_iex_latest"
    query.Sip -> "credentialed_sip_latest"
  }
}

fn limitations(feed: query.Feed) -> List(String) {
  [
    case feed {
      query.Iex -> "iex_single_exchange_not_consolidated_sip"
      query.Sip -> "sip_access_and_recency_depend_on_user_subscription"
    },
    "alpaca_symbol_is_not_authoritative_listing_identity",
    "provider_size_semantics_not_normalized",
    "freshness_and_latency_not_proven",
    "market_session_not_inferred",
    "redistribution_not_granted_by_plugin",
    "no_feed_fallback_or_stale_substitution",
  ]
}

fn render(
  plan: query.LatestQuoteQuery,
  value: Observation(finance_quote.Quote),
) -> String {
  let quote = value.value
  "US track | Alpaca "
  <> string.uppercase(query.feed_name(query.quote_feed(plan)))
  <> " latest best bid/ask | "
  <> query.quote_symbol(plan)
  <> " | bid "
  <> finance_quote.raw(finance_quote.price(finance_quote.bid(quote)))
  <> " ask "
  <> finance_quote.raw(finance_quote.price(finance_quote.ask(quote)))
  <> " USD | freshness unknown"
}

fn result_json(
  plan: query.LatestQuoteQuery,
  observed: Observation(finance_quote.Quote),
  request_id: Option(String),
) -> json.Json {
  let value = observed.value
  json.object(
    list.append(
      track_json.result_fields(result_context(query.quote_feed(plan))),
      [
        #("provider", json.string("alpaca")),
        #("route", json.string("direct")),
        #("feed", json.string(query.feed_name(query.quote_feed(plan)))),
        #("symbol", json.string(query.quote_symbol(plan))),
        #("quoteType", json.string("best_bid_ask_within_selected_feed")),
        #("currency", json.string(currency.code(finance_quote.currency(value)))),
        #(
          "providerTimestamp",
          json.string(finance_quote.source_timestamp(value)),
        ),
        #(
          "asOfUnixMilliseconds",
          json.int(time.unix_milliseconds(observed.as_of)),
        ),
        #(
          "retrievedAtUnixMilliseconds",
          json.int(time.unix_milliseconds(observed.retrieved_at)),
        ),
        #("requestId", json.nullable(request_id, json.string)),
        #(
          "source",
          json.object([
            #("provider", json.string(source.provider(observed.source))),
            #("reference", json.string(source.reference(observed.source))),
          ]),
        ),
        #("bid", side_json(finance_quote.bid(value))),
        #("ask", side_json(finance_quote.ask(value))),
        #(
          "conditionCodes",
          json.array(finance_quote.conditions(value), json.string),
        ),
        #("tape", json.string(finance_quote.tape(value))),
        #("sizeUnit", json.string("provider_reported_unverified")),
        #("freshness", json.string("unknown")),
        #("latency", json.string("unknown")),
        #("session", json.string("unknown")),
        #("entitlement", json.string(entitlement(query.quote_feed(plan)))),
        #("redistribution", json.string("not_granted_by_plugin")),
        #(
          "limitations",
          json.array(limitations(query.quote_feed(plan)), json.string),
        ),
      ],
    ),
  )
}

fn side_json(value: finance_quote.Side) -> json.Json {
  json.object([
    #("exchange", json.string(finance_quote.exchange(value))),
    #("rawPrice", json.string(finance_quote.raw(finance_quote.price(value)))),
    #("normalizedPrice", decimal_json(finance_quote.price(value))),
    #("rawSize", json.string(finance_quote.raw(finance_quote.size(value)))),
    #("normalizedSize", decimal_json(finance_quote.size(value))),
  ])
}

fn decimal_json(value: finance_quote.ExactValue) -> json.Json {
  value |> finance_quote.normalized |> decimal.to_string |> json.string
}
