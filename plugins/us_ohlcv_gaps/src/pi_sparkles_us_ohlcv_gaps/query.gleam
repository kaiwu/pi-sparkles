import finance_core/identifier
import finance_core/time.{type Date, type Instant}
import finance_listing/effective
import finance_listing/listing
import finance_market_alpaca/query as alpaca_query
import finance_provenance/identity.{type Sha256}
import finance_track
import finance_us_ohlcv/assessment
import finance_us_ohlcv/gap_receipt
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

pub type StatusInput {
  StatusInput(date: Date, status: assessment.MarketStatus, evidence: String)
}

pub type PageInput {
  PageInput(
    sequence: Int,
    request_id: Option(String),
    byte_length: Int,
    content_sha256: String,
  )
}

pub type ProviderInput {
  ProviderInput(
    schema: String,
    schema_version: Int,
    digest_algorithm: String,
    digest: String,
    provider: String,
    symbol: String,
    start_date: Date,
    end_date: Date,
    identity_as_of: Date,
    feed: alpaca_query.Feed,
    source_reference: String,
    retrieved_at: Instant,
    pagination: gap_receipt.Pagination,
    pages: List(PageInput),
    bar_dates: List(Date),
  )
}

pub type Input {
  Input(
    venue: assessment.Venue,
    instrument_id: String,
    listing_start: Date,
    listing_end: Option(Date),
    listing_evidence: String,
    provider_receipt: ProviderInput,
    statuses: List(StatusInput),
  )
}

pub type QueryError {
  InvalidInstrumentId
  InvalidSymbol
  InvalidListingInterval(effective.IntervalError)
  InvalidListingReceipt(assessment.ReceiptError)
  InvalidReceiptEnvelope
  InvalidContentHash(index: Int)
  InvalidPageReceipt(index: Int, reason: gap_receipt.ReceiptError)
  InvalidGapReceipt(gap_receipt.ReceiptError)
  InvalidReceiptDigest
  ReceiptDigestMismatch
  InvalidProviderPlan(alpaca_query.QueryError)
  SourceReferenceMismatch
  InvalidProviderReceipt(assessment.ReceiptError)
  InvalidStatusReceipt(index: Int, reason: assessment.ReceiptError)
  InvalidAssessment(assessment.AssessmentError)
}

pub fn canonical_receipt(input: Input) -> Result(String, QueryError) {
  input
  |> build_gap_receipt
  |> result.map(gap_receipt.canonical_text)
}

pub fn run(
  input: Input,
  actual_digest: Sha256,
) -> Result(assessment.Assessment, QueryError) {
  use receipt <- result.try(build_gap_receipt(input))
  use _ <- result.try(validate_digest(input.provider_receipt, actual_digest))
  use instrument_id <- result.try(build_instrument_id(input.instrument_id))
  use symbol <- result.try(build_symbol(input.provider_receipt.symbol))
  let assert Ok(mic) = identifier.mic(assessment.venue_mic_name(input.venue))
  let key = listing.new(finance_track.Us, instrument_id, symbol, mic)
  use listing_interval <- result.try(
    effective.new(input.listing_start, input.listing_end)
    |> result.map_error(InvalidListingInterval),
  )
  use listing_receipt <- result.try(
    assessment.listing_receipt(
      input.venue,
      key,
      listing_interval,
      input.listing_evidence,
    )
    |> result.map_error(InvalidListingReceipt),
  )
  use plan <- result.try(
    alpaca_query.daily_bars(
      gap_receipt.symbol(receipt),
      gap_receipt.start_date(receipt),
      gap_receipt.end_date(receipt),
      gap_receipt.identity_as_of(receipt),
      input.provider_receipt.feed,
      1,
      1,
      1,
    )
    |> result.map_error(InvalidProviderPlan),
  )
  use _ <- result.try(
    case
      gap_receipt.source_reference(receipt)
      == alpaca_query.daily_bars_source_reference(plan)
    {
      True -> Ok(Nil)
      False -> Error(SourceReferenceMismatch)
    },
  )
  use provider <- result.try(
    assessment.provider_receipt(
      gap_receipt.provider(receipt),
      gap_receipt.source_reference(receipt),
      gap_receipt.request_ids(receipt),
      assessment_completeness(gap_receipt.pagination(receipt)),
    )
    |> result.map_error(InvalidProviderReceipt),
  )
  use statuses <- result.try(build_statuses(input.statuses, 0, []))
  assessment.assess(
    input.venue,
    listing_receipt,
    gap_receipt.start_date(receipt),
    gap_receipt.end_date(receipt),
    gap_receipt.bar_dates(receipt),
    statuses,
    provider,
  )
  |> result.map_error(InvalidAssessment)
}

fn build_gap_receipt(input: Input) -> Result(gap_receipt.Receipt, QueryError) {
  let provider = input.provider_receipt
  use _ <- result.try(
    case
      provider.schema == gap_receipt.schema_name,
      provider.schema_version == gap_receipt.schema_version,
      provider.digest_algorithm == gap_receipt.digest_algorithm,
      provider.provider == "alpaca"
    {
      True, True, True, True -> Ok(Nil)
      _, _, _, _ -> Error(InvalidReceiptEnvelope)
    },
  )
  use pages <- result.try(build_pages(provider.pages, 0, []))
  gap_receipt.new(
    provider: provider.provider,
    symbol: provider.symbol,
    start_date: provider.start_date,
    end_date: provider.end_date,
    identity_as_of: provider.identity_as_of,
    feed: alpaca_query.feed_name(provider.feed),
    source_reference: provider.source_reference,
    retrieved_at: provider.retrieved_at,
    pagination: provider.pagination,
    pages: pages,
    bar_dates: provider.bar_dates,
  )
  |> result.map_error(InvalidGapReceipt)
}

fn build_pages(
  values: List(PageInput),
  index: Int,
  reversed: List(gap_receipt.Page),
) -> Result(List(gap_receipt.Page), QueryError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [PageInput(sequence, request_id, byte_length, content_sha256), ..rest] -> {
      use content_hash <- result.try(
        identity.sha256(content_sha256)
        |> result.map_error(fn(_) { InvalidContentHash(index) }),
      )
      use page <- result.try(
        gap_receipt.page(sequence, request_id, byte_length, content_hash)
        |> result.map_error(fn(reason) { InvalidPageReceipt(index, reason) }),
      )
      build_pages(rest, index + 1, [page, ..reversed])
    }
  }
}

fn validate_digest(
  provider: ProviderInput,
  actual: Sha256,
) -> Result(Nil, QueryError) {
  case identity.sha256(provider.digest) {
    Error(_) -> Error(InvalidReceiptDigest)
    Ok(expected) ->
      case expected == actual {
        True -> Ok(Nil)
        False -> Error(ReceiptDigestMismatch)
      }
  }
}

fn assessment_completeness(
  value: gap_receipt.Pagination,
) -> assessment.ProviderCompleteness {
  case value {
    gap_receipt.Complete -> assessment.Complete
    gap_receipt.TruncatedByPageBudget ->
      assessment.Incomplete("truncated_by_page_budget")
    gap_receipt.TruncatedByBarBudget ->
      assessment.Incomplete("truncated_by_bar_budget")
  }
}

fn build_instrument_id(
  value: String,
) -> Result(identifier.InstrumentId, QueryError) {
  let valid =
    string.length(value) <= 200
    && string.contains(value, ":")
    && !string.starts_with(value, ":")
    && !string.ends_with(value, ":")
    && {
      value
      |> string.to_graphemes
      |> list.all(fn(character) {
        string.contains(
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-/",
          character,
        )
      })
    }
  case valid, identifier.instrument_id(value) {
    True, Ok(instrument_id) -> Ok(instrument_id)
    _, _ -> Error(InvalidInstrumentId)
  }
}

fn build_symbol(value: String) -> Result(identifier.Symbol, QueryError) {
  case identifier.symbol(value) {
    Error(_) -> Error(InvalidSymbol)
    Ok(symbol) ->
      case identifier.symbol_value(symbol) == value {
        True -> Ok(symbol)
        False -> Error(InvalidSymbol)
      }
  }
}

fn build_statuses(
  values: List(StatusInput),
  index: Int,
  reversed: List(assessment.StatusReceipt),
) -> Result(List(assessment.StatusReceipt), QueryError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [StatusInput(date, status, evidence), ..rest] -> {
      use receipt <- result.try(
        assessment.status_receipt(date, status, evidence)
        |> result.map_error(fn(reason) { InvalidStatusReceipt(index, reason) }),
      )
      build_statuses(rest, index + 1, [receipt, ..reversed])
    }
  }
}
