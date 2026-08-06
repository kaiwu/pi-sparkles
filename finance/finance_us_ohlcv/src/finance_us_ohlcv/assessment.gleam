import finance_calendar/calendar
import finance_calendar/date
import finance_core/identifier
import finance_core/source.{type SourceRef}
import finance_core/time.{type Date}
import finance_listing/effective.{type Interval}
import finance_listing/listing.{type Key}
import finance_market_calendar/dataset as market_calendar
import finance_ohlcv
import finance_track
import finance_us_calendar/dataset as us_calendar
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string

pub type Venue {
  Nyse
  Nasdaq
}

pub type MarketStatus {
  Trading
  Suspended
}

pub type ProviderCompleteness {
  Complete
  Incomplete(reason: String)
}

pub type EvidenceRole {
  CalendarSchedule
  ListingInterval
  MarketStatusEvidence
  ProviderCoverage
}

pub type Evidence {
  Evidence(role: EvidenceRole, reference: String)
}

pub opaque type ListingReceipt {
  ListingReceipt(
    venue: Venue,
    listing: Key,
    interval: Interval,
    evidence_reference: String,
  )
}

pub opaque type StatusReceipt {
  StatusReceipt(
    session_date: Date,
    status: MarketStatus,
    evidence_reference: String,
  )
}

pub opaque type ProviderReceipt {
  ProviderReceipt(
    provider: String,
    source_reference: String,
    request_ids: List(String),
    completeness: ProviderCompleteness,
  )
}

pub type ClassifiedGap {
  ClassifiedGap(
    session_date: Date,
    state: finance_ohlcv.GapState,
    evidence: List(Evidence),
  )
}

pub opaque type Assessment {
  Assessment(
    venue: Venue,
    listing: ListingReceipt,
    start_date: Date,
    end_date: Date,
    calendar_source: SourceRef,
    calendar_version: String,
    provider: ProviderReceipt,
    returned_bar_dates: List(Date),
    statuses: List(StatusReceipt),
    gaps: List(ClassifiedGap),
  )
}

pub type ReceiptError {
  WrongTrack
  VenueMicMismatch(expected: String, received: String)
  InvalidEvidenceReference
  InvalidProvider
  InvalidRequestId
  DuplicateRequestId(value: String)
  InvalidIncompleteReason
}

pub type AssessmentError {
  InvalidRange
  RangeTooLarge
  ListingVenueMismatch
  IncompleteProviderCoverage(reason: String)
  InvalidBarDateOrder
  BarOutsideRange(date: Date)
  BarOutsideListing(date: Date)
  BarOnMarketClosure(date: Date)
  InvalidStatusOrder
  StatusOutsideRange(date: Date)
  StatusOutsideListing(date: Date)
  StatusOnMarketClosure(date: Date)
  StatusForReturnedBar(date: Date)
  MissingStatusReceipt(date: Date)
  CalendarDatasetError(us_calendar.CalendarDatasetError)
  CalendarQueryError(market_calendar.QueryError)
  DateStepError(date.DateError)
}

pub fn listing_receipt(
  venue venue_value: Venue,
  listing listing_key: Key,
  interval interval_value: Interval,
  evidence_reference evidence: String,
) -> Result(ListingReceipt, ReceiptError) {
  let expected_mic = venue_mic_name(venue_value)
  let received_mic = listing_key |> listing.mic |> identifier.mic_value
  case
    listing.track(listing_key),
    received_mic == expected_mic,
    valid_reference(evidence)
  {
    finance_track.Cn, _, _ | finance_track.Hk, _, _ -> Error(WrongTrack)
    _, False, _ -> Error(VenueMicMismatch(expected_mic, received_mic))
    _, _, False -> Error(InvalidEvidenceReference)
    finance_track.Us, True, True ->
      Ok(ListingReceipt(venue_value, listing_key, interval_value, evidence))
  }
}

pub fn status_receipt(
  session_date session_date_value: Date,
  status status_value: MarketStatus,
  evidence_reference evidence: String,
) -> Result(StatusReceipt, ReceiptError) {
  case valid_reference(evidence) {
    True -> Ok(StatusReceipt(session_date_value, status_value, evidence))
    False -> Error(InvalidEvidenceReference)
  }
}

pub fn provider_receipt(
  provider provider_value: String,
  source_reference reference: String,
  request_ids request_ids_value: List(String),
  completeness completeness_value: ProviderCompleteness,
) -> Result(ProviderReceipt, ReceiptError) {
  case
    valid_name(provider_value),
    valid_reference(reference),
    first_invalid_request_id(request_ids_value),
    first_duplicate(request_ids_value),
    valid_completeness(completeness_value)
  {
    False, _, _, _, _ -> Error(InvalidProvider)
    _, False, _, _, _ -> Error(InvalidEvidenceReference)
    _, _, True, _, _ -> Error(InvalidRequestId)
    _, _, _, Duplicate(value), _ -> Error(DuplicateRequestId(value))
    _, _, _, _, False -> Error(InvalidIncompleteReason)
    True, True, False, NoDuplicate, True ->
      Ok(ProviderReceipt(
        provider_value,
        reference,
        request_ids_value,
        completeness_value,
      ))
  }
}

pub fn assess(
  venue venue_value: Venue,
  listing listing_value: ListingReceipt,
  start_date start: Date,
  end_date end: Date,
  returned_bar_dates bar_dates: List(Date),
  statuses status_values: List(StatusReceipt),
  provider provider_value: ProviderReceipt,
) -> Result(Assessment, AssessmentError) {
  use _ <- result.try(validate_range(start, end))
  use _ <- result.try(case listing_value.venue == venue_value {
    True -> Ok(Nil)
    False -> Error(ListingVenueMismatch)
  })
  use _ <- result.try(validate_provider(provider_value))
  use dataset <- result.try(
    us_calendar.official_2026(calendar_venue(venue_value))
    |> result.map_error(CalendarDatasetError),
  )
  use _ <- result.try(validate_bar_dates(
    bar_dates,
    start,
    end,
    listing_value,
    dataset,
  ))
  use _ <- result.try(validate_statuses(
    status_values,
    start,
    end,
    listing_value,
    dataset,
    bar_dates,
  ))
  use gaps <- result.try(
    classify(
      start,
      end,
      listing_value,
      dataset,
      provider_value,
      bar_dates,
      status_values,
      [],
    ),
  )
  Ok(Assessment(
    venue_value,
    listing_value,
    start,
    end,
    market_calendar.source(dataset),
    market_calendar.version(dataset),
    provider_value,
    bar_dates,
    status_values,
    gaps,
  ))
}

pub fn venue(value: Assessment) -> Venue {
  value.venue
}

pub fn listing_receipt_value(value: Assessment) -> ListingReceipt {
  value.listing
}

pub fn start_date(value: Assessment) -> Date {
  value.start_date
}

pub fn end_date(value: Assessment) -> Date {
  value.end_date
}

pub fn calendar_source(value: Assessment) -> SourceRef {
  value.calendar_source
}

pub fn calendar_version(value: Assessment) -> String {
  value.calendar_version
}

pub fn provider(value: Assessment) -> ProviderReceipt {
  value.provider
}

pub fn returned_bar_dates(value: Assessment) -> List(Date) {
  value.returned_bar_dates
}

pub fn statuses(value: Assessment) -> List(StatusReceipt) {
  value.statuses
}

pub fn gaps(value: Assessment) -> List(ClassifiedGap) {
  value.gaps
}

pub fn assessed_date_count(value: Assessment) -> Int {
  date.days_between(value.start_date, value.end_date) + 1
}

pub fn listing_key(value: ListingReceipt) -> Key {
  value.listing
}

pub fn listing_interval(value: ListingReceipt) -> Interval {
  value.interval
}

pub fn listing_evidence_reference(value: ListingReceipt) -> String {
  value.evidence_reference
}

pub fn status_date(value: StatusReceipt) -> Date {
  value.session_date
}

pub fn market_status(value: StatusReceipt) -> MarketStatus {
  value.status
}

pub fn status_evidence_reference(value: StatusReceipt) -> String {
  value.evidence_reference
}

pub fn provider_name(value: ProviderReceipt) -> String {
  value.provider
}

pub fn provider_source_reference(value: ProviderReceipt) -> String {
  value.source_reference
}

pub fn provider_request_ids(value: ProviderReceipt) -> List(String) {
  value.request_ids
}

pub fn provider_completeness(value: ProviderReceipt) -> ProviderCompleteness {
  value.completeness
}

pub fn gap_date(value: ClassifiedGap) -> Date {
  let ClassifiedGap(session_date, _, _) = value
  session_date
}

pub fn gap_state(value: ClassifiedGap) -> finance_ohlcv.GapState {
  let ClassifiedGap(_, state, _) = value
  state
}

pub fn gap_evidence(value: ClassifiedGap) -> List(Evidence) {
  let ClassifiedGap(_, _, evidence) = value
  evidence
}

pub fn evidence_role(value: Evidence) -> EvidenceRole {
  let Evidence(role, _) = value
  role
}

pub fn evidence_reference(value: Evidence) -> String {
  let Evidence(_, reference) = value
  reference
}

pub fn venue_name(value: Venue) -> String {
  case value {
    Nyse -> "nyse"
    Nasdaq -> "nasdaq"
  }
}

pub fn venue_mic_name(value: Venue) -> String {
  case value {
    Nyse -> "XNYS"
    Nasdaq -> "XNAS"
  }
}

fn validate_range(start: Date, end: Date) -> Result(Nil, AssessmentError) {
  let span = date.days_between(start, end)
  case span < 0, span > 365 {
    True, _ -> Error(InvalidRange)
    _, True -> Error(RangeTooLarge)
    False, False -> Ok(Nil)
  }
}

fn validate_provider(value: ProviderReceipt) -> Result(Nil, AssessmentError) {
  case value.completeness {
    Complete -> Ok(Nil)
    Incomplete(reason) -> Error(IncompleteProviderCoverage(reason))
  }
}

fn validate_bar_dates(
  values: List(Date),
  start: Date,
  end: Date,
  listing_value: ListingReceipt,
  dataset: market_calendar.Dataset,
) -> Result(Nil, AssessmentError) {
  use _ <- result.try(validate_date_order(values, InvalidBarDateOrder))
  validate_bar_scope(values, start, end, listing_value, dataset)
}

fn validate_bar_scope(
  values: List(Date),
  start: Date,
  end: Date,
  listing_value: ListingReceipt,
  dataset: market_calendar.Dataset,
) -> Result(Nil, AssessmentError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case within_range(current, start, end) {
        False -> Error(BarOutsideRange(current))
        True ->
          case effective.contains(listing_value.interval, current) {
            False -> Error(BarOutsideListing(current))
            True -> {
              use day <- result.try(trading_day(dataset, current))
              case day {
                calendar.Closed(_) -> Error(BarOnMarketClosure(current))
                calendar.Open(_) ->
                  validate_bar_scope(rest, start, end, listing_value, dataset)
              }
            }
          }
      }
  }
}

fn validate_statuses(
  values: List(StatusReceipt),
  start: Date,
  end: Date,
  listing_value: ListingReceipt,
  dataset: market_calendar.Dataset,
  bar_dates: List(Date),
) -> Result(Nil, AssessmentError) {
  use _ <- result.try(validate_status_order(values))
  validate_status_scope(values, start, end, listing_value, dataset, bar_dates)
}

fn validate_status_order(
  values: List(StatusReceipt),
) -> Result(Nil, AssessmentError) {
  case values {
    [] | [_] -> Ok(Nil)
    [previous, current, ..rest] ->
      case date.compare(previous.session_date, current.session_date) {
        Lt -> validate_status_order([current, ..rest])
        Eq | Gt -> Error(InvalidStatusOrder)
      }
  }
}

fn validate_status_scope(
  values: List(StatusReceipt),
  start: Date,
  end: Date,
  listing_value: ListingReceipt,
  dataset: market_calendar.Dataset,
  bar_dates: List(Date),
) -> Result(Nil, AssessmentError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case within_range(current.session_date, start, end) {
        False -> Error(StatusOutsideRange(current.session_date))
        True ->
          case
            effective.contains(listing_value.interval, current.session_date)
          {
            False -> Error(StatusOutsideListing(current.session_date))
            True ->
              case list.contains(bar_dates, current.session_date) {
                True -> Error(StatusForReturnedBar(current.session_date))
                False -> {
                  use day <- result.try(trading_day(
                    dataset,
                    current.session_date,
                  ))
                  case day {
                    calendar.Closed(_) ->
                      Error(StatusOnMarketClosure(current.session_date))
                    calendar.Open(_) ->
                      validate_status_scope(
                        rest,
                        start,
                        end,
                        listing_value,
                        dataset,
                        bar_dates,
                      )
                  }
                }
              }
          }
      }
  }
}

fn classify(
  current: Date,
  end: Date,
  listing_value: ListingReceipt,
  dataset: market_calendar.Dataset,
  provider_value: ProviderReceipt,
  bar_dates: List(Date),
  status_values: List(StatusReceipt),
  reversed: List(ClassifiedGap),
) -> Result(List(ClassifiedGap), AssessmentError) {
  case date.compare(current, end) {
    Gt -> Ok(list.reverse(reversed))
    Eq | Lt -> {
      use day <- result.try(trading_day(dataset, current))
      use next <- result.try(
        date.add_days(current, 1) |> result.map_error(DateStepError),
      )
      case day {
        calendar.Closed(_) ->
          classify(
            next,
            end,
            listing_value,
            dataset,
            provider_value,
            bar_dates,
            status_values,
            [
              ClassifiedGap(current, finance_ohlcv.MarketClosure, [
                calendar_evidence(dataset),
              ]),
              ..reversed
            ],
          )
        calendar.Open(_) ->
          case effective.contains(listing_value.interval, current) {
            False ->
              classify(
                next,
                end,
                listing_value,
                dataset,
                provider_value,
                bar_dates,
                status_values,
                [
                  ClassifiedGap(current, finance_ohlcv.UnavailableHistory, [
                    listing_evidence(listing_value),
                    calendar_evidence(dataset),
                  ]),
                  ..reversed
                ],
              )
            True ->
              case list.contains(bar_dates, current) {
                True ->
                  classify(
                    next,
                    end,
                    listing_value,
                    dataset,
                    provider_value,
                    bar_dates,
                    status_values,
                    reversed,
                  )
                False ->
                  case find_status(status_values, current) {
                    None -> Error(MissingStatusReceipt(current))
                    Some(status_value) -> {
                      let #(state, evidence) = case status_value.status {
                        Suspended -> #(finance_ohlcv.Suspension, [
                          calendar_evidence(dataset),
                          listing_evidence(listing_value),
                          status_evidence(status_value),
                        ])
                        Trading -> #(finance_ohlcv.ProviderOmission, [
                          calendar_evidence(dataset),
                          listing_evidence(listing_value),
                          status_evidence(status_value),
                          provider_evidence(provider_value),
                        ])
                      }
                      classify(
                        next,
                        end,
                        listing_value,
                        dataset,
                        provider_value,
                        bar_dates,
                        status_values,
                        [ClassifiedGap(current, state, evidence), ..reversed],
                      )
                    }
                  }
              }
          }
      }
    }
  }
}

fn validate_date_order(
  values: List(Date),
  error: AssessmentError,
) -> Result(Nil, AssessmentError) {
  case values {
    [] | [_] -> Ok(Nil)
    [previous, current, ..rest] ->
      case date.compare(previous, current) {
        Lt -> validate_date_order([current, ..rest], error)
        Eq | Gt -> Error(error)
      }
  }
}

fn trading_day(
  dataset: market_calendar.Dataset,
  current: Date,
) -> Result(calendar.TradingDay, AssessmentError) {
  market_calendar.trading_day(dataset, on: current)
  |> result.map_error(CalendarQueryError)
}

fn find_status(values: List(StatusReceipt), on: Date) -> Option(StatusReceipt) {
  case values {
    [] -> None
    [value, ..rest] ->
      case date.compare(value.session_date, on) {
        Eq -> Some(value)
        Gt -> None
        Lt -> find_status(rest, on)
      }
  }
}

fn calendar_evidence(dataset: market_calendar.Dataset) -> Evidence {
  Evidence(
    CalendarSchedule,
    dataset |> market_calendar.source |> source.reference,
  )
}

fn listing_evidence(value: ListingReceipt) -> Evidence {
  Evidence(ListingInterval, value.evidence_reference)
}

fn status_evidence(value: StatusReceipt) -> Evidence {
  Evidence(MarketStatusEvidence, value.evidence_reference)
}

fn provider_evidence(value: ProviderReceipt) -> Evidence {
  Evidence(ProviderCoverage, value.source_reference)
}

fn within_range(value: Date, start: Date, end: Date) -> Bool {
  date.compare(value, start) != Lt && date.compare(value, end) != Gt
}

fn calendar_venue(value: Venue) -> us_calendar.Venue {
  case value {
    Nyse -> us_calendar.Nyse
    Nasdaq -> us_calendar.Nasdaq
  }
}

fn valid_name(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 200
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn valid_reference(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 2000
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn valid_request_id(value: String) -> Bool {
  valid_name(value) && string.length(value) <= 200
}

fn valid_completeness(value: ProviderCompleteness) -> Bool {
  case value {
    Complete -> True
    Incomplete(reason) -> valid_name(reason)
  }
}

fn first_invalid_request_id(values: List(String)) -> Bool {
  values |> list.any(fn(value) { !valid_request_id(value) })
}

type Duplicate {
  NoDuplicate
  Duplicate(String)
}

fn first_duplicate(values: List(String)) -> Duplicate {
  case values {
    [] -> NoDuplicate
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> Duplicate(first)
        False -> first_duplicate(rest)
      }
  }
}
