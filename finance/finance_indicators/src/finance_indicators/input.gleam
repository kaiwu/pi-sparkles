import finance_core/decimal.{type Decimal}
import finance_core/time.{type Date}
import finance_indicators/model.{type ParseablePolicy}
import finance_ohlcv/fact.{type Fact}
import gleam/list
import gleam/string

pub type Alternative {
  Alternative(raw: String, value: Decimal, source_reference: String)
}

/// One numeric source slot. Parseable values that failed mechanical checks are
/// retained separately so the caller's explicit policy controls their use.
pub type NumericFact {
  Known(raw: String, value: Decimal)
  ParseableWithFailedChecks(
    raw: String,
    value: Decimal,
    failed_checks: List(String),
  )
  Unknown(reason: String)
  NotObtained(reason: String)
  Conflicting(alternatives: List(Alternative))
  DecodeFailure(raw: String, reason: String)
}

pub type PriceSlot {
  PriceSlot(date: Date, value: NumericFact)
}

pub type BarSlot {
  BarSlot(date: Date, high: NumericFact, low: NumericFact, close: NumericFact)
}

pub type InputSnapshot {
  PriceInputs(slots: List(PriceSlot))
  BarInputs(slots: List(BarSlot))
}

pub type Unavailable {
  FactUnavailable(state: String, reason: String)
  MechanicalChecksExcluded(failed_checks: List(String), parsed: Decimal)
}

pub type InputError {
  InvalidDecimal(raw: String)
  EmptyAlternatives
  NonAscendingDates
}

pub fn known(raw: String) -> Result(NumericFact, InputError) {
  case decimal.parse(raw) {
    Ok(value) -> Ok(Known(raw, value))
    Error(_) -> Error(InvalidDecimal(raw))
  }
}

pub fn parseable_with_failed_checks(
  raw: String,
  failed_checks: List(String),
) -> Result(NumericFact, InputError) {
  case decimal.parse(raw) {
    Ok(value) -> Ok(ParseableWithFailedChecks(raw, value, failed_checks))
    Error(_) -> Error(InvalidDecimal(raw))
  }
}

pub fn alternative(
  raw: String,
  source_reference: String,
) -> Result(Alternative, InputError) {
  case decimal.parse(raw) {
    Ok(value) -> Ok(Alternative(raw, value, source_reference))
    Error(_) -> Error(InvalidDecimal(raw))
  }
}

pub fn conflicting(
  alternatives: List(Alternative),
) -> Result(NumericFact, InputError) {
  case alternatives {
    [] -> Error(EmptyAlternatives)
    _ -> Ok(Conflicting(alternatives))
  }
}

/// Adapt the shared market-data fact without promoting any state to a verdict.
pub fn from_market_fact(raw: String, value: Fact(Decimal)) -> NumericFact {
  case value {
    fact.Known(value) -> Known(raw, value)
    fact.Unknown(reason) -> Unknown(reason)
    fact.NotObtained(reason) -> NotObtained(reason)
    fact.Conflicting(values) ->
      Conflicting(
        list.map(values, fn(value) {
          Alternative(
            decimal.to_string(value),
            value,
            "market_fact_alternative",
          )
        }),
      )
    fact.DecodeFailure(raw, reason) -> DecodeFailure(raw, reason)
  }
}

pub fn usable(
  value: NumericFact,
  policy: ParseablePolicy,
) -> Result(Decimal, Unavailable) {
  case value, policy {
    Known(_, value), _ -> Ok(value)
    ParseableWithFailedChecks(_, value, _), model.IncludeParseableWithChecks ->
      Ok(value)
    ParseableWithFailedChecks(_, value, checks),
      model.ExcludeParseableWithChecks
    -> Error(MechanicalChecksExcluded(checks, value))
    Unknown(reason), _ -> Error(FactUnavailable("unknown", reason))
    NotObtained(reason), _ -> Error(FactUnavailable("not_obtained", reason))
    Conflicting(_), _ ->
      Error(FactUnavailable("conflicting", "unselected_alternatives"))
    DecodeFailure(_, reason), _ ->
      Error(FactUnavailable("decode_failure", reason))
  }
}

pub fn validate_price_slots(slots: List(PriceSlot)) -> Result(Nil, InputError) {
  validate_dates(list.map(slots, fn(slot) { slot.date }))
}

pub fn validate_bar_slots(slots: List(BarSlot)) -> Result(Nil, InputError) {
  validate_dates(list.map(slots, fn(slot) { slot.date }))
}

pub fn unavailable_name(value: Unavailable) -> String {
  case value {
    FactUnavailable(state, reason) -> state <> ":" <> reason
    MechanicalChecksExcluded(checks, _) ->
      "mechanical_checks_excluded:" <> string.join(checks, with: ",")
  }
}

fn validate_dates(values: List(Date)) -> Result(Nil, InputError) {
  case values {
    [] | [_] -> Ok(Nil)
    [first, second, ..rest] ->
      case model.date_key(first) < model.date_key(second) {
        True -> validate_dates([second, ..rest])
        False -> Error(NonAscendingDates)
      }
  }
}
