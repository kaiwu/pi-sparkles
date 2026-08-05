import finance_core/decimal
import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_listing/effective
import finance_listing/listing
import finance_market_rules
import finance_market_rules/rule
import finance_track
import gleam/option.{type Option, None}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_market_rules.status()
  |> should.equal(finance_market_rules.Experimental)
}

pub fn invalid_or_overlapping_rules_fail_closed_test() {
  let first = rule_record(civil(2024, 1, 1), None)
  let second = rule_record(civil(2024, 6, 1), None)
  rule.select(
    listing: listing_key(),
    on: civil(2024, 7, 1),
    security_class: "equity",
    market_status: "normal",
    from: [first, second],
  )
  |> should.equal(Error(rule.ConflictingRules(2)))

  rule.select(
    listing: listing_key(),
    on: civil(2023, 12, 31),
    security_class: "equity",
    market_status: "normal",
    from: [first],
  )
  |> should.equal(Error(rule.UnknownRule))
}

pub fn constructors_reject_invalid_execution_constraints_test() {
  rule.new(
    listing: listing_key(),
    effective: interval(civil(2024, 1, 1), None),
    security_class: "equity",
    market_status: "normal",
    tick_size: decimal("0"),
    buy_lot: 100,
    sell_lot: 1,
    price_limit: rule.NoDailyLimit,
    settlement: rule.BusinessDays(1),
    eligibility: [],
    source: source_ref(),
    evidence_id: None,
  )
  |> should.equal(Error(rule.NonPositiveTickSize))
}

fn rule_record(start: time.Date, end: Option(time.Date)) -> rule.Rule {
  let assert Ok(value) =
    rule.new(
      listing: listing_key(),
      effective: interval(start, end),
      security_class: "equity",
      market_status: "normal",
      tick_size: decimal("0.01"),
      buy_lot: 100,
      sell_lot: 1,
      price_limit: rule.Percent(decimal("0.10")),
      settlement: rule.BusinessDays(1),
      eligibility: ["synthetic_only"],
      source: source_ref(),
      evidence_id: None,
    )
  value
}

fn listing_key() -> listing.Key {
  let assert Ok(instrument) = identifier.instrument_id("synthetic-listing")
  let assert Ok(symbol) = identifier.symbol("000001")
  let assert Ok(mic) = identifier.mic("XSHG")
  listing.new(finance_track.Cn, instrument, symbol, mic)
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new("synthetic-rules", "fixture/rules", source.Synthetic)
  value
}

fn interval(start: time.Date, end: Option(time.Date)) -> effective.Interval {
  let assert Ok(value) = effective.new(start, end)
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn decimal(value: String) -> decimal.Decimal {
  let assert Ok(parsed) = decimal.parse(value)
  parsed
}
