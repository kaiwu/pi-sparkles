import finance_core/time
import finance_http/binary_response
import finance_http/request.{type Request}
import finance_http/response.{type Response}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/result

pub type Cancellation

pub type TransportError {
  Timeout
  Cancelled
  ResponseTooLarge(limit: Int)
  NetworkFailure
  InvalidTransportResult
  InvalidResponse(response.ResponseError)
  InvalidBinaryResponse(binary_response.ResponseError)
}

type RawResult {
  RawSuccess(
    status: Int,
    headers: List(response.Header),
    body: String,
    byte_length: Int,
    elapsed_milliseconds: Int,
  )
  RawFailure(kind: String, limit: Option(Int))
}

type RawBinaryResult {
  RawBinarySuccess(
    status: Int,
    headers: List(response.Header),
    body_base64: String,
    byte_length: Int,
    content_sha256: String,
    prefix_hex: String,
    elapsed_milliseconds: Int,
  )
  RawBinaryFailure(kind: String, limit: Option(Int))
}

@external(javascript, "./transport_ffi.mjs", "new_cancellation")
pub fn new_cancellation() -> Cancellation

/// Adapt a host-owned JavaScript `AbortSignal` without taking ownership of it.
///
/// Pi plugins can pass `pi/raw.dynamic(signal)` here. An absent or malformed
/// dynamic value becomes an independent, non-cancelled token, which also covers
/// Pi callback contexts where no active-turn signal exists.
@external(javascript, "./transport_ffi.mjs", "from_abort_signal")
pub fn from_abort_signal(signal: Dynamic) -> Cancellation

/// Cancel a token created by `new_cancellation`.
///
/// This is intentionally a no-op for a host-owned token created with
/// `from_abort_signal`; a library must never abort Pi's controller.
@external(javascript, "./transport_ffi.mjs", "cancel")
pub fn cancel(cancellation: Cancellation) -> Nil

@external(javascript, "./transport_ffi.mjs", "is_cancelled")
pub fn is_cancelled(cancellation: Cancellation) -> Bool

@external(javascript, "./transport_ffi.mjs", "send_request")
fn send_request(payload: String, cancellation: Cancellation) -> Promise(Dynamic)

@external(javascript, "./transport_ffi.mjs", "send_binary_request")
fn send_binary_request(
  payload: String,
  cancellation: Cancellation,
) -> Promise(Dynamic)

pub fn send(
  request request_value: Request,
  cancellation cancellation: Cancellation,
) -> Promise(Result(Response, TransportError)) {
  request_value
  |> encode_request
  |> send_request(cancellation)
  |> promise.map(fn(dynamic) {
    case decode.run(dynamic, raw_result_decoder()) {
      Error(_) -> Error(InvalidTransportResult)
      Ok(raw) -> normalize(raw)
    }
  })
  |> promise.rescue(fn(_) { Error(NetworkFailure) })
}

pub fn send_binary(
  request request_value: Request,
  cancellation cancellation: Cancellation,
) -> Promise(Result(binary_response.Response, TransportError)) {
  request_value
  |> encode_request
  |> send_binary_request(cancellation)
  |> promise.map(fn(dynamic) {
    case decode.run(dynamic, raw_binary_result_decoder()) {
      Error(_) -> Error(InvalidTransportResult)
      Ok(raw) -> normalize_binary(raw)
    }
  })
  |> promise.rescue(fn(_) { Error(NetworkFailure) })
}

fn normalize(raw: RawResult) -> Result(Response, TransportError) {
  case raw {
    RawFailure("timeout", _) -> Error(Timeout)
    RawFailure("cancelled", _) -> Error(Cancelled)
    RawFailure("response_too_large", Some(limit)) ->
      Error(ResponseTooLarge(limit))
    RawFailure("network", _) -> Error(NetworkFailure)
    RawFailure(_, _) -> Error(InvalidTransportResult)
    RawSuccess(status, headers, body, byte_length, elapsed_milliseconds) -> {
      case time.duration(elapsed_milliseconds) {
        Error(_) -> Error(InvalidTransportResult)
        Ok(elapsed) ->
          response.new(status, headers, body, byte_length, elapsed)
          |> result.map_error(InvalidResponse)
      }
    }
  }
}

fn normalize_binary(
  raw: RawBinaryResult,
) -> Result(binary_response.Response, TransportError) {
  case raw {
    RawBinaryFailure("timeout", _) -> Error(Timeout)
    RawBinaryFailure("cancelled", _) -> Error(Cancelled)
    RawBinaryFailure("response_too_large", Some(limit)) ->
      Error(ResponseTooLarge(limit))
    RawBinaryFailure("network", _) -> Error(NetworkFailure)
    RawBinaryFailure(_, _) -> Error(InvalidTransportResult)
    RawBinarySuccess(
      status,
      headers,
      body_base64,
      byte_length,
      content_sha256,
      prefix_hex,
      elapsed_milliseconds,
    ) ->
      case time.duration(elapsed_milliseconds) {
        Error(_) -> Error(InvalidTransportResult)
        Ok(elapsed) ->
          binary_response.new(
            status,
            headers,
            body_base64,
            byte_length,
            content_sha256,
            prefix_hex,
            elapsed,
          )
          |> result.map_error(InvalidBinaryResponse)
      }
  }
}

fn encode_request(request_value: Request) -> String {
  json.object([
    #(
      "method",
      request.method(request_value) |> request.method_name |> json.string,
    ),
    #("origin", request.origin(request_value) |> json.string),
    #("path", request.path(request_value) |> json.string),
    #(
      "headers",
      request.headers(request_value)
        |> json.array(fn(header) {
          let request.Header(name, value, _) = header
          json.object([
            #("name", json.string(name)),
            #("value", json.string(value)),
          ])
        }),
    ),
    #(
      "query",
      request.query(request_value)
        |> json.array(fn(parameter) {
          let request.QueryParameter(name, value, _) = parameter
          json.object([
            #("name", json.string(name)),
            #("value", json.string(value)),
          ])
        }),
    ),
    #("body", body_json(request.body(request_value))),
    #("idempotencyKey", optional_string(request.idempotency_key(request_value))),
    #(
      "timeoutMs",
      request.timeout(request_value)
        |> time.duration_milliseconds
        |> json.int,
    ),
    #(
      "maximumResponseBytes",
      request.maximum_response_bytes(request_value) |> json.int,
    ),
  ])
  |> json.to_string
}

fn body_json(body: Option(request.Body)) -> Json {
  case body {
    None -> json.null()
    Some(request.TextBody(content_type, value)) ->
      json.object([
        #("contentType", json.string(content_type)),
        #("value", json.string(value)),
      ])
  }
}

fn optional_string(value: Option(String)) -> Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn raw_result_decoder() -> decode.Decoder(RawResult) {
  use ok <- decode.field("ok", decode.bool)
  case ok {
    True -> {
      use status <- decode.field("status", decode.int)
      use headers <- decode.field("headers", decode.list(of: header_decoder()))
      use body <- decode.field("body", decode.string)
      use byte_length <- decode.field("byteLength", decode.int)
      use elapsed_milliseconds <- decode.field("elapsedMs", decode.int)
      decode.success(RawSuccess(
        status,
        headers,
        body,
        byte_length,
        elapsed_milliseconds,
      ))
    }
    False -> {
      use kind <- decode.field("kind", decode.string)
      use limit <- decode.optional_field(
        "limit",
        None,
        decode.map(decode.int, Some),
      )
      decode.success(RawFailure(kind, limit))
    }
  }
}

fn raw_binary_result_decoder() -> decode.Decoder(RawBinaryResult) {
  use ok <- decode.field("ok", decode.bool)
  case ok {
    True -> {
      use status <- decode.field("status", decode.int)
      use headers <- decode.field("headers", decode.list(of: header_decoder()))
      use body_base64 <- decode.field("bodyBase64", decode.string)
      use byte_length <- decode.field("byteLength", decode.int)
      use content_sha256 <- decode.field("contentSha256", decode.string)
      use prefix_hex <- decode.field("prefixHex", decode.string)
      use elapsed_milliseconds <- decode.field("elapsedMs", decode.int)
      decode.success(RawBinarySuccess(
        status,
        headers,
        body_base64,
        byte_length,
        content_sha256,
        prefix_hex,
        elapsed_milliseconds,
      ))
    }
    False -> {
      use kind <- decode.field("kind", decode.string)
      use limit <- decode.optional_field(
        "limit",
        None,
        decode.map(decode.int, Some),
      )
      decode.success(RawBinaryFailure(kind, limit))
    }
  }
}

fn header_decoder() -> decode.Decoder(response.Header) {
  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(response.Header(name, value))
}
