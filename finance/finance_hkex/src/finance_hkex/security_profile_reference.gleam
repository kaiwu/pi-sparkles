import finance_archive as archive
import finance_authority_snapshot/artifact
import finance_core/source
import finance_core/time.{type Date, type Instant}
import finance_hkex/full_list.{type Profile}
import finance_hkex/request
import finance_hkex/security_search.{type Query}
import finance_http/binary_response.{type Response}
import finance_http/transport.{type Cancellation}
import finance_provenance/hash
import finance_provenance/identity
import finance_track
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

pub const schema = "pi-sparkles/hkex-current-security-profile-receipt"

pub const schema_version = 1

pub const authority_id = "hk_hkex_full_list_of_securities"

pub opaque type Reference {
  Reference(
    query: Query,
    lookup: full_list.Lookup,
    artifact: artifact.Artifact,
    extraction: archive.Extraction,
  )
}

pub opaque type ExtractedEntry {
  ExtractedEntry(name: String, byte_length: Int, crc32: String)
}

pub type ReferenceError {
  InvalidArtifact(artifact.CaptureError)
  InvalidArchive(archive.ExtractError)
  InvalidWorkbook(full_list.DecodeError)
}

/// Capture the exact HKEX workbook before bounded extraction and decoding.
///
/// The workbook proves a current Full List profile as of its stated update
/// date. It does not prove the listing start/end date or positive trading
/// status, and no such fields are inferred from catalogue membership.
pub fn capture(
  query query_value: Query,
  response response_value: Response,
  retrieved_at retrieved_at_value: Instant,
  cancellation cancellation_value: Cancellation,
) -> Promise(Result(Reference, ReferenceError)) {
  case
    artifact.capture(
      artifact_policy(),
      response_value,
      as_of: retrieved_at_value,
      retrieved_at: retrieved_at_value,
    )
  {
    Error(error) -> promise.resolve(Error(InvalidArtifact(error)))
    Ok(captured) -> {
      use extracted <- promise.await(archive.extract(
        archive_policy(),
        artifact.body_base64(captured),
        cancellation_value,
      ))
      case extracted {
        Error(error) -> promise.resolve(Error(InvalidArchive(error)))
        Ok(extraction) -> {
          let assert Some(content_types) =
            archive.find_entry(extraction, "[Content_Types].xml")
          let assert Some(workbook) =
            archive.find_entry(extraction, "xl/workbook.xml")
          let assert Some(relationships) =
            archive.find_entry(extraction, "xl/_rels/workbook.xml.rels")
          let assert Some(shared_strings) =
            archive.find_entry(extraction, "xl/sharedStrings.xml")
          let assert Some(worksheet) =
            archive.find_entry(extraction, "xl/worksheets/sheet1.xml")
          case
            full_list.decode(
              security_search.query_code(query_value),
              archive.entry_text(content_types),
              archive.entry_text(workbook),
              archive.entry_text(relationships),
              archive.entry_text(shared_strings),
              archive.entry_text(worksheet),
            )
          {
            Error(error) -> promise.resolve(Error(InvalidWorkbook(error)))
            Ok(lookup) ->
              promise.resolve(
                Ok(Reference(query_value, lookup, captured, extraction)),
              )
          }
        }
      }
    }
  }
}

pub fn query_code(value: Reference) -> String {
  security_search.query_code(value.query)
}

pub fn updated_as(value: Reference) -> Date {
  full_list.updated_as(value.lookup)
}

pub fn candidates(value: Reference) -> List(Profile) {
  full_list.candidates(value.lookup)
}

pub fn resolution(value: Reference) -> String {
  full_list.resolution(value.lookup)
}

pub fn source_reference(value: Reference) -> String {
  value.artifact |> artifact.source |> source.reference
}

pub fn retrieved_at(value: Reference) -> Instant {
  value.artifact |> artifact.evidence |> fn(item) { item.retrieved_at }
}

pub fn evidence_id(value: Reference) -> String {
  value.artifact
  |> artifact.evidence
  |> fn(item) { item.id }
  |> identity.evidence_id_value
}

pub fn source_fingerprint(value: Reference) -> String {
  value.artifact
  |> artifact.evidence
  |> fn(item) { item.source_fingerprint }
  |> identity.source_fingerprint_value
}

pub fn media_type(value: Reference) -> String {
  value.artifact |> artifact.evidence |> fn(item) { item.media_type }
}

pub fn response_byte_length(value: Reference) -> Int {
  value.artifact |> artifact.evidence |> fn(item) { item.byte_length }
}

pub fn content_sha256(value: Reference) -> String {
  value.artifact
  |> artifact.evidence
  |> fn(item) { item.content_hash }
  |> identity.sha256_value
}

pub fn archive_entry_count(value: Reference) -> Int {
  archive.archive_entry_count(value.extraction)
}

pub fn total_uncompressed_bytes(value: Reference) -> Int {
  archive.total_uncompressed_bytes(value.extraction)
}

pub fn extracted_entries(value: Reference) -> List(ExtractedEntry) {
  value.extraction
  |> archive.entries
  |> list.map(fn(entry) {
    ExtractedEntry(
      archive.entry_name(entry),
      archive.entry_byte_length(entry),
      archive.entry_crc32(entry),
    )
  })
}

pub fn extracted_entry_name(value: ExtractedEntry) -> String {
  value.name
}

pub fn extracted_entry_byte_length(value: ExtractedEntry) -> Int {
  value.byte_length
}

pub fn extracted_entry_crc32(value: ExtractedEntry) -> String {
  value.crc32
}

pub fn canonical_digest(value: Reference) -> String {
  let assert Ok(digest) = value |> canonical_text |> hash.text
  identity.sha256_value(digest)
}

pub fn canonical_text(value: Reference) -> String {
  let retrieved = value |> retrieved_at |> time.unix_milliseconds
  json.object([
    #("schema", json.string(schema)),
    #("schema_version", json.int(schema_version)),
    #("track", json.string(finance_track.name(finance_track.Hk))),
    #("authority_id", json.string(authority_id)),
    #("provider", json.string("HKEX")),
    #("source_reference", json.string(source_reference(value))),
    #("query_code", json.string(query_code(value))),
    #("workbook_updated_as", json.string(date_text(updated_as(value)))),
    #("retrieved_at_unix_ms", retrieved |> int.to_string |> json.string),
    #("catalogue_scope", json.string("current_full_list_exact_code_only")),
    #("evidence_id", json.string(evidence_id(value))),
    #("source_fingerprint", json.string(source_fingerprint(value))),
    #("media_type", json.string(media_type(value))),
    #(
      "response_byte_length",
      value |> response_byte_length |> int.to_string |> json.string,
    ),
    #("content_sha256", json.string(content_sha256(value))),
    #("archive_entry_count", json.int(archive_entry_count(value))),
    #("total_uncompressed_bytes", json.int(total_uncompressed_bytes(value))),
    #(
      "extracted_entries",
      json.array(extracted_entries(value), archive_entry_json),
    ),
    #("resolution", json.string(resolution(value))),
    #("candidates", json.array(candidates(value), profile_json)),
    #("venue_mic", json.string("XHKG")),
    #("listing_effective_from", json.null()),
    #("listing_effective_to", json.null()),
    #("trading_status", json.null()),
  ])
  |> json.to_string
}

fn artifact_policy() -> artifact.Policy {
  let assert Ok(source_ref) =
    source.new(
      provider: "HKEX",
      reference: request.securities_origin <> request.full_list_path,
      kind: source.Exchange,
    )
  let assert Ok(value) =
    artifact.local_analysis_policy(
      track: finance_track.Hk,
      authority_id: authority_id,
      source: source_ref,
      retrieval_route: "direct:HKEX",
      allowed_media_types: [
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      ],
      maximum_bytes: 2_000_000,
      signature: artifact.Zip,
    )
  value
}

fn archive_policy() -> archive.Policy {
  let assert Ok(value) =
    archive.policy(
      required_entries: [
        "[Content_Types].xml",
        "xl/workbook.xml",
        "xl/_rels/workbook.xml.rels",
        "xl/sharedStrings.xml",
        "xl/worksheets/sheet1.xml",
      ],
      maximum_archive_bytes: 2_000_000,
      maximum_entries: 32,
      maximum_entry_bytes: 20_000_000,
      maximum_total_uncompressed_bytes: 25_000_000,
    )
  value
}

fn archive_entry_json(value: ExtractedEntry) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #("byte_length", json.int(value.byte_length)),
    #("crc32", json.string(value.crc32)),
  ])
}

fn profile_json(value: Profile) -> json.Json {
  json.object([
    #("code", json.string(full_list.code(value))),
    #("name", json.string(full_list.name(value))),
    #("category", json.string(full_list.category(value))),
    #("subcategory", json.string(full_list.subcategory(value))),
    #("board", option_json(full_list.board(value))),
    #("board_lot", json.string(full_list.board_lot(value))),
    #("isin", json.string(full_list.isin(value))),
    #("expiry_date", json.string(full_list.expiry_date(value))),
    #("stamp_duty", json.string(full_list.stamp_duty(value))),
    #("short_sell", json.string(full_list.short_sell(value))),
    #("cas", json.string(full_list.cas(value))),
    #("vcm", json.string(full_list.vcm(value))),
    #("ccass", json.string(full_list.ccass(value))),
    #("debt_board_lot", json.string(full_list.debt_board_lot(value))),
    #("debt_investor_type", json.string(full_list.debt_investor_type(value))),
    #("pos", json.string(full_list.pos(value))),
    #("spread_table", json.string(full_list.spread_table(value))),
    #("trading_currency", json.string(full_list.trading_currency(value))),
    #("rmb_counter", json.string(full_list.rmb_counter(value))),
  ])
}

fn option_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> pad(month) <> "-" <> pad(day)
}

fn pad(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
