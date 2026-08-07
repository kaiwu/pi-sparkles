import finance_core/time
import finance_market_alpaca/assets
import finance_market_alpaca/query
import finance_provenance/identity
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub opaque type Input {
  Input(plan: query.AssetUniverseQuery)
}

pub type InputError {
  InvalidEnvironment
  InvalidStatus
  InvalidExchange
  InvalidMaximumAssets
}

pub fn input(
  environment: String,
  status: String,
  exchange: String,
  maximum_assets: Int,
) -> Result(Input, InputError) {
  use environment_value <- result.try(parse_environment(environment))
  use status_value <- result.try(parse_status(status))
  use exchange_value <- result.try(parse_exchange(exchange))
  query.asset_universe(
    environment_value,
    status_value,
    exchange_value,
    maximum_assets,
  )
  |> result.map(Input)
  |> result.map_error(fn(_) { InvalidMaximumAssets })
}

pub fn plan(value: Input) -> query.AssetUniverseQuery {
  value.plan
}

pub fn summary(
  plan: query.AssetUniverseQuery,
  snapshot: assets.Snapshot,
) -> String {
  "US track | Alpaca asset universe | "
  <> environment_name(query.asset_environment(plan))
  <> " "
  <> query.asset_status_name(query.asset_status(plan))
  <> " "
  <> query.asset_exchange_name(query.asset_exchange(plan))
  <> " | "
  <> int.to_string(list.length(assets.rows(snapshot)))
  <> " provider rows | no screening or ranking performed"
}

pub fn result_json(
  plan: query.AssetUniverseQuery,
  snapshot: assets.Snapshot,
  retrieved_at: time.Instant,
  request_id: Option(String),
  source_receipt: identity.Sha256,
  universe_receipt: identity.Sha256,
) -> json.Json {
  let rows = assets.rows(snapshot)
  json.object(
    list.append(track_json.result_fields(result_context()), [
      #("provider", json.string("alpaca")),
      #("route", json.string("direct")),
      #(
        "environment",
        query.asset_environment(plan) |> environment_name |> json.string,
      ),
      #(
        "filters",
        json.object([
          #(
            "status",
            query.asset_status(plan)
              |> query.asset_status_name
              |> json.string,
          ),
          #("assetClass", json.string("us_equity")),
          #(
            "exchange",
            query.asset_exchange(plan)
              |> query.asset_exchange_name
              |> json.string,
          ),
        ]),
      ),
      #(
        "sourceReference",
        query.asset_universe_source_reference(plan) |> json.string,
      ),
      #("requestId", json.nullable(request_id, json.string)),
      #(
        "retrievedAtUnixMilliseconds",
        retrieved_at |> time.unix_milliseconds |> json.int,
      ),
      #(
        "sourceCutoffUnixMilliseconds",
        retrieved_at |> time.unix_milliseconds |> json.int,
      ),
      #(
        "asOfState",
        json.string("retrieval_time_only_no_historical_asof_parameter"),
      ),
      #("sourceReceipt", source_receipt |> identity.sha256_value |> json.string),
      #(
        "universeReceipt",
        universe_receipt |> identity.sha256_value |> json.string,
      ),
      #(
        "rowBudget",
        json.object([
          #("maximum", json.int(query.maximum_assets(plan))),
          #("received", json.int(list.length(rows))),
          #("outcome", json.string("within_bound")),
        ]),
      ),
      #("providerOrder", json.string("asset_class_exchange_symbol")),
      #(
        "populationState",
        json.string("provider_response_array_copied_within_bounds"),
      ),
      #("rows", json.array(rows, asset_json)),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
      #("entitlement", json.string("credentialed_trading_asset_master")),
      #("redistribution", json.string("not_granted_by_plugin")),
      #("limitations", json.array(limitations(), json.string)),
    ]),
  )
}

pub fn limitations() -> List(String) {
  [
    "alpaca_asset_master_is_provider_catalogue_not_authoritative_listing_identity",
    "provider_endpoint_has_no_historical_asof_parameter",
    "provider_status_and_capability_flags_are_information_not_eligibility",
    "returned_rows_are_not_ranked_qualified_selected_or_recommended",
    "provider_response_hash_is_not_a_provider_signature",
    "redistribution_not_granted_by_plugin",
    "no_environment_status_exchange_or_provider_fallback",
  ]
}

fn asset_json(value: assets.Asset) -> json.Json {
  json.object([
    #("providerRowId", json.string(assets.id(value))),
    #("providerMembership", json.string("provider_returned_row")),
    #("class", json.string(assets.asset_class(value))),
    #("exchange", json.string(assets.exchange(value))),
    #("symbol", json.string(assets.symbol(value))),
    #("name", json.string(assets.name(value))),
    #("status", json.string(assets.status(value))),
    #("tradable", json.bool(assets.tradable(value))),
    #("marginable", json.bool(assets.marginable(value))),
    #("shortable", json.bool(assets.shortable(value))),
    #("easyToBorrow", json.bool(assets.easy_to_borrow(value))),
    #("fractionable", json.bool(assets.fractionable(value))),
    #("attributes", json.array(assets.attributes(value), json.string)),
  ])
}

fn result_context() -> track_context.Context {
  let assert Ok(zone) = time.timezone("America/New_York")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Us,
      market_scope: "us_stock_universe",
      venue_mic: None,
      board: None,
      timezone: Some(zone),
      source_language: "en-US",
      providers: ["alpaca", "trading_assets"],
      entitlement: "credentialed_trading_asset_master",
      limitations: limitations(),
    )
  value
}

fn parse_environment(
  value: String,
) -> Result(query.TradingEnvironment, InputError) {
  case value {
    "paper" -> Ok(query.Paper)
    "live" -> Ok(query.Live)
    _ -> Error(InvalidEnvironment)
  }
}

fn parse_status(value: String) -> Result(query.AssetStatusFilter, InputError) {
  case value {
    "active" -> Ok(query.Active)
    "inactive" -> Ok(query.Inactive)
    "all" -> Ok(query.AllStatuses)
    _ -> Error(InvalidStatus)
  }
}

fn parse_exchange(value: String) -> Result(query.AssetExchange, InputError) {
  case value {
    "AMEX" -> Ok(query.Amex)
    "ARCA" -> Ok(query.Arca)
    "BATS" -> Ok(query.Bats)
    "NYSE" -> Ok(query.Nyse)
    "NASDAQ" -> Ok(query.Nasdaq)
    "NYSEARCA" -> Ok(query.NyseArca)
    "OTC" -> Ok(query.Otc)
    _ -> Error(InvalidExchange)
  }
}

fn environment_name(value: query.TradingEnvironment) -> String {
  case value {
    query.Paper -> "paper"
    query.Live -> "live"
  }
}
