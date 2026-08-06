import finance_core/identifier
import finance_core/time.{type Date}
import finance_listing/effective
import finance_listing/listing
import finance_market_alpaca/query as alpaca_query
import finance_track
import finance_us_ohlcv/assessment
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

pub type StatusInput {
  StatusInput(date: Date, status: assessment.MarketStatus, evidence: String)
}

pub type Input {
  Input(
    venue: assessment.Venue,
    instrument_id: String,
    symbol: String,
    listing_start: Date,
    listing_end: Option(Date),
    listing_evidence: String,
    start_date: Date,
    end_date: Date,
    identity_as_of: Date,
    feed: alpaca_query.Feed,
    pagination: assessment.ProviderCompleteness,
    source_reference: String,
    request_ids: List(String),
    bar_dates: List(Date),
    statuses: List(StatusInput),
  )
}

pub type QueryError {
  InvalidInstrumentId
  InvalidSymbol
  InvalidListingInterval(effective.IntervalError)
  InvalidListingReceipt(assessment.ReceiptError)
  InvalidProviderPlan(alpaca_query.QueryError)
  SourceReferenceMismatch
  InvalidProviderReceipt(assessment.ReceiptError)
  InvalidStatusReceipt(index: Int, reason: assessment.ReceiptError)
  InvalidAssessment(assessment.AssessmentError)
}

pub fn run(input: Input) -> Result(assessment.Assessment, QueryError) {
  use instrument_id <- result.try(build_instrument_id(input.instrument_id))
  use symbol <- result.try(build_symbol(input.symbol))
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
      input.symbol,
      input.start_date,
      input.end_date,
      input.identity_as_of,
      input.feed,
      1,
      1,
      1,
    )
    |> result.map_error(InvalidProviderPlan),
  )
  use _ <- result.try(
    case
      input.source_reference == alpaca_query.daily_bars_source_reference(plan)
    {
      True -> Ok(Nil)
      False -> Error(SourceReferenceMismatch)
    },
  )
  use provider <- result.try(
    assessment.provider_receipt(
      "alpaca",
      input.source_reference,
      input.request_ids,
      input.pagination,
    )
    |> result.map_error(InvalidProviderReceipt),
  )
  use statuses <- result.try(build_statuses(input.statuses, 0, []))
  assessment.assess(
    input.venue,
    listing_receipt,
    input.start_date,
    input.end_date,
    input.bar_dates,
    statuses,
    provider,
  )
  |> result.map_error(InvalidAssessment)
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
