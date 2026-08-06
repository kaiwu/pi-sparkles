import finance_http/transport.{type Cancellation}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type Policy {
  Policy(
    required_entries: List(String),
    maximum_archive_bytes: Int,
    maximum_entries: Int,
    maximum_entry_bytes: Int,
    maximum_total_uncompressed_bytes: Int,
  )
}

pub opaque type Entry {
  Entry(name: String, text: String, byte_length: Int, crc32: String)
}

pub opaque type Extraction {
  Extraction(
    archive_byte_length: Int,
    archive_entry_count: Int,
    total_uncompressed_bytes: Int,
    entries: List(Entry),
  )
}

pub type PolicyError {
  EmptyRequiredEntries
  TooManyRequiredEntries
  InvalidRequiredEntry(name: String)
  DuplicateRequiredEntry(name: String)
  InvalidArchiveByteBudget
  InvalidEntryCountBudget
  InvalidEntryByteBudget
  InvalidTotalUncompressedBudget
  IncoherentBudgets
}

pub type ExtractError {
  Cancelled
  InvalidBase64
  InvalidArchive
  MultiDiskUnsupported
  Zip64Unsupported
  ArchiveTooLarge(limit: Int, received: Int)
  TooManyEntries(limit: Int, received: Int)
  UnsafeEntryName(name: String)
  DuplicateEntry(name: String)
  EncryptedEntry(name: String)
  UnsupportedCompression(name: String)
  EntryTooLarge(name: String, limit: Int, received: Int)
  TotalUncompressedTooLarge(limit: Int, received: Int)
  MissingRequiredEntry(name: String)
  MalformedEntry(name: String)
  EntryLengthMismatch(name: String)
  ChecksumMismatch(name: String)
  InvalidUtf8(name: String)
  DecompressionFailed(name: String)
  InvalidExtractorResult
}

type RawResult {
  RawSuccess(
    archive_byte_length: Int,
    entry_count: Int,
    total_uncompressed_bytes: Int,
    entries: List(Entry),
  )
  RawFailure(kind: String, name: Option(String), limit: Int, received: Int)
}

@external(javascript, "./archive_ffi.mjs", "extract_zip_utf8")
fn extract_zip_utf8(
  body_base64: String,
  required_entries: List(String),
  maximum_archive_bytes: Int,
  maximum_entries: Int,
  maximum_entry_bytes: Int,
  maximum_total_uncompressed_bytes: Int,
) -> Promise(Dynamic)

pub fn policy(
  required_entries required: List(String),
  maximum_archive_bytes maximum_archive: Int,
  maximum_entries maximum_entry_count: Int,
  maximum_entry_bytes maximum_entry: Int,
  maximum_total_uncompressed_bytes maximum_total: Int,
) -> Result(Policy, PolicyError) {
  case
    required,
    list.length(required) <= 16,
    first_invalid_name(required),
    first_duplicate(required),
    maximum_archive > 0,
    maximum_entry_count >= list.length(required) && maximum_entry_count <= 256,
    maximum_entry > 0,
    maximum_total > 0,
    maximum_total >= maximum_entry
  {
    [], _, _, _, _, _, _, _, _ -> Error(EmptyRequiredEntries)
    _, False, _, _, _, _, _, _, _ -> Error(TooManyRequiredEntries)
    _, _, Some(name), _, _, _, _, _, _ -> Error(InvalidRequiredEntry(name))
    _, _, _, Some(name), _, _, _, _, _ -> Error(DuplicateRequiredEntry(name))
    _, _, _, _, False, _, _, _, _ -> Error(InvalidArchiveByteBudget)
    _, _, _, _, _, False, _, _, _ -> Error(InvalidEntryCountBudget)
    _, _, _, _, _, _, False, _, _ -> Error(InvalidEntryByteBudget)
    _, _, _, _, _, _, _, False, _ -> Error(InvalidTotalUncompressedBudget)
    _, _, _, _, _, _, _, _, False -> Error(IncoherentBudgets)
    [_, ..], True, None, None, True, True, True, True, True ->
      Ok(Policy(
        required,
        maximum_archive,
        maximum_entry_count,
        maximum_entry,
        maximum_total,
      ))
  }
}

pub fn extract(
  policy policy_value: Policy,
  body_base64 body: String,
  cancellation cancellation_value: Cancellation,
) -> Promise(Result(Extraction, ExtractError)) {
  case transport.is_cancelled(cancellation_value) {
    True -> promise.resolve(Error(Cancelled))
    False ->
      extract_zip_utf8(
        body,
        policy_value.required_entries,
        policy_value.maximum_archive_bytes,
        policy_value.maximum_entries,
        policy_value.maximum_entry_bytes,
        policy_value.maximum_total_uncompressed_bytes,
      )
      |> promise.map(fn(value) {
        case transport.is_cancelled(cancellation_value) {
          True -> Error(Cancelled)
          False -> normalize(value)
        }
      })
      |> promise.rescue(fn(_) { Error(InvalidExtractorResult) })
  }
}

pub fn entries(value: Extraction) -> List(Entry) {
  value.entries
}

pub fn archive_byte_length(value: Extraction) -> Int {
  value.archive_byte_length
}

pub fn archive_entry_count(value: Extraction) -> Int {
  value.archive_entry_count
}

pub fn total_uncompressed_bytes(value: Extraction) -> Int {
  value.total_uncompressed_bytes
}

pub fn entry_name(value: Entry) -> String {
  value.name
}

pub fn entry_text(value: Entry) -> String {
  value.text
}

pub fn entry_byte_length(value: Entry) -> Int {
  value.byte_length
}

pub fn entry_crc32(value: Entry) -> String {
  value.crc32
}

pub fn find_entry(value: Extraction, name expected: String) -> Option(Entry) {
  case value.entries |> list.find(fn(entry) { entry.name == expected }) {
    Ok(entry) -> Some(entry)
    Error(Nil) -> None
  }
}

fn normalize(value: Dynamic) -> Result(Extraction, ExtractError) {
  case decode.run(value, raw_decoder()) {
    Error(_) -> Error(InvalidExtractorResult)
    Ok(RawSuccess(archive_bytes, count, total, entries)) ->
      Ok(Extraction(archive_bytes, count, total, entries))
    Ok(RawFailure(kind, name, limit, received)) ->
      Error(map_failure(kind, name, limit, received))
  }
}

fn raw_decoder() -> decode.Decoder(RawResult) {
  use ok <- decode.field("ok", decode.bool)
  case ok {
    True -> {
      use archive_bytes <- decode.field("archiveByteLength", decode.int)
      use count <- decode.field("entryCount", decode.int)
      use total <- decode.field("totalUncompressedBytes", decode.int)
      use values <- decode.field("entries", decode.list(of: entry_decoder()))
      decode.success(RawSuccess(archive_bytes, count, total, values))
    }
    False -> {
      use kind <- decode.field("kind", decode.string)
      use name <- decode.optional_field(
        "name",
        None,
        decode.map(decode.string, Some),
      )
      use limit <- decode.optional_field("limit", -1, decode.int)
      use received <- decode.optional_field("received", -1, decode.int)
      decode.success(RawFailure(kind, name, limit, received))
    }
  }
}

fn entry_decoder() -> decode.Decoder(Entry) {
  use name <- decode.field("name", decode.string)
  use text <- decode.field("text", decode.string)
  use bytes <- decode.field("byteLength", decode.int)
  use crc32 <- decode.field("crc32", decode.string)
  decode.success(Entry(name, text, bytes, crc32))
}

fn map_failure(
  kind: String,
  name: Option(String),
  limit: Int,
  received: Int,
) -> ExtractError {
  let entry = option_name(name)
  case kind {
    "invalid_base64" -> InvalidBase64
    "invalid_archive" -> InvalidArchive
    "multi_disk" -> MultiDiskUnsupported
    "zip64" -> Zip64Unsupported
    "archive_too_large" -> ArchiveTooLarge(limit, received)
    "too_many_entries" -> TooManyEntries(limit, received)
    "unsafe_entry_name" -> UnsafeEntryName(entry)
    "duplicate_entry" -> DuplicateEntry(entry)
    "encrypted_entry" -> EncryptedEntry(entry)
    "unsupported_compression" -> UnsupportedCompression(entry)
    "entry_too_large" -> EntryTooLarge(entry, limit, received)
    "total_uncompressed_too_large" -> TotalUncompressedTooLarge(limit, received)
    "missing_required_entry" -> MissingRequiredEntry(entry)
    "malformed_entry" -> MalformedEntry(entry)
    "entry_length_mismatch" -> EntryLengthMismatch(entry)
    "checksum_mismatch" -> ChecksumMismatch(entry)
    "invalid_utf8" -> InvalidUtf8(entry)
    "decompression_failed" -> DecompressionFailed(entry)
    _ -> InvalidExtractorResult
  }
}

fn option_name(value: Option(String)) -> String {
  case value {
    Some(value) -> value
    None -> ""
  }
}

fn first_invalid_name(values: List(String)) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case valid_name(first) {
        True -> first_invalid_name(rest)
        False -> Some(first)
      }
  }
}

fn first_duplicate(values: List(String)) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> Some(first)
        False -> first_duplicate(rest)
      }
  }
}

fn valid_name(value: String) -> Bool {
  value != ""
  && string.length(value) <= 240
  && string.trim(value) == value
  && !string.starts_with(value, "/")
  && !string.contains(value, "\\")
  && !string.contains(value, "\u{0000}")
  && !string.contains(value, ":")
  && {
    value
    |> string.split("/")
    |> list.all(fn(segment) {
      segment != "" && segment != "." && segment != ".."
    })
  }
}
