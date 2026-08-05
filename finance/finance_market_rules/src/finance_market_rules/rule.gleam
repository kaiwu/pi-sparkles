import finance_core/decimal.{type Decimal}
import finance_core/source.{type SourceRef}
import finance_core/time.{type Date}
import finance_listing/effective.{type Interval}
import finance_listing/listing.{type Key}
import finance_provenance/identity.{type EvidenceId}
import gleam/list
import gleam/option.{type Option}
import gleam/order.{Eq, Gt, Lt}
import gleam/string

pub type PriceLimit {
  NoDailyLimit
  Percent(Decimal)
  ProviderPublishedOnly
  TradingProhibited
}

pub type Settlement {
  SameDay
  BusinessDays(Int)
}

/// A source-labelled rule record for one exact listing and effective interval.
///
/// Market packages own the vocabulary used by `security_class`,
/// `market_status`, and `eligibility`. This package owns validation and strict
/// selection without embedding any market's rule constants.
pub opaque type Rule {
  Rule(
    listing: Key,
    effective: Interval,
    security_class: String,
    market_status: String,
    tick_size: Decimal,
    buy_lot: Int,
    sell_lot: Int,
    price_limit: PriceLimit,
    settlement: Settlement,
    eligibility: List(String),
    source: SourceRef,
    evidence_id: Option(EvidenceId),
  )
}

pub type RuleError {
  InvalidSecurityClass
  InvalidMarketStatus
  NonPositiveTickSize
  NonPositiveBuyLot
  NonPositiveSellLot
  InvalidPriceLimit
  InvalidSettlement
  InvalidEligibility
  DuplicateEligibility(value: String)
}

pub type SelectionError {
  UnknownRule
  ConflictingRules(count: Int)
}

pub fn new(
  listing listing_key: Key,
  effective effective_interval: Interval,
  security_class security_class_value: String,
  market_status market_status_value: String,
  tick_size tick_size_value: Decimal,
  buy_lot buy_lot_value: Int,
  sell_lot sell_lot_value: Int,
  price_limit price_limit_value: PriceLimit,
  settlement settlement_value: Settlement,
  eligibility eligibility_values: List(String),
  source source_ref: SourceRef,
  evidence_id evidence: Option(EvidenceId),
) -> Result(Rule, RuleError) {
  case
    valid_name(security_class_value),
    valid_name(market_status_value),
    decimal.compare(tick_size_value, decimal.zero()),
    buy_lot_value > 0,
    sell_lot_value > 0,
    valid_price_limit(price_limit_value),
    valid_settlement(settlement_value),
    first_invalid_eligibility(eligibility_values),
    first_duplicate(eligibility_values)
  {
    False, _, _, _, _, _, _, _, _ -> Error(InvalidSecurityClass)
    _, False, _, _, _, _, _, _, _ -> Error(InvalidMarketStatus)
    _, _, Lt, _, _, _, _, _, _ -> Error(NonPositiveTickSize)
    _, _, Eq, _, _, _, _, _, _ -> Error(NonPositiveTickSize)
    _, _, _, False, _, _, _, _, _ -> Error(NonPositiveBuyLot)
    _, _, _, _, False, _, _, _, _ -> Error(NonPositiveSellLot)
    _, _, _, _, _, False, _, _, _ -> Error(InvalidPriceLimit)
    _, _, _, _, _, _, False, _, _ -> Error(InvalidSettlement)
    _, _, _, _, _, _, _, True, _ -> Error(InvalidEligibility)
    _, _, _, _, _, _, _, _, SomeDuplicate(value) ->
      Error(DuplicateEligibility(value))
    True, True, Gt, True, True, True, True, False, NoDuplicate ->
      Ok(Rule(
        listing: listing_key,
        effective: effective_interval,
        security_class: security_class_value,
        market_status: market_status_value,
        tick_size: tick_size_value,
        buy_lot: buy_lot_value,
        sell_lot: sell_lot_value,
        price_limit: price_limit_value,
        settlement: settlement_value,
        eligibility: eligibility_values,
        source: source_ref,
        evidence_id: evidence,
      ))
  }
}

pub fn select(
  listing listing_key: Key,
  on date: Date,
  security_class security_class_value: String,
  market_status market_status_value: String,
  from rules: List(Rule),
) -> Result(Rule, SelectionError) {
  let matches =
    rules
    |> list.filter(fn(value) {
      value.listing == listing_key
      && value.security_class == security_class_value
      && value.market_status == market_status_value
      && effective.contains(value.effective, date)
    })
  case matches {
    [] -> Error(UnknownRule)
    [value] -> Ok(value)
    many -> Error(ConflictingRules(list.length(many)))
  }
}

pub fn listing(value: Rule) -> Key {
  value.listing
}

pub fn effective(value: Rule) -> Interval {
  value.effective
}

pub fn security_class(value: Rule) -> String {
  value.security_class
}

pub fn market_status(value: Rule) -> String {
  value.market_status
}

pub fn tick_size(value: Rule) -> Decimal {
  value.tick_size
}

pub fn buy_lot(value: Rule) -> Int {
  value.buy_lot
}

pub fn sell_lot(value: Rule) -> Int {
  value.sell_lot
}

pub fn price_limit(value: Rule) -> PriceLimit {
  value.price_limit
}

pub fn settlement(value: Rule) -> Settlement {
  value.settlement
}

pub fn eligibility(value: Rule) -> List(String) {
  value.eligibility
}

pub fn source(value: Rule) -> SourceRef {
  value.source
}

pub fn evidence_id(value: Rule) -> Option(EvidenceId) {
  value.evidence_id
}

type Duplicate {
  NoDuplicate
  SomeDuplicate(String)
}

fn valid_name(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn valid_price_limit(value: PriceLimit) -> Bool {
  case value {
    Percent(percent) -> decimal.compare(percent, decimal.zero()) == Gt
    NoDailyLimit | ProviderPublishedOnly | TradingProhibited -> True
  }
}

fn valid_settlement(value: Settlement) -> Bool {
  case value {
    SameDay -> True
    BusinessDays(days) -> days > 0
  }
}

fn first_invalid_eligibility(values: List(String)) -> Bool {
  values |> list.any(fn(value) { !valid_name(value) })
}

fn first_duplicate(values: List(String)) -> Duplicate {
  case values {
    [] -> NoDuplicate
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> SomeDuplicate(first)
        False -> first_duplicate(rest)
      }
  }
}
