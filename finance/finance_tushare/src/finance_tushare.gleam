import finance_http/request
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string

pub type Status {
  Experimental
}

pub opaque type Access {
  Access(token: String)
}

pub type AccessError {
  InvalidToken
  InvalidApiName
  InvalidFields
  InvalidRequest(request.RequestError)
}

pub fn status() -> Status {
  Experimental
}

/// Validate a caller-supplied token while keeping it opaque to adapter users.
pub fn access(token: String) -> Result(Access, AccessError) {
  case
    token != ""
    && string.trim(token) == token
    && string.length(token) <= 512
    && !string.contains(token, "\r")
    && !string.contains(token, "\n")
  {
    True -> Ok(Access(token))
    False -> Error(InvalidToken)
  }
}

/// Attach one read-only Tushare query body.
///
/// The actual body contains the credential. The safe body used by request
/// identity, diagnostics, caches, and retry accounting contains a fixed
/// redaction marker instead.
pub fn authorize_query(
  access access: Access,
  request_value request_value: request.Request,
  api_name api_name: String,
  params params: List(#(String, String)),
  fields fields: List(String),
) -> Result(request.Request, AccessError) {
  use _ <- result.try(validate_api_name(api_name))
  use _ <- result.try(validate_fields(fields))
  let Access(token) = access
  let body = query_json(api_name, token, params, fields) |> json.to_string
  let safe_body =
    query_json(api_name, "[REDACTED]", params, fields) |> json.to_string
  use with_body <- result.try(
    request.with_text_body(
      request_value,
      content_type: "application/json",
      value: body,
      safe_variant: safe_body,
    )
    |> result.map_error(InvalidRequest),
  )
  request.as_repeatable_read(with_body) |> result.map_error(InvalidRequest)
}

fn query_json(
  api_name: String,
  token: String,
  params: List(#(String, String)),
  fields: List(String),
) -> Json {
  json.object([
    #("api_name", json.string(api_name)),
    #("token", json.string(token)),
    #(
      "params",
      params
        |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) })
        |> json.object,
    ),
    #("fields", fields |> string.join(",") |> json.string),
  ])
}

fn validate_api_name(value: String) -> Result(Nil, AccessError) {
  case
    value != ""
    && value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidApiName)
  }
}

fn validate_fields(values: List(String)) -> Result(Nil, AccessError) {
  case
    values != []
    && values
    |> list.all(fn(value) {
      value != ""
      && value
      |> string.to_graphemes
      |> list.all(fn(character) {
        string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
      })
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidFields)
  }
}
