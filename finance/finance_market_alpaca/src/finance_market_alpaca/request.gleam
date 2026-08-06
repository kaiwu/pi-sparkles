import finance_core/time
import finance_http/request
import finance_market_alpaca.{type Access}
import finance_market_alpaca/query.{type DailyBarsQuery}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const origin = "https://data.alpaca.markets"

pub const bars_path = "/v2/stocks/bars"

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
