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
import pi_sparkles_stock_screener/decode as screen_decode
import pi_sparkles_stock_screener/domain
import pi_sparkles_stock_screener/effect/environment
import pi_sparkles_stock_screener/membership
import pi_sparkles_stock_screener/membership_decode
import pi_sparkles_stock_screener/screen

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
  register_project_universe(api)
  register_screen(api)
  promise.resolve(Nil)
}

fn register_project_universe(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "project_universe",
    "Project exact point-in-time universe membership",
    "Verify one caller-supplied canonical finance_replay universe manifest and mechanically project exact cn, hk, or us listing membership at a caller-selected effective date and knowledge cutoff, preserving ended, late, unknown, conflicting, and overlapping facts",
    "Supply the exact manifest, track, effective date, knowledge cutoff, and page; the LLM chooses and interprets every source, cutoff, limitation, and next operation",
    tool.parameters(project_universe_schema(), membership_decode.input()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case membership.run(input) {
        Ok(value) ->
          tool.text_result(value.summary, value.details)
          |> promise.resolve
        Error(error) -> tool.reject(membership.error_message(error))
      }
    },
  )
}

fn register_screen(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "screen",
    "Calculate exact caller-defined stock predicates",
    "Verify caller-supplied canonical universe and dataset manifests, then calculate exact field-versus-constant decimal predicates over bounded dated rows with matched, not-matched, and unresolved facts and stable caller-selected paging",
    "Supply every manifest, row, fact, receipt, predicate, relation policy, and page explicitly; the LLM alone interprets the mechanical relation and chooses any next operation",
    tool.parameters(screen_schema(), screen_decode.screen()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case screen.run(input) {
        Ok(value) ->
          tool.text_result(value.summary, value.details)
          |> promise.resolve
        Error(error) -> tool.reject(screen.error_message(error))
      }
    },
  )
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

fn screen_schema() -> schema.Schema {
  schema.object([
    schema.Required("context", screen_context_schema()),
    schema.Required(
      "predicates",
      schema.array(predicate_schema()) |> schema.with_array_length(1, 20),
    ),
    schema.Required(
      "rows",
      schema.array(screen_row_schema()) |> schema.with_array_length(1, 2000),
    ),
    schema.Required(
      "relation",
      schema.object([
        schema.Required(
          "matchPolicy",
          schema.string_enum(["all_predicates_observed_true_v1"]),
        ),
        schema.Required(
          "unresolvedPolicy",
          schema.string_enum(["preserve_unresolved_separately_v1"]),
        ),
      ]),
    ),
    schema.Required(
      "page",
      schema.object([
        schema.Required(
          "partition",
          schema.string_enum([
            "matched",
            "not_matched",
            "unresolved",
            "all",
          ]),
        ),
        schema.Required("offset", bounded_integer(0.0, 2000.0)),
        schema.Required("limit", bounded_integer(1.0, 200.0)),
      ]),
    ),
  ])
}

fn project_universe_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("effectiveDate", date_schema()),
    schema.Required(
      "knowledgeCutoffUnixMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("universe", canonical_manifest_schema("universe")),
    schema.Required(
      "page",
      schema.object([
        schema.Required(
          "partition",
          schema.string_enum(["member", "not_member", "unresolved", "all"]),
        ),
        schema.Required("offset", bounded_integer(0.0, 10_000.0)),
        schema.Required("limit", bounded_integer(1.0, 200.0)),
      ]),
    ),
  ])
}

fn screen_context_schema() -> schema.Schema {
  schema.object([
    schema.Required("instructionRef", hash_schema()),
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("dateStart", date_schema()),
    schema.Required("dateEnd", date_schema()),
    schema.Required(
      "sourceCutoffUnixMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("universe", canonical_manifest_schema("universe")),
    schema.Required("dataset", canonical_manifest_schema("dataset")),
    schema.Required(
      "technicalReceiptRoots",
      schema.array(hash_schema()) |> schema.with_array_length(0, 10_000),
    ),
  ])
}

fn canonical_manifest_schema(kind: String) -> schema.Schema {
  schema.object([
    schema.Required(
      "manifestJson",
      bounded_string(1, 10_000_000)
        |> schema.described(
          "Exact canonical finance_replay " <> kind <> " envelope bytes",
        ),
    ),
    schema.Required("manifestHash", hash_schema()),
  ])
}

fn predicate_schema() -> schema.Schema {
  schema.object([
    schema.Required("id", bounded_string(1, 200)),
    schema.Required(
      "leftOperand",
      schema.object([
        schema.Required("kind", schema.string_enum(["field"])),
        schema.Required("field", bounded_string(1, 200)),
        schema.Required("unit", bounded_string(1, 200)),
      ]),
    ),
    schema.Required(
      "operator",
      schema.string_enum([
        "greater_than",
        "greater_than_or_equal",
        "less_than",
        "less_than_or_equal",
        "equal",
        "not_equal",
      ]),
    ),
    schema.Required(
      "rightOperand",
      schema.object([
        schema.Required("kind", schema.string_enum(["constant"])),
        schema.Required("raw", bounded_string(1, 4000)),
        schema.Required("unit", bounded_string(1, 200)),
      ]),
    ),
  ])
}

fn screen_row_schema() -> schema.Schema {
  schema.object([
    schema.Required("listingId", bounded_string(1, 2000)),
    schema.Required("mic", bounded_string(1, 50)),
    schema.Required("observationDate", date_schema()),
    schema.Required("observationId", bounded_string(1, 2000)),
    schema.Required(
      "values",
      schema.array(screen_value_schema()) |> schema.with_array_length(0, 100),
    ),
  ])
}

fn screen_value_schema() -> schema.Schema {
  schema.object([
    schema.Required("field", bounded_string(1, 200)),
    schema.Required("unit", bounded_string(1, 200)),
    schema.Required(
      "sourceKind",
      schema.string_enum(["dataset_observation", "technical_receipt"]),
    ),
    schema.Required(
      "knownAtUnixMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required(
      "evidenceRoots",
      schema.array(hash_schema()) |> schema.with_array_length(1, 10_000),
    ),
    schema.Required("fact", screen_fact_schema()),
  ])
}

fn screen_fact_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum([
        "known",
        "unknown",
        "not_obtained",
        "not_applicable",
        "decode_failure",
        "conflicting",
      ]),
    ),
    schema.Optional("raw", schema.nullable(bounded_string(1, 4000))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 2000))),
    schema.Required(
      "alternatives",
      schema.array(bounded_string(1, 4000)) |> schema.with_array_length(0, 20),
    ),
  ])
}

fn date_schema() -> schema.Schema {
  schema.string()
  |> schema.with_string_length(10, 10)
  |> schema.described("Canonical Gregorian YYYY-MM-DD")
}

fn hash_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(64, 64)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Float, maximum: Float) -> schema.Schema {
  schema.integer() |> schema.with_number_range(minimum, maximum)
}
