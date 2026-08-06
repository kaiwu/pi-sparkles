import finance_calendar/date
import finance_core/time.{type Date, type Instant}
import finance_provenance/identity.{type Sha256}
import finance_track.{type Track}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string

pub const digest_algorithm = "sha256"

pub type Pagination {
  Complete
  TruncatedByPageBudget
  TruncatedByBarBudget
}

pub opaque type IdentityField {
  IdentityField(name: String, value: String)
}

pub opaque type Page {
  Page(
    sequence: Int,
    request_id: Option(String),
    byte_length: Int,
    content_sha256: Sha256,
  )
}

pub opaque type Receipt {
  Receipt(
    schema: String,
    schema_version: Int,
    track: Track,
    provider: String,
    identity: List(IdentityField),
    source_reference: String,
    retrieved_at: Instant,
    pagination: Pagination,
    pages: List(Page),
    range_start: Date,
    range_end: Date,
    bar_dates: List(Date),
  )
}

pub type ReceiptError {
  InvalidSchema
  InvalidProvider
  InvalidIdentityField
  DuplicateIdentityField(name: String)
  ReservedIdentityField(name: String)
  InvalidSourceReference
  InvalidDateRange
  InvalidRetrievalTime
  InvalidPageSequence(expected: Int, received: Int)
  InvalidPageRequestId(sequence: Int)
  DuplicatePageRequestId(value: String)
  InvalidPageByteLength(sequence: Int)
  InvalidPageCount
  InvalidBarDateOrder
  BarDateOutsideRange(date: Date)
}

pub fn identity_field(
  name name_value: String,
  value value_value: String,
) -> Result(IdentityField, ReceiptError) {
  case
    valid_field_name(name_value),
    reserved_field_name(name_value),
    valid_text(value_value) && string.length(value_value) <= 2000
  {
    False, _, _ | _, _, False -> Error(InvalidIdentityField)
    _, True, _ -> Error(ReservedIdentityField(name_value))
    True, False, True -> Ok(IdentityField(name_value, value_value))
  }
}

pub fn page(
  sequence sequence_value: Int,
  request_id request_id_value: Option(String),
  byte_length byte_length_value: Int,
  content_sha256 content_hash: Sha256,
) -> Result(Page, ReceiptError) {
  case
    sequence_value >= 1,
    valid_optional_request_id(request_id_value),
    byte_length_value >= 0
  {
    False, _, _ -> Error(InvalidPageSequence(1, sequence_value))
    _, False, _ -> Error(InvalidPageRequestId(sequence_value))
    _, _, False -> Error(InvalidPageByteLength(sequence_value))
    True, True, True ->
      Ok(Page(sequence_value, request_id_value, byte_length_value, content_hash))
  }
}

pub fn new(
  schema schema_value: String,
  schema_version version: Int,
  track track_value: Track,
  provider provider_value: String,
  identity identity_fields: List(IdentityField),
  source_reference source_value: String,
  retrieved_at retrieved: Instant,
  pagination pagination_value: Pagination,
  pages page_values: List(Page),
  range_start start: Date,
  range_end end: Date,
  bar_dates dates: List(Date),
) -> Result(Receipt, ReceiptError) {
  use _ <- result.try(validate_header(
    schema_value,
    version,
    provider_value,
    identity_fields,
    source_value,
  ))
  use _ <- result.try(validate_dates(start, end, retrieved, dates))
  use _ <- result.try(case list.length(page_values) {
    count if count >= 1 && count <= 10 -> Ok(Nil)
    _ -> Error(InvalidPageCount)
  })
  use _ <- result.try(validate_pages(page_values, 1, []))
  Ok(Receipt(
    schema_value,
    version,
    track_value,
    provider_value,
    identity_fields,
    source_value,
    retrieved,
    pagination_value,
    page_values,
    start,
    end,
    dates,
  ))
}

pub fn canonical_text(value: Receipt) -> String {
  json.object(list.append(
    [
      #("schema", json.string(value.schema)),
      #("schema_version", json.int(value.schema_version)),
      #("track", json.string(finance_track.name(value.track))),
      #("provider", json.string(value.provider)),
    ],
    list.append(
      value.identity
        |> list.map(fn(field) { #(field.name, json.string(field.value)) }),
      [
        #("source_reference", json.string(value.source_reference)),
        #(
          "retrieved_at_unix_ms",
          value.retrieved_at
            |> time.unix_milliseconds
            |> int.to_string
            |> json.string,
        ),
        #("pagination", json.string(pagination_name(value.pagination))),
        #("pages", json.array(value.pages, page_json)),
        #(
          "bar_dates",
          json.array(value.bar_dates, fn(value) {
            value |> date_text |> json.string
          }),
        ),
      ],
    ),
  ))
  |> json.to_string
}

pub fn schema(value: Receipt) -> String {
  value.schema
}

pub fn schema_version(value: Receipt) -> Int {
  value.schema_version
}

pub fn track(value: Receipt) -> Track {
  value.track
}

pub fn provider(value: Receipt) -> String {
  value.provider
}

pub fn identity(value: Receipt) -> List(IdentityField) {
  value.identity
}

pub fn identity_field_name(value: IdentityField) -> String {
  value.name
}

pub fn identity_field_value(value: IdentityField) -> String {
  value.value
}

pub fn source_reference(value: Receipt) -> String {
  value.source_reference
}

pub fn retrieved_at(value: Receipt) -> Instant {
  value.retrieved_at
}

pub fn pagination(value: Receipt) -> Pagination {
  value.pagination
}

pub fn pages(value: Receipt) -> List(Page) {
  value.pages
}

pub fn range_start(value: Receipt) -> Date {
  value.range_start
}

pub fn range_end(value: Receipt) -> Date {
  value.range_end
}

pub fn bar_dates(value: Receipt) -> List(Date) {
  value.bar_dates
}

pub fn page_sequence(value: Page) -> Int {
  value.sequence
}

pub fn page_request_id(value: Page) -> Option(String) {
  value.request_id
}

pub fn page_byte_length(value: Page) -> Int {
  value.byte_length
}

pub fn page_content_sha256(value: Page) -> Sha256 {
  value.content_sha256
}

pub fn request_ids(value: Receipt) -> List(String) {
  request_ids_from_pages(value.pages, [])
}

pub fn pagination_name(value: Pagination) -> String {
  case value {
    Complete -> "complete"
    TruncatedByPageBudget -> "truncated_by_page_budget"
    TruncatedByBarBudget -> "truncated_by_bar_budget"
  }
}

fn page_json(value: Page) -> json.Json {
  json.object([
    #("sequence", json.int(value.sequence)),
    #("request_id", case value.request_id {
      Some(request_id) -> json.string(request_id)
      None -> json.null()
    }),
    #("byte_length", value.byte_length |> int.to_string |> json.string),
    #(
      "content_sha256",
      value.content_sha256 |> identity.sha256_value |> json.string,
    ),
  ])
}

fn validate_header(
  schema: String,
  version: Int,
  provider: String,
  identity: List(IdentityField),
  source_reference: String,
) -> Result(Nil, ReceiptError) {
  case
    valid_schema(schema) && version >= 1,
    valid_text(provider),
    identity != [],
    valid_text(source_reference) && string.length(source_reference) <= 2000
  {
    False, _, _, _ -> Error(InvalidSchema)
    _, False, _, _ -> Error(InvalidProvider)
    _, _, False, _ -> Error(InvalidIdentityField)
    _, _, _, False -> Error(InvalidSourceReference)
    True, True, True, True -> validate_identity(identity, [])
  }
}

fn validate_identity(
  values: List(IdentityField),
  names: List(String),
) -> Result(Nil, ReceiptError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case list.contains(names, current.name) {
        True -> Error(DuplicateIdentityField(current.name))
        False -> validate_identity(rest, [current.name, ..names])
      }
  }
}

fn validate_dates(
  start: Date,
  end: Date,
  retrieved_at: Instant,
  bar_dates: List(Date),
) -> Result(Nil, ReceiptError) {
  case date.compare(start, end), time.unix_milliseconds(retrieved_at) >= 0 {
    Gt, _ -> Error(InvalidDateRange)
    _, False -> Error(InvalidRetrievalTime)
    Eq, True | Lt, True -> validate_bar_dates(bar_dates, start, end)
  }
}

fn validate_bar_dates(
  values: List(Date),
  start: Date,
  end: Date,
) -> Result(Nil, ReceiptError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case date.compare(current, start), date.compare(current, end) {
        Lt, _ | _, Gt -> Error(BarDateOutsideRange(current))
        _, _ -> validate_bar_date_order(rest, current, start, end)
      }
  }
}

fn validate_bar_date_order(
  values: List(Date),
  previous: Date,
  start: Date,
  end: Date,
) -> Result(Nil, ReceiptError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case
        date.compare(previous, current),
        date.compare(current, start),
        date.compare(current, end)
      {
        Eq, _, _ | Gt, _, _ -> Error(InvalidBarDateOrder)
        _, Lt, _ | _, _, Gt -> Error(BarDateOutsideRange(current))
        Lt, _, _ -> validate_bar_date_order(rest, current, start, end)
      }
  }
}

fn validate_pages(
  values: List(Page),
  expected_sequence: Int,
  request_ids: List(String),
) -> Result(Nil, ReceiptError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case current.sequence == expected_sequence, current.request_id {
        False, _ ->
          Error(InvalidPageSequence(expected_sequence, current.sequence))
        True, Some(value) ->
          case list.contains(request_ids, value) {
            True -> Error(DuplicatePageRequestId(value))
            False ->
              validate_pages(rest, expected_sequence + 1, [value, ..request_ids])
          }
        True, None -> validate_pages(rest, expected_sequence + 1, request_ids)
      }
  }
}

fn request_ids_from_pages(
  values: List(Page),
  reversed: List(String),
) -> List(String) {
  case values {
    [] -> list.reverse(reversed)
    [Page(request_id: Some(value), ..), ..rest] ->
      request_ids_from_pages(rest, [value, ..reversed])
    [Page(request_id: None, ..), ..rest] ->
      request_ids_from_pages(rest, reversed)
  }
}

fn valid_optional_request_id(value: Option(String)) -> Bool {
  case value {
    None -> True
    Some(value) -> valid_text(value) && string.length(value) <= 200
  }
}

fn valid_schema(value: String) -> Bool {
  valid_text(value)
  && string.length(value) <= 200
  && string.starts_with(value, "pi-sparkles/")
}

fn valid_field_name(value: String) -> Bool {
  value != ""
  && string.length(value) <= 64
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
  })
}

fn reserved_field_name(value: String) -> Bool {
  list.contains(
    [
      "schema",
      "schema_version",
      "track",
      "provider",
      "source_reference",
      "retrieved_at_unix_ms",
      "pagination",
      "pages",
      "bar_dates",
    ],
    value,
  )
}

fn valid_text(value: String) -> Bool {
  value != "" && value == string.trim(value)
}

fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
