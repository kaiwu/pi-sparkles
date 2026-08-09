import finance_http/binary_response.{type Response}
import finance_http/transport.{type Cancellation}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option, None, Some}

pub type TextItem {
  TextItem(page: Int, x: Float, text: String)
}

pub type Extraction {
  Extraction(
    page_count: Int,
    byte_length: Int,
    parser: String,
    parser_version: String,
    items: List(TextItem),
  )
}

pub type ExtractionError {
  Cancelled
  Timeout
  UnexpectedStatus(received: Int)
  InvalidSignature
  BodyTooLarge(received: Int)
  InvalidBase64
  ByteLengthMismatch(expected: Int, received: Int)
  ContentHashMismatch
  TooManyPages(received: Int)
  TooManyItems(received: Int)
  TextBudgetExceeded(received: Int)
  EncryptedPdf
  InvalidPdf
  UnreadablePage
  InvalidExtractorResult
  ExtractorFailure
}

type RawResult {
  RawSuccess(
    pages: Int,
    byte_length: Int,
    parser: String,
    parser_version: String,
    items: List(TextItem),
  )
  RawFailure(kind: String, received: Option(Int))
}

/// Extract bounded positioned text from an already bounded binary response.
/// PDF mechanics remain in JavaScript; CAPCO row semantics remain in Gleam.
pub fn extract(
  response: Response,
  cancellation: Cancellation,
) -> Promise(Result(Extraction, ExtractionError)) {
  extract_pdf(
    binary_response.body_base64(response),
    binary_response.byte_length(response),
    binary_response.content_sha256(response),
    1_000_000,
    200,
    100_000,
    4_000_000,
    15_000,
    cancellation,
  )
  |> promise.map(fn(dynamic) {
    case decode.run(dynamic, raw_result_decoder()) {
      Error(_) -> Error(InvalidExtractorResult)
      Ok(raw) -> normalize(response, raw)
    }
  })
  |> promise.rescue(fn(_) { Error(ExtractorFailure) })
}

fn normalize(
  response: Response,
  raw: RawResult,
) -> Result(Extraction, ExtractionError) {
  case raw {
    RawFailure("cancelled", _) -> Error(Cancelled)
    RawFailure("timeout", _) -> Error(Timeout)
    RawFailure("unexpected_status", Some(value)) ->
      Error(UnexpectedStatus(value))
    RawFailure("invalid_signature", _) -> Error(InvalidSignature)
    RawFailure("too_large", Some(value)) -> Error(BodyTooLarge(value))
    RawFailure("invalid_base64", _) -> Error(InvalidBase64)
    RawFailure("length_mismatch", Some(value)) ->
      Error(ByteLengthMismatch(binary_response.byte_length(response), value))
    RawFailure("hash_mismatch", _) -> Error(ContentHashMismatch)
    RawFailure("page_limit", Some(value)) -> Error(TooManyPages(value))
    RawFailure("item_limit", Some(value)) -> Error(TooManyItems(value))
    RawFailure("text_limit", Some(value)) -> Error(TextBudgetExceeded(value))
    RawFailure("encrypted", _) -> Error(EncryptedPdf)
    RawFailure("invalid_pdf", _) -> Error(InvalidPdf)
    RawFailure("unreadable_page", _) -> Error(UnreadablePage)
    RawFailure(_, _) -> Error(ExtractorFailure)
    RawSuccess(pages, bytes, parser_name, version, items) ->
      case
        binary_response.status(response) == 200,
        pages > 0 && pages <= 200,
        bytes == binary_response.byte_length(response),
        parser_name != "",
        version != ""
      {
        False, _, _, _, _ ->
          Error(UnexpectedStatus(binary_response.status(response)))
        _, False, _, _, _ -> Error(InvalidExtractorResult)
        _, _, False, _, _ ->
          Error(ByteLengthMismatch(binary_response.byte_length(response), bytes))
        _, _, _, False, _ | _, _, _, _, False -> Error(InvalidExtractorResult)
        True, True, True, True, True ->
          Ok(Extraction(pages, bytes, parser_name, version, items))
      }
  }
}

fn raw_result_decoder() -> decode.Decoder(RawResult) {
  use ok <- decode.field("ok", decode.bool)
  case ok {
    True -> {
      use pages <- decode.field("pages", decode.int)
      use bytes <- decode.field("byteLength", decode.int)
      use parser_name <- decode.field("parser", decode.string)
      use version <- decode.field("parserVersion", decode.string)
      use items <- decode.field("items", decode.list(text_item_decoder()))
      decode.success(RawSuccess(pages, bytes, parser_name, version, items))
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

fn text_item_decoder() -> decode.Decoder(TextItem) {
  use page <- decode.field("page", decode.int)
  use x <- decode.field("x", decode.float)
  use text <- decode.field("text", decode.string)
  decode.success(TextItem(page, x, text))
}

@external(javascript, "./pdf_text_ffi.mjs", "extract_pdf")
fn extract_pdf(
  body_base64: String,
  declared_byte_length: Int,
  expected_sha256: String,
  maximum_bytes: Int,
  maximum_pages: Int,
  maximum_items: Int,
  maximum_text_bytes: Int,
  timeout_milliseconds: Int,
  cancellation: Cancellation,
) -> Promise(Dynamic)
