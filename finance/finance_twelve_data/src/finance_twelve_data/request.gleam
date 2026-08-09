import finance_core/time
import finance_http/request
import finance_twelve_data.{type Access}
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string

pub const origin = "https://api.twelvedata.com"

pub const profile_path = "/profile"

pub const statistics_path = "/statistics"

pub type RequestError {
  InvalidSymbol
  UnsupportedMic
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_twelve_data.AccessError)
}

pub fn profile(
  access: Access,
  symbol: String,
  mic: String,
) -> Result(request.Request, RequestError) {
  build(access, profile_path, symbol, mic, 500_000)
}

pub fn statistics(
  access: Access,
  symbol: String,
  mic: String,
) -> Result(request.Request, RequestError) {
  build(access, statistics_path, symbol, mic, 1_000_000)
}

fn build(
  access: Access,
  path: String,
  symbol: String,
  mic: String,
  maximum_response_bytes: Int,
) -> Result(request.Request, RequestError) {
  use _ <- result.try(validate_listing(symbol, mic))
  let assert Ok(timeout) = time.duration(15_000)
  use value <- result.try(
    request.new(request.Get, origin, path, None)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_limits(value, timeout, maximum_response_bytes)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_header(value, "Accept", "application/json", request.Public)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(value, "symbol", symbol, request.Public)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(value, "mic_code", mic, request.Public)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(value, "country", "US", request.Public)
    |> result.map_error(InvalidHttp),
  )
  finance_twelve_data.authorize(access, value)
  |> result.map_error(InvalidAccess)
}

fn validate_listing(symbol: String, mic: String) -> Result(Nil, RequestError) {
  case valid_symbol(symbol), supported_mic(mic) {
    False, _ -> Error(InvalidSymbol)
    _, False -> Error(UnsupportedMic)
    True, True -> Ok(Nil)
  }
}

fn valid_symbol(value: String) -> Bool {
  value != ""
  && string.length(value) <= 20
  && string.uppercase(value) == value
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-", character)
    })
  }
}

fn supported_mic(value: String) -> Bool {
  list.contains(["XNYS", "XNAS", "XNGS", "XNCM", "XNMS"], value)
}
