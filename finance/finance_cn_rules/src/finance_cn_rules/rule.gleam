import finance_cn_identity/identity
import finance_core/decimal.{type Decimal}
import finance_core/source.{type SourceRef}
import finance_core/time.{type Date}
import finance_listing/effective.{type Interval}
import finance_market_rules/rule as market_rule
import finance_provenance/identity as provenance_identity
import gleam/list
import gleam/option.{type Option}

pub type SecurityType {
  Equity
  ExchangeTradedFund
  ConvertibleBond
}

pub type MarketStatus {
  Normal
  SpecialTreatment
  DelistingRisk
  Suspended
}

pub opaque type Rule {
  Rule(
    listing: identity.Listing,
    security_type: SecurityType,
    market_status: MarketStatus,
    value: market_rule.Rule,
  )
}

pub type RuleError {
  InvalidRule(market_rule.RuleError)
}

pub type SelectionError {
  UnknownRule
  ConflictingRules(count: Int)
}

pub fn new(
  listing listing_value: identity.Listing,
  effective effective_interval: Interval,
  security_type security_type_value: SecurityType,
  market_status market_status_value: MarketStatus,
  tick_size tick_size_value: Decimal,
  buy_lot buy_lot_value: Int,
  sell_lot sell_lot_value: Int,
  price_limit price_limit_value: market_rule.PriceLimit,
  settlement settlement_value: market_rule.Settlement,
  eligibility eligibility_values: List(String),
  source source_ref: SourceRef,
  evidence_id evidence: Option(provenance_identity.EvidenceId),
) -> Result(Rule, RuleError) {
  case
    market_rule.new(
      listing: identity.key(listing_value),
      effective: effective_interval,
      security_class: security_type_name(security_type_value),
      market_status: market_status_name(market_status_value),
      tick_size: tick_size_value,
      buy_lot: buy_lot_value,
      sell_lot: sell_lot_value,
      price_limit: price_limit_value,
      settlement: settlement_value,
      eligibility: eligibility_values,
      source: source_ref,
      evidence_id: evidence,
    )
  {
    Ok(value) ->
      Ok(Rule(listing_value, security_type_value, market_status_value, value))
    Error(error) -> Error(InvalidRule(error))
  }
}

pub fn select(
  listing listing_value: identity.Listing,
  on date: Date,
  security_type security_type_value: SecurityType,
  market_status market_status_value: MarketStatus,
  from rules: List(Rule),
) -> Result(Rule, SelectionError) {
  let matches =
    rules
    |> list.filter(fn(value) {
      identity.key(value.listing) == identity.key(listing_value)
      && identity.board(value.listing) == identity.board(listing_value)
      && identity.share_class(value.listing)
      == identity.share_class(listing_value)
      && value.security_type == security_type_value
      && value.market_status == market_status_value
      && effective.contains(market_rule.effective(value.value), date)
    })
  case matches {
    [] -> Error(UnknownRule)
    [value] -> Ok(value)
    many -> Error(ConflictingRules(list.length(many)))
  }
}

pub fn listing(value: Rule) -> identity.Listing {
  value.listing
}

pub fn security_type(value: Rule) -> SecurityType {
  value.security_type
}

pub fn market_status(value: Rule) -> MarketStatus {
  value.market_status
}

pub fn common(value: Rule) -> market_rule.Rule {
  value.value
}

pub fn security_type_name(value: SecurityType) -> String {
  case value {
    Equity -> "equity"
    ExchangeTradedFund -> "exchange_traded_fund"
    ConvertibleBond -> "convertible_bond"
  }
}

pub fn market_status_name(value: MarketStatus) -> String {
  case value {
    Normal -> "normal"
    SpecialTreatment -> "special_treatment"
    DelistingRisk -> "delisting_risk"
    Suspended -> "suspended"
  }
}
