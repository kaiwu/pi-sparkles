import finance_core/time
import finance_http/binary_response.{type Response}
import finance_http/transport.{type Cancellation}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type Policy {
  Policy(maximum_bytes: Int, maximum_pages: Int, timeout: time.Duration)
}

pub opaque type Inspection {
  Inspection(
    page_count: Int,
    byte_length: Int,
    parser: String,
    parser_version: String,
  )
}

pub type PolicyError {
  InvalidMaximumBytes
  InvalidMaximumPages
  InvalidTimeout
}

pub type InspectionError {
  Cancelled
  Timeout
  UnexpectedStatus(received: Int)
  InvalidSignature
  BodyTooLarge(maximum: Int, received: Int)
  InvalidBase64
  ByteLengthMismatch(expected: Int, received: Int)
  ContentHashMismatch
  TooManyPages(maximum: Int, received: Int)
  EncryptedPdf
  InvalidPdf
  UnreadablePage
  InvalidInspectorResult
  InspectorFailure
}

type RawResult {
  RawSuccess(
    pages: Int,
    byte_length: Int,
    parser: String,
    parser_version: String,
  )
  RawFailure(kind: String, received: Option(Int))
}

pub fn policy(
  maximum_bytes maximum_bytes_value: Int,
  maximum_pages maximum_pages_value: Int,
  timeout timeout_value: time.Duration,
) -> Result(Policy, PolicyError) {
  case
    maximum_bytes_value > 0,
    maximum_pages_value > 0,
    time.duration_milliseconds(timeout_value) > 0
  {
    False, _, _ -> Error(InvalidMaximumBytes)
    _, False, _ -> Error(InvalidMaximumPages)
    _, _, False -> Error(InvalidTimeout)
    True, True, True ->
      Ok(Policy(maximum_bytes_value, maximum_pages_value, timeout_value))
  }
}

/// Inspect an already-bounded binary HTTP response with a real PDF parser.
///
/// No URL is passed to the parser, so inspection cannot perform nested network
/// access. The effect boundary disables rendering-oriented features, walks
/// every declared page, and destroys the parser on success, failure, timeout,
/// or cancellation.
pub fn inspect(
  policy policy_value: Policy,
  response response_value: Response,
  cancellation cancellation_value: Cancellation,
) -> Promise(Result(Inspection, InspectionError)) {
  case
    binary_response.status(response_value),
    string.starts_with(binary_response.prefix_hex(response_value), "255044462d"),
    binary_response.byte_length(response_value) <= policy_value.maximum_bytes
  {
    200, False, _ -> promise.resolve(Error(InvalidSignature))
    200, _, False ->
      promise.resolve(
        Error(BodyTooLarge(
          policy_value.maximum_bytes,
          binary_response.byte_length(response_value),
        )),
      )
    200, True, True ->
      inspect_pdf(
        binary_response.body_base64(response_value),
        binary_response.byte_length(response_value),
        binary_response.content_sha256(response_value),
        policy_value.maximum_bytes,
        policy_value.maximum_pages,
        time.duration_milliseconds(policy_value.timeout),
        cancellation_value,
      )
      |> promise.map(fn(dynamic) {
        case decode.run(dynamic, raw_result_decoder()) {
          Error(_) -> Error(InvalidInspectorResult)
          Ok(raw) -> normalize(policy_value, response_value, raw)
        }
      })
      |> promise.rescue(fn(_) { Error(InspectorFailure) })
    status, _, _ -> promise.resolve(Error(UnexpectedStatus(status)))
  }
}

pub fn page_count(value: Inspection) -> Int {
  value.page_count
}

pub fn byte_length(value: Inspection) -> Int {
  value.byte_length
}

pub fn parser(value: Inspection) -> String {
  value.parser
}

pub fn parser_version(value: Inspection) -> String {
  value.parser_version
}

fn normalize(
  policy: Policy,
  response: Response,
  raw: RawResult,
) -> Result(Inspection, InspectionError) {
  case raw {
    RawFailure("cancelled", _) -> Error(Cancelled)
    RawFailure("timeout", _) -> Error(Timeout)
    RawFailure("invalid_base64", _) -> Error(InvalidBase64)
    RawFailure("length_mismatch", Some(received)) ->
      Error(ByteLengthMismatch(binary_response.byte_length(response), received))
    RawFailure("hash_mismatch", _) -> Error(ContentHashMismatch)
    RawFailure("too_large", Some(received)) ->
      Error(BodyTooLarge(policy.maximum_bytes, received))
    RawFailure("page_limit", Some(received)) ->
      Error(TooManyPages(policy.maximum_pages, received))
    RawFailure("encrypted", _) -> Error(EncryptedPdf)
    RawFailure("invalid_pdf", _) -> Error(InvalidPdf)
    RawFailure("unreadable_page", _) -> Error(UnreadablePage)
    RawFailure(_, _) -> Error(InspectorFailure)
    RawSuccess(pages, bytes, parser_name, version) ->
      case
        pages > 0,
        pages <= policy.maximum_pages,
        bytes == binary_response.byte_length(response),
        valid_label(parser_name),
        valid_label(version)
      {
        False, _, _, _, _ -> Error(InvalidInspectorResult)
        _, False, _, _, _ -> Error(TooManyPages(policy.maximum_pages, pages))
        _, _, False, _, _ ->
          Error(ByteLengthMismatch(binary_response.byte_length(response), bytes))
        _, _, _, False, _ | _, _, _, _, False -> Error(InvalidInspectorResult)
        True, True, True, True, True ->
          Ok(Inspection(pages, bytes, parser_name, version))
      }
  }
}

fn valid_label(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn raw_result_decoder() -> decode.Decoder(RawResult) {
  use ok <- decode.field("ok", decode.bool)
  case ok {
    True -> {
      use pages <- decode.field("pages", decode.int)
      use bytes <- decode.field("byteLength", decode.int)
      use parser_name <- decode.field("parser", decode.string)
      use version <- decode.field("parserVersion", decode.string)
      decode.success(RawSuccess(pages, bytes, parser_name, version))
    }
    False -> {
      use kind <- decode.field("kind", decode.string)
      use received <- decode.optional_field(
        "received",
        None,
        decode.map(decode.int, Some),
      )
      decode.success(RawFailure(kind, received))
    }
  }
}

@external(javascript, "./inspector_ffi.mjs", "inspect_pdf")
fn inspect_pdf(
  body_base64: String,
  declared_byte_length: Int,
  expected_sha256: String,
  maximum_bytes: Int,
  maximum_pages: Int,
  timeout_milliseconds: Int,
  cancellation: Cancellation,
) -> Promise(Dynamic)
