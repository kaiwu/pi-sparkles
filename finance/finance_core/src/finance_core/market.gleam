import finance_core/currency.{type Currency}
import gleam/string

pub opaque type CustomLabel {
  CustomLabel(value: String)
}

pub type Unit {
  Scalar
  Currency(Currency)
  CurrencyPerShare(Currency)
  Shares
  Contracts
  Percent
  BasisPoints
  Ratio
  CustomUnit(CustomLabel)
}

pub type Session {
  PreMarket
  Regular
  AfterHours
  Auction
  Closed
  OtherSession(CustomLabel)
}

pub type MarketError {
  InvalidCustomLabel
}

pub fn custom_unit(label: String) -> Result(Unit, MarketError) {
  label
  |> custom_label
  |> result_map(CustomUnit)
}

pub fn other_session(label: String) -> Result(Session, MarketError) {
  label
  |> custom_label
  |> result_map(OtherSession)
}

pub fn label(value: CustomLabel) -> String {
  let CustomLabel(value) = value
  value
}

fn custom_label(value: String) -> Result(CustomLabel, MarketError) {
  case value != "" && string.trim(value) == value {
    True -> Ok(CustomLabel(value))
    False -> Error(InvalidCustomLabel)
  }
}

fn result_map(
  value: Result(a, error),
  transform: fn(a) -> mapped,
) -> Result(mapped, error) {
  case value {
    Ok(value) -> Ok(transform(value))
    Error(error) -> Error(error)
  }
}
