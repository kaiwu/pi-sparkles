import finance_core/identifier.{type Resolution}
import finance_core/market
import finance_listing/listing.{type Key}
import finance_market_accounting/fact.{
  type Fact, type Period, type StatementScope,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type UnitKind {
  Monetary
  MonetaryPerShare
  ShareCount
  Percentage
  BasisPointValue
  ScalarValue
  ContractCount
  OtherUnit
}

pub type PeriodKind {
  InstantFact
  DurationFact
}

/// Executable, inspectable normalized-metric mapping data.
pub opaque type Mapping {
  Mapping(
    name: String,
    accepted_line_codes: List(String),
    unit_kind: UnitKind,
    period_kind: PeriodKind,
    method: String,
  )
}

pub type MappingError {
  InvalidName
  EmptyAcceptedLineCodes
  InvalidLineCode
  DuplicateLineCode(code: String)
  InvalidMethod
}

pub fn new(
  name name_value: String,
  accepted_line_codes codes: List(String),
  unit_kind unit_kind_value: UnitKind,
  period_kind period_kind_value: PeriodKind,
  method method_value: String,
) -> Result(Mapping, MappingError) {
  case
    valid_token(name_value),
    codes,
    first_invalid(codes),
    first_duplicate(codes),
    valid_description(method_value)
  {
    False, _, _, _, _ -> Error(InvalidName)
    _, [], _, _, _ -> Error(EmptyAcceptedLineCodes)
    _, _, Some(_code), _, _ -> Error(InvalidLineCode)
    _, _, _, Some(code), _ -> Error(DuplicateLineCode(code))
    _, _, _, _, False -> Error(InvalidMethod)
    True, [_, ..], None, None, True ->
      Ok(Mapping(
        name_value,
        codes,
        unit_kind_value,
        period_kind_value,
        method_value,
      ))
  }
}

pub fn resolve(
  mapping mapping_value: Mapping,
  listing listing_key: Key,
  period exact_period: Period,
  statement_scope exact_scope: StatementScope,
  within facts: List(Fact),
) -> Resolution(Fact) {
  facts
  |> list.filter(fn(value) {
    fact.listing(value) == listing_key
    && fact.period(value) == exact_period
    && fact.statement_scope(value) == exact_scope
    && period_matches(mapping_value.period_kind, exact_period)
    && unit_kind(fact.normalized_unit(value)) == mapping_value.unit_kind
    && case fact.line_code(value) {
      Some(code) -> list.contains(mapping_value.accepted_line_codes, code)
      None -> False
    }
  })
  |> identifier.resolve
}

pub fn name(value: Mapping) -> String {
  value.name
}

pub fn accepted_line_codes(value: Mapping) -> List(String) {
  value.accepted_line_codes
}

pub fn expected_unit_kind(value: Mapping) -> UnitKind {
  value.unit_kind
}

pub fn expected_period_kind(value: Mapping) -> PeriodKind {
  value.period_kind
}

pub fn method(value: Mapping) -> String {
  value.method
}

pub fn unit_kind(value: Option(market.Unit)) -> UnitKind {
  case value {
    Some(market.Currency(_)) -> Monetary
    Some(market.CurrencyPerShare(_)) -> MonetaryPerShare
    Some(market.Shares) -> ShareCount
    Some(market.Percent) -> Percentage
    Some(market.BasisPoints) -> BasisPointValue
    Some(market.Scalar) | Some(market.Ratio) -> ScalarValue
    Some(market.Contracts) -> ContractCount
    Some(market.CustomUnit(_)) | None -> OtherUnit
  }
}

fn period_matches(expected: PeriodKind, received: Period) -> Bool {
  case expected, received {
    InstantFact, fact.Instant(_) -> True
    DurationFact, fact.Duration(_, _) -> True
    _, _ -> False
  }
}

fn first_invalid(values: List(String)) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case valid_token(first) {
        True -> first_invalid(rest)
        False -> Some(first)
      }
  }
}

fn first_duplicate(values: List(String)) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> Some(first)
        False -> first_duplicate(rest)
      }
  }
}

fn valid_token(value: String) -> Bool {
  value != ""
  && string.length(value) <= 200
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_:-.",
        character,
      )
    })
  }
}

fn valid_description(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 1000
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}
