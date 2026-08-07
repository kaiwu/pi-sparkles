import finance_core/time
import finance_http/response as http_response
import finance_http/transport
import finance_market_alpaca
import finance_market_alpaca/assets
import finance_market_alpaca/query
import finance_market_alpaca/request as provider_request
import finance_market_alpaca/runtime
import finance_provenance/hash
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_stock_screener/domain
import pi_sparkles_stock_screener/effect/environment

type Provider {
  Ready(access: finance_market_alpaca.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "stock_universe",
    "US provider asset universe",
    "Fetch exact Alpaca US-equity asset-master rows for caller-selected paper/live, status, and exchange filters; preserve provider fields, order, hashes, limits, and unknowns without screening, ranking, qualification, or selection",
    "Inspect bounded provider universe information; the LLM decides what any row means and whether to request another operation",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          let plan = domain.plan(input)
          let assert Ok(request_value) =
            provider_request.asset_universe(access, plan)
          use sent <- promise.await(runtime.send(
            provider_runtime,
            id: id <> ":asset-universe",
            request: request_value,
            cancellation: transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case checked_response(sent) {
            Error(message) -> tool.reject(message)
            Ok(response_value) -> {
              let body = http_response.body(response_value)
              case assets.decode_snapshot(body, for: plan) {
                Error(error) ->
                  tool.reject(
                    "Alpaca returned a malformed or over-budget asset array: "
                    <> string.inspect(error),
                  )
                Ok(snapshot) -> {
                  let reference = query.asset_universe_source_reference(plan)
                  case hash.text(body), hash.text(reference <> "\n" <> body) {
                    Ok(source_receipt), Ok(universe_receipt) -> {
                      let assert Ok(retrieved_at) =
                        time.instant(environment.now_milliseconds())
                      tool.text_result(
                        domain.summary(plan, snapshot),
                        domain.result_json(
                          plan,
                          snapshot,
                          retrieved_at,
                          http_response.first_header(
                            response_value,
                            name: "x-request-id",
                          ),
                          source_receipt,
                          universe_receipt,
                        ),
                      )
                      |> promise.resolve
                    }
                    _, _ ->
                      tool.reject(
                        "Alpaca asset response could not be content-bound",
                      )
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
        "Alpaca stock universe requires ALPACA_API_KEY_ID, ALPACA_API_SECRET_KEY, and ALPACA_USER_AGENT_CONTACT; ALPACA_USER_AGENT_PRODUCT is optional",
      )
    Ok(access) ->
      case runtime.new() {
        Ok(provider_runtime) -> Ready(access, provider_runtime)
        Error(_) ->
          InvalidConfiguration(
            "Alpaca bounded read-only runtime could not initialize safely",
          )
      }
  }
}

fn checked_response(
  outcome: Result(http_response.Response, runtime.SendError),
) -> Result(http_response.Response, String) {
  case outcome {
    Error(error) ->
      Error(
        "Alpaca asset-universe request failed safely: " <> string.inspect(error),
      )
    Ok(value) -> {
      let status = http_response.status(value)
      case status >= 200 && status < 300 {
        True -> Ok(value)
        False if status == 401 || status == 403 ->
          Error(
            "Alpaca rejected the credentials or selected trading environment (HTTP "
            <> int.to_string(status)
            <> ")",
          )
        False ->
          Error(
            "Alpaca asset-universe request returned HTTP "
            <> int.to_string(status),
          )
      }
    }
  }
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "environment",
      schema.string_enum(["paper", "live"])
        |> schema.described(
          "Explicit read-only Alpaca Trading API environment; there is no fallback",
        ),
    ),
    schema.Required(
      "status",
      schema.string_enum(["active", "inactive", "all"])
        |> schema.described("Exact caller-selected Alpaca asset status filter"),
    ),
    schema.Required(
      "exchange",
      schema.string_enum([
        "AMEX",
        "ARCA",
        "BATS",
        "NYSE",
        "NASDAQ",
        "NYSEARCA",
        "OTC",
      ])
        |> schema.described("Exact caller-selected Alpaca exchange filter"),
    ),
    schema.Required(
      "maximumAssets",
      schema.integer()
        |> schema.with_number_range(1.0, 20_000.0)
        |> schema.described(
          "Maximum provider rows accepted; excess rows fail instead of truncating",
        ),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(domain.Input) {
  use environment <- decode.field("environment", decode.string)
  use status <- decode.field("status", decode.string)
  use exchange <- decode.field("exchange", decode.string)
  use maximum_assets <- decode.field("maximumAssets", decode.int)
  case domain.input(environment, status, exchange, maximum_assets) {
    Ok(value) -> decode.success(value)
    Error(_) -> {
      let assert Ok(placeholder) = domain.input("paper", "active", "NASDAQ", 1)
      decode.failure(placeholder, "valid exact Alpaca asset-universe input")
    }
  }
}
