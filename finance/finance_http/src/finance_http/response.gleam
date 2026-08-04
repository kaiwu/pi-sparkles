import finance_core/time.{type Duration}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Header {
  Header(name: String, value: String)
}

pub opaque type Response {
  Response(
    status: Int,
    headers: List(Header),
    body: String,
    byte_length: Int,
    elapsed: Duration,
  )
}

pub type ResponseError {
  InvalidStatus
  InvalidHeaderName
  InvalidHeaderValue
  NegativeByteLength
}

pub type SafeSummary {
  SafeSummary(status: Int, byte_length: Int, elapsed: Duration)
}

pub fn new(
  status status: Int,
  headers headers: List(Header),
  body body: String,
  byte_length byte_length: Int,
  elapsed elapsed: Duration,
) -> Result(Response, ResponseError) {
  case status >= 100 && status <= 599, byte_length >= 0 {
    False, _ -> Error(InvalidStatus)
    _, False -> Error(NegativeByteLength)
    True, True ->
      validate_headers(headers, [])
      |> result.map(fn(safe_headers) {
        Response(status, safe_headers, body, byte_length, elapsed)
      })
  }
}

pub fn status(response: Response) -> Int {
  let Response(status, ..) = response
  status
}

pub fn headers(response: Response) -> List(Header) {
  let Response(_, headers, ..) = response
  headers
}

pub fn body(response: Response) -> String {
  let Response(_, _, body, ..) = response
  body
}

pub fn byte_length(response: Response) -> Int {
  let Response(_, _, _, byte_length, _) = response
  byte_length
}

pub fn elapsed(response: Response) -> Duration {
  let Response(_, _, _, _, elapsed) = response
  elapsed
}

pub fn safe_summary(response: Response) -> SafeSummary {
  SafeSummary(status(response), byte_length(response), elapsed(response))
}

pub fn first_header(response: Response, name name: String) -> Option(String) {
  find_header(headers(response), string.lowercase(name))
}

fn find_header(headers: List(Header), name: String) -> Option(String) {
  case headers {
    [] -> None
    [Header(candidate, value), ..rest] ->
      case candidate == name {
        True -> Some(value)
        False -> find_header(rest, name)
      }
  }
}

fn validate_headers(
  remaining: List(Header),
  validated: List(Header),
) -> Result(List(Header), ResponseError) {
  case remaining {
    [] -> Ok(list.reverse(validated))
    [Header(name, value), ..rest] ->
      case valid_header_name(name), valid_header_value(value) {
        False, _ -> Error(InvalidHeaderName)
        _, False -> Error(InvalidHeaderValue)
        True, True -> {
          let normalized_name = string.lowercase(name)
          let safe_value = case sensitive_header(normalized_name) {
            True -> "[REDACTED]"
            False -> value
          }
          validate_headers(rest, [
            Header(normalized_name, safe_value),
            ..validated
          ])
        }
      }
  }
}

fn sensitive_header(name: String) -> Bool {
  name == "authorization"
  || name == "proxy-authorization"
  || name == "set-cookie"
  || name == "cookie"
  || name == "x-api-key"
  || name == "api-key"
  || string.ends_with(name, "-api-key")
  || string.ends_with(name, "-token")
}

fn valid_header_name(name: String) -> Bool {
  name != ""
  && {
    name
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~",
        character,
      )
    })
  }
}

fn valid_header_value(value: String) -> Bool {
  !string.contains(value, "\r") && !string.contains(value, "\n")
}
