import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Cell {
  Text(String)
  Numeric(String)
  Missing
}

pub opaque type Payload {
  Payload(
    code: String,
    message: String,
    fields: List(String),
    rows: List(List(Cell)),
  )
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  ProviderError(code: String, message: String)
}

pub fn decode(body: String) -> Result(Payload, DecodeError) {
  case body |> normalize_numbers |> json.parse(payload_decoder()) {
    Error(error) -> Error(InvalidJson(error))
    Ok(payload) ->
      case payload.code {
        "0" -> Ok(payload)
        code -> Error(ProviderError(code, payload.message))
      }
  }
}

/// Render a credential-safe, user-facing explanation while retaining the
/// provider's original message in `ProviderError` for typed diagnostics.
pub fn error_message(value: DecodeError) -> String {
  case value {
    InvalidJson(_) ->
      "Tushare response did not match the documented JSON envelope"
    ProviderError("40203", _) ->
      "Tushare rejected the request (provider code 40203): this API's caller-account rate or permission limit was exceeded; no provider-error retry or fallback was attempted"
    ProviderError(code, _) ->
      "Tushare rejected the request (provider code "
      <> code
      <> "); check the caller-owned token, request parameters, points, permissions, and provider quota; no fallback was attempted"
  }
}

pub fn fields(value: Payload) -> List(String) {
  value.fields
}

pub fn rows(value: Payload) -> List(List(Cell)) {
  value.rows
}

pub fn text(value: Cell) -> Result(String, Nil) {
  case value {
    Text(value) -> Ok(value)
    Numeric(_) | Missing -> Error(Nil)
  }
}

pub fn scalar(value: Cell) -> Result(String, Nil) {
  case value {
    Text(value) | Numeric(value) -> Ok(value)
    Missing -> Error(Nil)
  }
}

pub fn optional_text(value: Cell) -> Result(Option(String), Nil) {
  case value {
    Text(value) -> Ok(Some(value))
    Missing -> Ok(None)
    Numeric(_) -> Error(Nil)
  }
}

pub fn optional_scalar(value: Cell) -> Result(Option(String), Nil) {
  case value {
    Text(value) | Numeric(value) -> Ok(Some(value))
    Missing -> Ok(None)
  }
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use code <- decode.field("code", number_decoder())
  use message <- decode.field("msg", decode.string)
  case string.length(code) <= 20, int.parse(code) {
    False, _ | _, Error(_) ->
      decode.failure(
        Payload(code, message, [], []),
        "bounded integer Tushare response code",
      )
    True, Ok(_) ->
      case code {
        "0" -> {
          use data <- decode.field("data", data_decoder())
          let #(fields, rows) = data
          decode.success(Payload(code, message, fields, rows))
        }
        _ -> decode.success(Payload(code, message, [], []))
      }
  }
}

fn data_decoder() -> decode.Decoder(#(List(String), List(List(Cell)))) {
  use fields <- decode.field("fields", decode.list(of: decode.string))
  use rows <- decode.field(
    "items",
    decode.list(of: decode.list(of: cell_decoder())),
  )
  decode.success(#(fields, rows))
}

fn cell_decoder() -> decode.Decoder(Cell) {
  decode.optional(number_decoder())
  |> decode.map(fn(value) {
    case value {
      Some(value) -> Numeric(value)
      None -> Missing
    }
  })
  |> decode.one_of(or: [decode.string |> decode.map(Text)])
}

fn number_decoder() -> decode.Decoder(String) {
  decode.at(["__finance_tushare_number__"], decode.string)
}

@external(javascript, "./response_ffi.mjs", "normalize_numbers")
fn normalize_numbers(source: String) -> String
