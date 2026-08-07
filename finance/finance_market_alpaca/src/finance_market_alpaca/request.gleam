import finance_core/time
import finance_http/request
import finance_market_alpaca.{type Access}
import finance_market_alpaca/query.{
  type AssetUniverseQuery, type DailyBarsQuery, type LatestQuoteQuery,
}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const origin = "https://data.alpaca.markets"

pub const bars_path = "/v2/stocks/bars"

pub const latest_quotes_path = "/v2/stocks/quotes/latest"

pub const assets_path = "/v2/assets"

pub type RequestError {
  InvalidPageLimit
  InvalidPageToken
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_market_alpaca.AccessError)
}

pub fn daily_bars(
  access: Access,
  plan: DailyBarsQuery,
  page_limit page_limit: Int,
  page_token page_token: Option(String),
) -> Result(request.Request, RequestError) {
  use _ <- result.try(
    case page_limit >= 1 && page_limit <= query.page_size(plan) {
      True -> Ok(Nil)
      False -> Error(InvalidPageLimit)
    },
  )
  use _ <- result.try(validate_page_token(page_token))
  let assert Ok(timeout) = time.duration(15_000)
  use base <- result.try(
    request.new(request.Get, origin, bars_path, None)
    |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(
      base,
      timeout: timeout,
      maximum_response_bytes: 5_000_000,
    )
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(public_header(
    bounded,
    "Accept",
    "application/json",
  ))
  use value <- result.try(public_query(accepted, "symbols", query.symbol(plan)))
  use value <- result.try(public_query(value, "timeframe", "1Day"))
  use value <- result.try(public_query(
    value,
    "start",
    query.date_text(query.start_date(plan)),
  ))
  use value <- result.try(public_query(
    value,
    "end",
    query.date_text(query.end_date(plan)),
  ))
  use value <- result.try(public_query(
    value,
    "limit",
    int.to_string(page_limit),
  ))
  use value <- result.try(public_query(value, "adjustment", "raw"))
  use value <- result.try(public_query(
    value,
    "feed",
    query.feed_name(query.feed(plan)),
  ))
  use value <- result.try(public_query(value, "currency", "USD"))
  use value <- result.try(public_query(value, "sort", "asc"))
  use value <- result.try(public_query(
    value,
    "asof",
    query.date_text(query.as_of_date(plan)),
  ))
  use value <- result.try(case page_token {
    None -> Ok(value)
    Some(token) -> public_query(value, "page_token", token)
  })
  finance_market_alpaca.authorize(access, value)
  |> result.map_error(InvalidAccess)
}

pub fn latest_quote(
  access: Access,
  plan: LatestQuoteQuery,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(10_000)
  use base <- result.try(
    request.new(request.Get, origin, latest_quotes_path, None)
    |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(base, timeout: timeout, maximum_response_bytes: 250_000)
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(public_header(
    bounded,
    "Accept",
    "application/json",
  ))
  use value <- result.try(public_query(
    accepted,
    "symbols",
    query.quote_symbol(plan),
  ))
  use value <- result.try(public_query(
    value,
    "feed",
    query.feed_name(query.quote_feed(plan)),
  ))
  use value <- result.try(public_query(value, "currency", "USD"))
  finance_market_alpaca.authorize(access, value)
  |> result.map_error(InvalidAccess)
}

pub fn asset_universe(
  access: Access,
  plan: AssetUniverseQuery,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(15_000)
  use base <- result.try(
    request.new(
      request.Get,
      query.trading_origin(query.asset_environment(plan)),
      assets_path,
      None,
    )
    |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(
      base,
      timeout: timeout,
      maximum_response_bytes: 15_000_000,
    )
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(public_header(
    bounded,
    "Accept",
    "application/json",
  ))
  use value <- result.try(public_query(
    accepted,
    "status",
    query.asset_status_name(query.asset_status(plan)),
  ))
  use value <- result.try(public_query(value, "asset_class", "us_equity"))
  use value <- result.try(public_query(
    value,
    "exchange",
    query.asset_exchange_name(query.asset_exchange(plan)),
  ))
  finance_market_alpaca.authorize(access, value)
  |> result.map_error(InvalidAccess)
}

fn public_header(
  value: request.Request,
  name: String,
  header_value: String,
) -> Result(request.Request, RequestError) {
  request.with_header(
    value,
    name:,
    value: header_value,
    sensitivity: request.Public,
  )
  |> result.map_error(InvalidHttp)
}

fn public_query(
  value: request.Request,
  name: String,
  query_value: String,
) -> Result(request.Request, RequestError) {
  request.with_query(
    value,
    name:,
    value: query_value,
    sensitivity: request.Public,
  )
  |> result.map_error(InvalidHttp)
}

fn validate_page_token(value: Option(String)) -> Result(Nil, RequestError) {
  case value {
    None -> Ok(Nil)
    Some(token) ->
      case
        token != ""
        && string.trim(token) == token
        && string.length(token) <= 2048
        && !string.contains(token, "\r")
        && !string.contains(token, "\n")
      {
        True -> Ok(Nil)
        False -> Error(InvalidPageToken)
      }
  }
}
