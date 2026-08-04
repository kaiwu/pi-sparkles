import finance_core/identifier
import finance_core/time
import finance_http/request
import finance_openfigi.{type Access}
import finance_openfigi/response.{type ResultSet}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type Query {
  Query(value: String, mic_code: Option(String), cursor: Option(String))
}

pub type QueryError {
  EmptyQuery
  QueryTooLong
  InvalidMic
  InvalidCursor
}

pub type RequestError {
  InvalidHttpRequest(request.RequestError)
  InvalidAccess(finance_openfigi.AccessError)
}

pub fn query(
  value value: String,
  mic_code mic_code: Option(String),
) -> Result(Query, QueryError) {
  case string.trim(value), string.length(value) <= 200 {
    "", _ -> Error(EmptyQuery)
    _, False -> Error(QueryTooLong)
    normalized, True -> {
      use normalized_mic <- result.try(validate_mic(mic_code))
      Ok(Query(normalized, normalized_mic, None))
    }
  }
}

pub fn with_cursor(value: Query, cursor: String) -> Result(Query, QueryError) {
  case
    cursor != ""
    && string.trim(cursor) == cursor
    && string.length(cursor) <= 4096
    && !string.contains(cursor, "\r")
    && !string.contains(cursor, "\n")
  {
    False -> Error(InvalidCursor)
    True -> Ok(Query(..value, cursor: Some(cursor)))
  }
}

pub fn next(value: Query, result: ResultSet) -> Option(Query) {
  case result.next {
    None -> None
    Some(cursor) ->
      case with_cursor(value, cursor) {
        Ok(next) -> Some(next)
        Error(_) -> None
      }
  }
}

pub fn request(
  access: Access,
  value: Query,
) -> Result(request.Request, RequestError) {
  let Query(query_value, mic_code, cursor) = value
  let body =
    [#("query", json.string(query_value))]
    |> list.append(optional_property("micCode", mic_code))
    |> list.append(optional_property("start", cursor))
    |> json.object
    |> json.to_string
  use base <- result.try(
    request.new(
      method: request.Post,
      origin: finance_openfigi.origin,
      path: "/v3/filter",
      idempotency_key: None,
    )
    |> result.map_error(InvalidHttpRequest),
  )
  use repeatable <- result.try(
    request.as_repeatable_read(base)
    |> result.map_error(InvalidHttpRequest),
  )
  use with_body <- result.try(
    request.with_text_body(
      repeatable,
      content_type: "application/json",
      value: body,
      safe_variant: "openfigi-v3-filter:" <> body,
    )
    |> result.map_error(InvalidHttpRequest),
  )
  let assert Ok(timeout) = time.duration(10_000)
  use bounded <- result.try(
    request.with_limits(
      with_body,
      timeout: timeout,
      maximum_response_bytes: 500_000,
    )
    |> result.map_error(InvalidHttpRequest),
  )
  finance_openfigi.authorize(access, bounded)
  |> result.map_error(InvalidAccess)
}

fn validate_mic(value: Option(String)) -> Result(Option(String), QueryError) {
  case value {
    None -> Ok(None)
    Some(value) ->
      case identifier.mic(value) {
        Error(_) -> Error(InvalidMic)
        Ok(value) -> Ok(Some(identifier.mic_value(value)))
      }
  }
}

fn optional_property(
  name: String,
  value: Option(String),
) -> List(#(String, json.Json)) {
  case value {
    Some(value) -> [#(name, json.string(value))]
    None -> []
  }
}
