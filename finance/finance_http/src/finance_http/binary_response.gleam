import finance_core/time.{type Duration}
import finance_http/response
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type Response {
  Response(
    status: Int,
    headers: List(response.Header),
    body_base64: String,
    byte_length: Int,
    content_sha256: String,
    prefix_hex: String,
    elapsed: Duration,
  )
}

pub type ResponseError {
  InvalidResponse(response.ResponseError)
  InvalidBase64
  InvalidSha256
  InvalidPrefixHex
}

pub fn new(
  status status_value: Int,
  headers header_values: List(response.Header),
  body_base64 body_value: String,
  byte_length byte_length_value: Int,
  content_sha256 sha256_value: String,
  prefix_hex prefix_value: String,
  elapsed elapsed_value: Duration,
) -> Result(Response, ResponseError) {
  case
    response.new(status_value, header_values, "", 0, elapsed_value),
    valid_base64(body_value, byte_length_value),
    valid_sha256(sha256_value),
    valid_prefix(prefix_value, byte_length_value)
  {
    Error(error), _, _, _ -> Error(InvalidResponse(error))
    _, False, _, _ -> Error(InvalidBase64)
    _, _, False, _ -> Error(InvalidSha256)
    _, _, _, False -> Error(InvalidPrefixHex)
    Ok(validated), True, True, True ->
      Ok(Response(
        status_value,
        response.headers(validated),
        body_value,
        byte_length_value,
        sha256_value,
        prefix_value,
        elapsed_value,
      ))
  }
}

pub fn status(value: Response) -> Int {
  value.status
}

pub fn headers(value: Response) -> List(response.Header) {
  value.headers
}

pub fn body_base64(value: Response) -> String {
  value.body_base64
}

pub fn byte_length(value: Response) -> Int {
  value.byte_length
}

pub fn content_sha256(value: Response) -> String {
  value.content_sha256
}

pub fn prefix_hex(value: Response) -> String {
  value.prefix_hex
}

pub fn elapsed(value: Response) -> Duration {
  value.elapsed
}

pub fn safe_summary(value: Response) -> response.SafeSummary {
  response.SafeSummary(value.status, value.byte_length, value.elapsed)
}

pub fn first_header(value: Response, name name: String) -> Option(String) {
  find_header(value.headers, string.lowercase(name))
}

fn find_header(headers: List(response.Header), name: String) -> Option(String) {
  case headers {
    [] -> None
    [response.Header(candidate, value), ..rest] ->
      case candidate == name {
        True -> Some(value)
        False -> find_header(rest, name)
      }
  }
}

fn valid_base64(value: String, byte_length: Int) -> Bool {
  case byte_length {
    bytes if bytes < 0 -> False
    0 -> value == ""
    bytes -> {
      let expected_length = { bytes + 2 } / 3 * 4
      let padding = case bytes % 3 {
        0 -> ""
        1 -> "=="
        _ -> "="
      }
      let core_length = string.length(value) - string.length(padding)
      case string.length(value) == expected_length, core_length >= 0 {
        False, _ | _, False -> False
        True, True -> {
          let core = string.slice(value, at_index: 0, length: core_length)
          value == core <> padding
          && {
            core
            |> string.to_graphemes
            |> list.all(fn(character) {
              string.contains(
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
                character,
              )
            })
          }
        }
      }
    }
  }
}

fn valid_sha256(value: String) -> Bool {
  string.length(value) == 64
  && value == string.lowercase(value)
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) { string.contains("0123456789abcdef", character) })
  }
}

fn valid_prefix(value: String, byte_length: Int) -> Bool {
  let expected_bytes = case byte_length > 16 {
    True -> 16
    False -> byte_length
  }
  string.length(value) == expected_bytes * 2
  && value == string.lowercase(value)
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) { string.contains("0123456789abcdef", character) })
  }
}
