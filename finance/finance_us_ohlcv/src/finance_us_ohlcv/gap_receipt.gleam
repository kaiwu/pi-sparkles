import finance_core/time.{type Date, type Instant}
import finance_ohlcv/acquisition_receipt
import finance_provenance/identity.{type Sha256}
import finance_track
import gleam/int
import gleam/option.{type Option}
import gleam/result
import gleam/string

pub const schema_name = "pi-sparkles/us-ohlcv-gap-receipt"

pub const schema_version = 1

pub const digest_algorithm = acquisition_receipt.digest_algorithm

pub type Pagination {
  Complete
  TruncatedByPageBudget
  TruncatedByBarBudget
}

pub type Page =
  acquisition_receipt.Page

pub opaque type Receipt {
  Receipt(
    canonical: acquisition_receipt.Receipt,
    symbol: String,
    start_date: Date,
    end_date: Date,
    identity_as_of: Date,
    feed: String,
    pagination: Pagination,
  )
}

pub type ReceiptError {
  InvalidProvider
  InvalidSymbol
  InvalidFeed
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

pub fn page(
  sequence sequence_value: Int,
  request_id request_id_value: Option(String),
  byte_length byte_length_value: Int,
  content_sha256 content_hash: Sha256,
) -> Result(Page, ReceiptError) {
  acquisition_receipt.page(
    sequence_value,
    request_id_value,
    byte_length_value,
    content_hash,
  )
  |> result.map_error(map_receipt_error)
}

pub fn new(
  provider provider_value: String,
  symbol symbol_value: String,
  start_date start: Date,
  end_date end: Date,
  identity_as_of identity_date: Date,
  feed feed_value: String,
  source_reference source_value: String,
  retrieved_at retrieved: Instant,
  pagination pagination_value: Pagination,
  pages page_values: List(Page),
  bar_dates dates: List(Date),
) -> Result(Receipt, ReceiptError) {
  use _ <- result.try(validate_header(
    provider_value,
    symbol_value,
    feed_value,
    source_value,
  ))
  use fields <- result.try(identity_fields(
    symbol_value,
    start,
    end,
    identity_date,
    feed_value,
  ))
  use canonical <- result.try(
    acquisition_receipt.new(
      schema: schema_name,
      schema_version: schema_version,
      track: finance_track.Us,
      provider: provider_value,
      identity: fields,
      source_reference: source_value,
      retrieved_at: retrieved,
      pagination: shared_pagination(pagination_value),
      pages: page_values,
      range_start: start,
      range_end: end,
      bar_dates: dates,
    )
    |> result.map_error(map_receipt_error),
  )
  Ok(Receipt(
    canonical,
    symbol_value,
    start,
    end,
    identity_date,
    feed_value,
    pagination_value,
  ))
}

pub fn canonical_text(value: Receipt) -> String {
  value.canonical |> acquisition_receipt.canonical_text
}

pub fn provider(value: Receipt) -> String {
  value.canonical |> acquisition_receipt.provider
}

pub fn symbol(value: Receipt) -> String {
  value.symbol
}

pub fn start_date(value: Receipt) -> Date {
  value.start_date
}

pub fn end_date(value: Receipt) -> Date {
  value.end_date
}

pub fn identity_as_of(value: Receipt) -> Date {
  value.identity_as_of
}

pub fn feed(value: Receipt) -> String {
  value.feed
}

pub fn source_reference(value: Receipt) -> String {
  value.canonical |> acquisition_receipt.source_reference
}

pub fn retrieved_at(value: Receipt) -> Instant {
  value.canonical |> acquisition_receipt.retrieved_at
}

pub fn pagination(value: Receipt) -> Pagination {
  value.pagination
}

pub fn pages(value: Receipt) -> List(Page) {
  value.canonical |> acquisition_receipt.pages
}

pub fn bar_dates(value: Receipt) -> List(Date) {
  value.canonical |> acquisition_receipt.bar_dates
}

pub fn page_sequence(value: Page) -> Int {
  value |> acquisition_receipt.page_sequence
}

pub fn page_request_id(value: Page) -> Option(String) {
  value |> acquisition_receipt.page_request_id
}

pub fn page_byte_length(value: Page) -> Int {
  value |> acquisition_receipt.page_byte_length
}

pub fn page_content_sha256(value: Page) -> Sha256 {
  value |> acquisition_receipt.page_content_sha256
}

pub fn request_ids(value: Receipt) -> List(String) {
  value.canonical |> acquisition_receipt.request_ids
}

pub fn pagination_name(value: Pagination) -> String {
  value |> shared_pagination |> acquisition_receipt.pagination_name
}

fn identity_fields(
  symbol: String,
  start: Date,
  end: Date,
  identity_as_of: Date,
  feed: String,
) -> Result(List(acquisition_receipt.IdentityField), ReceiptError) {
  use symbol_field <- result.try(field("symbol", symbol))
  use start_field <- result.try(field("start_date", date_text(start)))
  use end_field <- result.try(field("end_date", date_text(end)))
  use identity_field <- result.try(field(
    "identity_as_of",
    date_text(identity_as_of),
  ))
  use feed_field <- result.try(field("feed", feed))
  Ok([symbol_field, start_field, end_field, identity_field, feed_field])
}

fn field(
  name: String,
  value: String,
) -> Result(acquisition_receipt.IdentityField, ReceiptError) {
  acquisition_receipt.identity_field(name, value)
  |> result.map_error(map_receipt_error)
}

fn shared_pagination(value: Pagination) -> acquisition_receipt.Pagination {
  case value {
    Complete -> acquisition_receipt.Complete
    TruncatedByPageBudget -> acquisition_receipt.TruncatedByPageBudget
    TruncatedByBarBudget -> acquisition_receipt.TruncatedByBarBudget
  }
}

fn map_receipt_error(value: acquisition_receipt.ReceiptError) -> ReceiptError {
  case value {
    acquisition_receipt.InvalidProvider -> InvalidProvider
    acquisition_receipt.InvalidSourceReference -> InvalidSourceReference
    acquisition_receipt.InvalidDateRange -> InvalidDateRange
    acquisition_receipt.InvalidRetrievalTime -> InvalidRetrievalTime
    acquisition_receipt.InvalidPageSequence(expected, received) ->
      InvalidPageSequence(expected, received)
    acquisition_receipt.InvalidPageRequestId(sequence) ->
      InvalidPageRequestId(sequence)
    acquisition_receipt.DuplicatePageRequestId(value) ->
      DuplicatePageRequestId(value)
    acquisition_receipt.InvalidPageByteLength(sequence) ->
      InvalidPageByteLength(sequence)
    acquisition_receipt.InvalidPageCount -> InvalidPageCount
    acquisition_receipt.InvalidBarDateOrder -> InvalidBarDateOrder
    acquisition_receipt.BarDateOutsideRange(date) -> BarDateOutsideRange(date)
    acquisition_receipt.InvalidSchema
    | acquisition_receipt.InvalidIdentityField
    | acquisition_receipt.DuplicateIdentityField(_)
    | acquisition_receipt.ReservedIdentityField(_) -> InvalidSourceReference
  }
}

fn validate_header(
  provider: String,
  symbol: String,
  feed: String,
  source_reference: String,
) -> Result(Nil, ReceiptError) {
  case
    valid_text(provider),
    valid_symbol(symbol),
    valid_text(feed),
    valid_text(source_reference)
  {
    False, _, _, _ -> Error(InvalidProvider)
    _, False, _, _ -> Error(InvalidSymbol)
    _, _, False, _ -> Error(InvalidFeed)
    _, _, _, False -> Error(InvalidSourceReference)
    True, True, True, True -> Ok(Nil)
  }
}

fn valid_text(value: String) -> Bool {
  value != "" && value == string.trim(value)
}

fn valid_symbol(value: String) -> Bool {
  valid_text(value)
  && string.length(value) <= 20
  && value == string.uppercase(value)
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
