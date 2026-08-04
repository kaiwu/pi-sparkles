import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri

pub type Value {
  Text(String)
  Boolean(Bool)
  Null
  Array(List(Value))
  Object(List(#(String, Value)))
}

const replacement = "[REDACTED]"

pub fn apply(value: Value, additional_keys: List(String)) -> Value {
  let sensitive_keys =
    list.append(mandatory_keys(), list.map(additional_keys, string.lowercase))
  redact(value, sensitive_keys)
}

pub fn mandatory_keys() -> List(String) {
  [
    "authorization",
    "proxy-authorization",
    "cookie",
    "set-cookie",
    "api-key",
    "apikey",
    "api_key",
    "x-api-key",
    "access-token",
    "refresh-token",
    "client-secret",
    "password",
    "signature",
    "x-signature",
    "token",
    "access_token",
    "x-amz-signature",
    "x-amz-credential",
    "x-goog-signature",
    "sig",
  ]
}

pub fn url(value: String, additional_query_keys: List(String)) -> String {
  let sensitive_keys =
    list.append(
      mandatory_keys(),
      list.map(additional_query_keys, string.lowercase),
    )
  let without_fragment = case string.split_once(value, on: "#") {
    Ok(#(before, _)) -> before
    Error(_) -> value
  }
  let #(base, query) = case string.split_once(without_fragment, on: "?") {
    Ok(#(base, query)) -> #(base, Some(query))
    Error(_) -> #(without_fragment, None)
  }
  let safe_base = redact_userinfo(base)
  case query {
    None -> safe_base
    Some(query) -> safe_base <> "?" <> redact_query(query, sensitive_keys)
  }
}

fn redact(value: Value, sensitive_keys: List(String)) -> Value {
  case value {
    Text(_) | Boolean(_) | Null -> value
    Array(values) -> Array(list.map(values, redact(_, sensitive_keys)))
    Object(fields) ->
      Object(
        list.map(fields, fn(field) {
          let #(key, value) = field
          case list.contains(sensitive_keys, string.lowercase(key)) {
            True -> #(key, Text(replacement))
            False -> #(key, redact(value, sensitive_keys))
          }
        }),
      )
  }
}

fn redact_query(query: String, sensitive_keys: List(String)) -> String {
  query
  |> string.split(on: "&")
  |> list.map(fn(parameter) {
    let key = case string.split_once(parameter, on: "=") {
      Ok(#(key, _)) -> key
      Error(_) -> parameter
    }
    let decoded_key =
      key |> uri.percent_decode |> result.unwrap(key) |> string.lowercase
    case list.contains(sensitive_keys, decoded_key) {
      True -> key <> "=%5BREDACTED%5D"
      False -> parameter
    }
  })
  |> string.join("&")
}

fn redact_userinfo(value: String) -> String {
  case string.split_once(value, on: "://") {
    Error(_) -> value
    Ok(#(scheme, remainder)) -> {
      let #(authority, suffix) = case string.split_once(remainder, on: "/") {
        Ok(#(authority, path)) -> #(authority, "/" <> path)
        Error(_) -> #(remainder, "")
      }
      case string.contains(authority, "@") {
        False -> value
        True -> {
          let host =
            authority
            |> string.split(on: "@")
            |> list.last
            |> result.unwrap("")
          scheme <> "://[REDACTED]@" <> host <> suffix
        }
      }
    }
  }
}
