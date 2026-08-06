import finance_core/currency.{type Currency}
import finance_core/identifier
import finance_core/instrument
import finance_core/time.{type Date, type Instant}
import finance_eastmoney/query as eastmoney_query
import finance_hk_identity/identity as hk_identity
import finance_hk_ohlcv/assessment
import finance_hk_ohlcv/gap_receipt
import finance_listing/effective
import finance_ohlcv/gap_assessment
import finance_provenance/identity.{type Sha256}
import finance_track
import gleam/list
import gleam/option.{type Option}
import gleam/result

pub type StatusInput {
  StatusInput(date: Date, status: gap_assessment.MarketStatus, evidence: String)
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
    venue: String,
    board: hk_identity.Board,
    share_class: hk_identity.ShareClass,
    currency: Currency,
    code: String,
    start_date: Date,
    end_date: Date,
    limit: Int,
    source_reference: String,
    retrieved_at: Instant,
    pagination: gap_receipt.Pagination,
    pages: List(PageInput),
    bar_dates: List(Date),
  )
}

pub type Input {
  Input(
    venue: String,
    board: hk_identity.Board,
    share_class: hk_identity.ShareClass,
    currency: Currency,
    code: String,
    instrument_id: String,
    listing_start: Date,
    listing_end: Option(Date),
    listing_evidence: String,
    provider_receipt: ProviderInput,
    statuses: List(StatusInput),
  )
}

pub type QueryError {
  InvalidVenue
  InvalidInstrumentId
  InvalidListingIdentity(hk_identity.IdentityError)
  InvalidListingInterval(effective.IntervalError)
  InvalidListingReceipt(assessment.ReceiptError)
  InvalidReceiptEnvelope
  InvalidContentHash(index: Int)
  InvalidPageReceipt(index: Int, reason: gap_receipt.ReceiptError)
  InvalidGapReceipt(gap_receipt.ReceiptError)
  InvalidReceiptDigest
  ReceiptDigestMismatch
  ProviderIdentityMismatch
  InvalidProviderPlan(eastmoney_query.QueryError)
  SourceReferenceMismatch
  InvalidProviderReceipt(gap_assessment.ReceiptError)
  InvalidStatusReceipt(index: Int, reason: gap_assessment.ReceiptError)
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
  use listing <- result.try(build_listing(
    input.instrument_id,
    input.board,
    input.share_class,
    input.currency,
    input.code,
  ))
  use _ <- result.try(validate_identity_match(listing, receipt))
  use listing_interval <- result.try(
    effective.new(input.listing_start, input.listing_end)
    |> result.map_error(InvalidListingInterval),
  )
  use listing_receipt <- result.try(
    assessment.listing_receipt(
      listing,
      listing_interval,
      input.listing_evidence,
    )
    |> result.map_error(InvalidListingReceipt),
  )
  use plan <- result.try(
    eastmoney_query.history(
      finance_track.Hk,
      eastmoney_query.Hk,
      gap_receipt.code(receipt),
      gap_receipt.start_date(receipt),
      gap_receipt.end_date(receipt),
      gap_receipt.limit(receipt),
    )
    |> result.map_error(InvalidProviderPlan),
  )
  use _ <- result.try(
    case
      gap_receipt.source_reference(receipt)
      == eastmoney_query.history_source_reference(plan)
    {
      True -> Ok(Nil)
      False -> Error(SourceReferenceMismatch)
    },
  )
  use provider <- result.try(
    gap_assessment.provider_receipt(
      gap_receipt.provider(receipt),
      gap_receipt.source_reference(receipt),
      gap_receipt.request_ids(receipt),
      provider_completeness(gap_receipt.pagination(receipt)),
    )
    |> result.map_error(InvalidProviderReceipt),
  )
  use statuses <- result.try(build_statuses(input.statuses, 0, []))
  assessment.assess(
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
  use _ <- result.try(case input.venue == "hk", provider.venue == "hk" {
    True, True -> Ok(Nil)
    _, _ -> Error(InvalidVenue)
  })
  use _ <- result.try(
    case
      provider.schema == gap_receipt.schema_name,
      provider.schema_version == gap_receipt.schema_version,
      provider.digest_algorithm == gap_receipt.digest_algorithm,
      provider.provider == "eastmoney"
    {
      True, True, True, True -> Ok(Nil)
      _, _, _, _ -> Error(InvalidReceiptEnvelope)
    },
  )
  use provider_listing <- result.try(build_listing(
    "eastmoney:hk:" <> provider.code,
    provider.board,
    provider.share_class,
    provider.currency,
    provider.code,
  ))
  use pages <- result.try(build_pages(provider.pages, 0, []))
  gap_receipt.new(
    listing: provider_listing,
    start_date: provider.start_date,
    end_date: provider.end_date,
    limit: provider.limit,
    source_reference: provider.source_reference,
    retrieved_at: provider.retrieved_at,
    pagination: provider.pagination,
    pages: pages,
    bar_dates: provider.bar_dates,
  )
  |> result.map_error(InvalidGapReceipt)
}

fn build_listing(
  instrument_id_value: String,
  board: hk_identity.Board,
  share_class: hk_identity.ShareClass,
  currency: Currency,
  code: String,
) -> Result(hk_identity.Listing, QueryError) {
  use instrument_id <- result.try(
    identifier.instrument_id(instrument_id_value)
    |> result.map_error(fn(_) { InvalidInstrumentId }),
  )
  hk_identity.new(
    instrument_id,
    code,
    board,
    share_class,
    currency,
    instrument.UnknownStatus,
  )
  |> result.map_error(InvalidListingIdentity)
}

fn validate_identity_match(
  listing: hk_identity.Listing,
  receipt: gap_receipt.Receipt,
) -> Result(Nil, QueryError) {
  case
    hk_identity.board(listing) == gap_receipt.board(receipt),
    hk_identity.share_class(listing) == gap_receipt.share_class(receipt),
    listing |> hk_identity.currency |> currency.code
    == { receipt |> gap_receipt.currency |> currency.code },
    hk_identity.code(listing) == gap_receipt.code(receipt)
  {
    True, True, True, True -> Ok(Nil)
    _, _, _, _ -> Error(ProviderIdentityMismatch)
  }
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

fn provider_completeness(
  value: gap_receipt.Pagination,
) -> gap_assessment.ProviderCompleteness {
  case value {
    gap_receipt.Complete -> gap_assessment.Complete
    gap_receipt.TruncatedByBarBudget ->
      gap_assessment.Incomplete("truncated_by_bar_budget")
  }
}

fn build_statuses(
  values: List(StatusInput),
  index: Int,
  reversed: List(gap_assessment.StatusReceipt),
) -> Result(List(gap_assessment.StatusReceipt), QueryError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [StatusInput(date, status, evidence), ..rest] -> {
      use receipt <- result.try(
        gap_assessment.status_receipt(date, status, evidence)
        |> result.map_error(fn(reason) { InvalidStatusReceipt(index, reason) }),
      )
      build_statuses(rest, index + 1, [receipt, ..reversed])
    }
  }
}
