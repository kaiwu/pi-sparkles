import finance_core/currency.{type Currency}
import finance_core/decimal.{type Decimal}
import finance_core/market
import finance_core/observation.{type Observation}
import finance_core/source.{type SourceRef}
import finance_core/time.{type Instant, type Timezone}
import gleam/list
import gleam/option.{None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/string

pub type SizeUnit {
  ProviderReportedSize
}

pub opaque type ExactValue {
  ExactValue(raw: String, normalized: Decimal)
}

pub opaque type Side {
  Side(exchange: String, price: ExactValue, size: ExactValue)
}

pub opaque type Quote {
  Quote(
    source_timestamp: String,
    at: Instant,
    currency: Currency,
    bid: Side,
    ask: Side,
    conditions: List(String),
    tape: String,
    size_unit: SizeUnit,
  )
}

pub type ValueError {
  InvalidDecimal
}

pub type SideError {
  InvalidExchange
  NegativePrice
  NegativeSize
}

pub type QuoteError {
  InvalidSourceTimestamp
  InvalidCondition
  InvalidTape
}

pub type ObservationError {
  SourceProviderMismatch(expected: String, received: String)
  RetrievalBeforeQuote
}

pub fn exact(raw: String) -> Result(ExactValue, ValueError) {
  case decimal.parse(raw) {
    Ok(value) -> Ok(ExactValue(raw, value))
    Error(_) -> Error(InvalidDecimal)
  }
}

pub fn side(
  exchange exchange: String,
  price price: ExactValue,
  size size: ExactValue,
) -> Result(Side, SideError) {
  case valid_code(exchange) {
    False -> Error(InvalidExchange)
    True ->
      case decimal.compare(price.normalized, decimal.zero()) {
        Lt -> Error(NegativePrice)
        Eq | Gt ->
          case decimal.compare(size.normalized, decimal.zero()) {
            Lt -> Error(NegativeSize)
            Eq | Gt -> Ok(Side(exchange, price, size))
          }
      }
  }
}

pub fn quote(
  source_timestamp source_timestamp: String,
  at at: Instant,
  currency currency: Currency,
  bid bid: Side,
  ask ask: Side,
  conditions conditions: List(String),
  tape tape: String,
  size_unit size_unit: SizeUnit,
) -> Result(Quote, QuoteError) {
  case
    valid_text(source_timestamp),
    list.all(conditions, valid_code),
    valid_code(tape)
  {
    False, _, _ -> Error(InvalidSourceTimestamp)
    _, False, _ -> Error(InvalidCondition)
    _, _, False -> Error(InvalidTape)
    True, True, True ->
      Ok(Quote(
        source_timestamp,
        at,
        currency,
        bid,
        ask,
        conditions,
        tape,
        size_unit,
      ))
  }
}

pub fn observe(
  value value: Quote,
  retrieved_at retrieved_at: Instant,
  timezone timezone: Timezone,
  source source_ref: SourceRef,
  expected_provider expected_provider: String,
) -> Result(Observation(Quote), ObservationError) {
  let received_provider = source.provider(source_ref)
  case received_provider == expected_provider {
    False -> Error(SourceProviderMismatch(expected_provider, received_provider))
    True ->
      case
        time.unix_milliseconds(retrieved_at) < time.unix_milliseconds(value.at)
      {
        True -> Error(RetrievalBeforeQuote)
        False ->
          Ok(observation.Observation(
            value: value,
            as_of: value.at,
            retrieved_at: retrieved_at,
            timezone: Some(timezone),
            source: source_ref,
            evidence_id: None,
            freshness: observation.UnknownFreshness,
            entitlement: observation.UnknownEntitlement,
            quality: observation.Reported,
            unit: Some(market.CurrencyPerShare(value.currency)),
            adjustment: None,
            session: None,
          ))
      }
  }
}

pub fn raw(value: ExactValue) -> String {
  value.raw
}

pub fn normalized(value: ExactValue) -> Decimal {
  value.normalized
}

pub fn exchange(value: Side) -> String {
  value.exchange
}

pub fn price(value: Side) -> ExactValue {
  value.price
}

pub fn size(value: Side) -> ExactValue {
  value.size
}

pub fn source_timestamp(value: Quote) -> String {
  value.source_timestamp
}

pub fn at(value: Quote) -> Instant {
  value.at
}

pub fn currency(value: Quote) -> Currency {
  value.currency
}

pub fn bid(value: Quote) -> Side {
  value.bid
}

pub fn ask(value: Quote) -> Side {
  value.ask
}

pub fn conditions(value: Quote) -> List(String) {
  value.conditions
}

pub fn tape(value: Quote) -> String {
  value.tape
}

pub fn size_unit(value: Quote) -> SizeUnit {
  value.size_unit
}

fn valid_code(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 40
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn valid_text(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
