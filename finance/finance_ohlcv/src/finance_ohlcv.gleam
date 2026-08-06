import finance_calendar/date
import finance_core/adjustment.{type Adjustment}
import finance_core/currency.{type Currency}
import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/market.{type Session}
import finance_core/observation.{type Observation}
import finance_core/source.{type SourceRef}
import finance_core/time.{type Date, type Instant, type Timezone}
import finance_series/observed
import finance_series/returns
import finance_series/series.{type Series}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string

pub type Interval {
  Daily
}

pub type VolumeUnit {
  Shares
  UnknownVolumeUnit
}

pub type TimeBasis {
  SourceInstant
  SessionDateAnchor
}

pub opaque type ExactValue {
  ExactValue(raw: String, normalized: Decimal)
}

pub opaque type ExactCount {
  ExactCount(raw: String, normalized: Int)
}

pub opaque type Bar {
  Bar(
    source_timestamp: String,
    at: Instant,
    time_basis: TimeBasis,
    session_date: Date,
    open: ExactValue,
    high: ExactValue,
    low: ExactValue,
    close: ExactValue,
    volume: ExactValue,
    trade_count: Option(ExactCount),
    vwap: Option(ExactValue),
  )
}

pub type GapState {
  MarketClosure
  Suspension
  ProviderOmission
  UnavailableHistory
}

pub type Gap {
  Gap(session_date: Date, state: GapState, evidence_reference: Option(String))
}

pub type CalendarAssessment {
  CalendarNotAssessed(reason: String)
  CalendarAssessed(gaps: List(Gap))
}

pub type Pagination {
  AllPages
  TruncatedByPageBudget(maximum_pages: Int)
  TruncatedByBarBudget(maximum_bars: Int)
}

pub type Availability {
  BarsReturned
  NoBarsReturned
}

pub opaque type Batch {
  Batch(
    interval: Interval,
    timezone: Timezone,
    currency: Currency,
    volume_unit: VolumeUnit,
    adjustment: Adjustment,
    session: Session,
    pagination: Pagination,
    calendar: CalendarAssessment,
    observations: List(Observation(Bar)),
    duplicates_collapsed: Int,
  )
}

pub type ValueError {
  InvalidDecimal
  InvalidCount
}

pub type BarError {
  NegativePrice
  NegativeVolume
  NegativeTradeCount
  NegativeVwap
  VwapAboveHigh
  VwapBelowLow
  HighBelowPrice
  LowAbovePrice
  InvalidSourceTimestamp
}

pub type BatchError {
  InvalidCalendarReason
  InvalidGapEvidence
  InvalidGapOrder
  SourceProviderMismatch(expected: String, received: String)
  RetrievalBeforeBar(at: Instant)
  OutOfOrder(previous: Instant, current: Instant)
  ConflictingDuplicate(at: Instant)
  InvalidSeries(series.SeriesError)
}

pub fn exact(raw: String) -> Result(ExactValue, ValueError) {
  case decimal.parse(raw) {
    Ok(value) -> Ok(ExactValue(raw, value))
    Error(_) -> Error(InvalidDecimal)
  }
}

pub fn exact_count(raw: String) -> Result(ExactCount, ValueError) {
  case int.parse(raw) {
    Ok(value) -> Ok(ExactCount(raw, value))
    Error(_) -> Error(InvalidCount)
  }
}

pub fn bar(
  source_timestamp source_timestamp: String,
  at at: Instant,
  session_date session_date: Date,
  open open: ExactValue,
  high high: ExactValue,
  low low: ExactValue,
  close close: ExactValue,
  volume volume: ExactValue,
  trade_count trade_count: Option(ExactCount),
  vwap vwap: Option(ExactValue),
) -> Result(Bar, BarError) {
  make_bar(
    source_timestamp,
    at,
    SourceInstant,
    session_date,
    open,
    high,
    low,
    close,
    volume,
    trade_count,
    vwap,
  )
}

/// Construct a daily bar from a provider that supplies a civil date but no
/// source instant. The UTC-midnight instant is an ordering anchor only; callers
/// must retain `SessionDateAnchor` and must not present it as provider time.
pub fn date_bar(
  source_date source_date: String,
  session_date session_date: Date,
  open open: ExactValue,
  high high: ExactValue,
  low low: ExactValue,
  close close: ExactValue,
  volume volume: ExactValue,
  trade_count trade_count: Option(ExactCount),
  vwap vwap: Option(ExactValue),
) -> Result(Bar, BarError) {
  let assert Ok(epoch) = time.date(1970, 1, 1)
  let assert Ok(anchor) =
    time.instant(date.days_between(epoch, session_date) * 86_400_000)
  make_bar(
    source_date,
    anchor,
    SessionDateAnchor,
    session_date,
    open,
    high,
    low,
    close,
    volume,
    trade_count,
    vwap,
  )
}

fn make_bar(
  source_timestamp: String,
  at: Instant,
  time_basis: TimeBasis,
  session_date: Date,
  open: ExactValue,
  high: ExactValue,
  low: ExactValue,
  close: ExactValue,
  volume: ExactValue,
  trade_count: Option(ExactCount),
  vwap: Option(ExactValue),
) -> Result(Bar, BarError) {
  case valid_text(source_timestamp) {
    False -> Error(InvalidSourceTimestamp)
    True -> {
      use _ <- result.try(validate_prices(open, high, low, close))
      use _ <- result.try(validate_non_negative(volume, NegativeVolume))
      use _ <- result.try(validate_count(trade_count))
      use _ <- result.try(validate_vwap(vwap, high, low))
      Ok(Bar(
        source_timestamp,
        at,
        time_basis,
        session_date,
        open,
        high,
        low,
        close,
        volume,
        trade_count,
        vwap,
      ))
    }
  }
}

pub fn batch(
  bars bars: List(Bar),
  retrieved_at retrieved_at: Instant,
  timezone timezone: Timezone,
  currency currency: Currency,
  volume_unit volume_unit: VolumeUnit,
  adjustment adjustment: Adjustment,
  session session: Session,
  source source_ref: SourceRef,
  expected_provider expected_provider: String,
  pagination pagination: Pagination,
  calendar calendar: CalendarAssessment,
) -> Result(Batch, BatchError) {
  use _ <- result.try(validate_calendar(calendar))
  let received_provider = source.provider(source_ref)
  use _ <- result.try(case received_provider == expected_provider {
    True -> Ok(Nil)
    False -> Error(SourceProviderMismatch(expected_provider, received_provider))
  })
  use #(deduplicated, duplicate_count) <- result.try(deduplicate(bars, [], 0))
  use observations <- result.try(
    observe(
      deduplicated,
      retrieved_at,
      timezone,
      adjustment,
      session,
      source_ref,
      [],
    ),
  )
  use _ <- result.try(
    observed.from_observations(observations)
    |> result.map_error(InvalidSeries),
  )
  Ok(Batch(
    Daily,
    timezone,
    currency,
    volume_unit,
    adjustment,
    session,
    pagination,
    calendar,
    observations,
    duplicate_count,
  ))
}

pub fn raw(value: ExactValue) -> String {
  value.raw
}

pub fn normalized(value: ExactValue) -> Decimal {
  value.normalized
}

pub fn count_raw(value: ExactCount) -> String {
  value.raw
}

pub fn count_normalized(value: ExactCount) -> Int {
  value.normalized
}

pub fn source_timestamp(value: Bar) -> String {
  value.source_timestamp
}

pub fn at(value: Bar) -> Instant {
  value.at
}

pub fn time_basis(value: Bar) -> TimeBasis {
  value.time_basis
}

pub fn session_date(value: Bar) -> Date {
  value.session_date
}

pub fn open(value: Bar) -> ExactValue {
  value.open
}

pub fn high(value: Bar) -> ExactValue {
  value.high
}

pub fn low(value: Bar) -> ExactValue {
  value.low
}

pub fn close(value: Bar) -> ExactValue {
  value.close
}

pub fn volume(value: Bar) -> ExactValue {
  value.volume
}

pub fn trade_count(value: Bar) -> Option(ExactCount) {
  value.trade_count
}

pub fn vwap(value: Bar) -> Option(ExactValue) {
  value.vwap
}

pub fn interval(value: Batch) -> Interval {
  value.interval
}

pub fn timezone(value: Batch) -> Timezone {
  value.timezone
}

pub fn currency(value: Batch) -> Currency {
  value.currency
}

pub fn volume_unit(value: Batch) -> VolumeUnit {
  value.volume_unit
}

pub fn adjustment(value: Batch) -> Adjustment {
  value.adjustment
}

pub fn session(value: Batch) -> Session {
  value.session
}

pub fn pagination(value: Batch) -> Pagination {
  value.pagination
}

pub fn calendar_assessment(value: Batch) -> CalendarAssessment {
  value.calendar
}

pub fn observations(value: Batch) -> List(Observation(Bar)) {
  value.observations
}

pub fn duplicates_collapsed(value: Batch) -> Int {
  value.duplicates_collapsed
}

pub fn availability(value: Batch) -> Availability {
  case value.observations {
    [] -> NoBarsReturned
    [_, ..] -> BarsReturned
  }
}

pub fn close_series(value: Batch) -> Series(Decimal) {
  let assert Ok(timeline) = observed.from_observations(value.observations)
  timeline
  |> observed.values
  |> series.map(fn(bar_value) { bar_value.close.normalized })
}

pub fn simple_returns(
  value: Batch,
  scale scale: Int,
  rounding rounding: RoundingMode,
) -> Result(Series(Decimal), returns.ReturnError) {
  returns.simple(close_series(value), scale:, rounding:)
}

fn validate_prices(
  open_value: ExactValue,
  high_value: ExactValue,
  low_value: ExactValue,
  close_value: ExactValue,
) -> Result(Nil, BarError) {
  use _ <- result.try(validate_non_negative(open_value, NegativePrice))
  use _ <- result.try(validate_non_negative(high_value, NegativePrice))
  use _ <- result.try(validate_non_negative(low_value, NegativePrice))
  use _ <- result.try(validate_non_negative(close_value, NegativePrice))
  case
    decimal.compare(high_value.normalized, open_value.normalized),
    decimal.compare(high_value.normalized, low_value.normalized),
    decimal.compare(high_value.normalized, close_value.normalized),
    decimal.compare(low_value.normalized, open_value.normalized),
    decimal.compare(low_value.normalized, high_value.normalized),
    decimal.compare(low_value.normalized, close_value.normalized)
  {
    Lt, _, _, _, _, _ | _, Lt, _, _, _, _ | _, _, Lt, _, _, _ ->
      Error(HighBelowPrice)
    _, _, _, Gt, _, _ | _, _, _, _, Gt, _ | _, _, _, _, _, Gt ->
      Error(LowAbovePrice)
    _, _, _, _, _, _ -> Ok(Nil)
  }
}

fn validate_non_negative(
  value: ExactValue,
  error: BarError,
) -> Result(Nil, BarError) {
  case decimal.compare(value.normalized, decimal.zero()) {
    Lt -> Error(error)
    Eq | Gt -> Ok(Nil)
  }
}

fn validate_count(value: Option(ExactCount)) -> Result(Nil, BarError) {
  case value {
    Some(value) if value.normalized < 0 -> Error(NegativeTradeCount)
    _ -> Ok(Nil)
  }
}

fn validate_vwap(
  value: Option(ExactValue),
  high: ExactValue,
  low: ExactValue,
) -> Result(Nil, BarError) {
  case value {
    Some(value) -> {
      use _ <- result.try(validate_non_negative(value, NegativeVwap))
      case
        decimal.compare(value.normalized, high.normalized),
        decimal.compare(value.normalized, low.normalized)
      {
        Gt, _ -> Error(VwapAboveHigh)
        _, Lt -> Error(VwapBelowLow)
        _, _ -> Ok(Nil)
      }
    }
    None -> Ok(Nil)
  }
}

fn validate_calendar(value: CalendarAssessment) -> Result(Nil, BatchError) {
  case value {
    CalendarNotAssessed(reason) ->
      case valid_identifier(reason) {
        True -> Ok(Nil)
        False -> Error(InvalidCalendarReason)
      }
    CalendarAssessed(gaps) -> validate_gaps(gaps)
  }
}

fn validate_gaps(values: List(Gap)) -> Result(Nil, BatchError) {
  use _ <- result.try(validate_gap_evidence(values))
  validate_gap_order(values)
}

fn validate_gap_order(values: List(Gap)) -> Result(Nil, BatchError) {
  case values {
    [] | [_] -> Ok(Nil)
    [previous, current, ..rest] ->
      case date.compare(previous.session_date, current.session_date) {
        Lt -> validate_gap_order([current, ..rest])
        Eq | Gt -> Error(InvalidGapOrder)
      }
  }
}

fn validate_gap_evidence(values: List(Gap)) -> Result(Nil, BatchError) {
  case values {
    [] -> Ok(Nil)
    [Gap(_, _, Some(reference)), ..rest] ->
      case valid_text(reference) {
        True -> validate_gap_evidence(rest)
        False -> Error(InvalidGapEvidence)
      }
    [_, ..rest] -> validate_gap_evidence(rest)
  }
}

fn deduplicate(
  remaining: List(Bar),
  reversed: List(Bar),
  duplicates: Int,
) -> Result(#(List(Bar), Int), BatchError) {
  case remaining, reversed {
    [], _ -> Ok(#(list.reverse(reversed), duplicates))
    [current, ..rest], [] -> deduplicate(rest, [current], duplicates)
    [current, ..rest], [previous, ..] -> {
      let previous_ms = time.unix_milliseconds(previous.at)
      let current_ms = time.unix_milliseconds(current.at)
      case int.compare(current_ms, previous_ms) {
        Gt -> deduplicate(rest, [current, ..reversed], duplicates)
        Lt -> Error(OutOfOrder(previous.at, current.at))
        Eq ->
          case current == previous {
            True -> deduplicate(rest, reversed, duplicates + 1)
            False -> Error(ConflictingDuplicate(current.at))
          }
      }
    }
  }
}

fn observe(
  bars: List(Bar),
  retrieved_at: Instant,
  timezone: Timezone,
  adjustment: Adjustment,
  session: Session,
  source_ref: SourceRef,
  reversed: List(Observation(Bar)),
) -> Result(List(Observation(Bar)), BatchError) {
  case bars {
    [] -> Ok(list.reverse(reversed))
    [bar_value, ..rest] ->
      case
        time.unix_milliseconds(retrieved_at)
        < time.unix_milliseconds(bar_value.at)
      {
        True -> Error(RetrievalBeforeBar(bar_value.at))
        False ->
          observe(
            rest,
            retrieved_at,
            timezone,
            adjustment,
            session,
            source_ref,
            [
              observation.Observation(
                value: bar_value,
                as_of: bar_value.at,
                retrieved_at: retrieved_at,
                timezone: Some(timezone),
                source: source_ref,
                evidence_id: None,
                freshness: observation.UnknownFreshness,
                entitlement: observation.EndOfDay,
                quality: observation.Reported,
                unit: None,
                adjustment: Some(adjustment),
                session: Some(session),
              ),
              ..reversed
            ],
          )
      }
  }
}

fn valid_identifier(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 200
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  }
}

fn valid_text(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 500
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
