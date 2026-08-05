import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/instrument
import finance_core/source
import finance_core/time
import finance_hk_identity/identity
import finance_hk_rules
import finance_hk_rules/official
import finance_hk_rules/rule
import finance_listing/effective
import finance_market_rules/rule as market_rule
import gleam/option.{None}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_hk_rules.status() |> should.equal(finance_hk_rules.Experimental)
}

pub fn board_lot_is_listing_specific_and_status_is_explicit_test() {
  let first = hk_listing("00001", "hk-first")
  let second = hk_listing("00002", "hk-second")
  let first_rule = rule_record(first, rule.Normal, 500)

  let assert Ok(selected) =
    rule.select(
      listing: first,
      on: civil(2024, 6, 1),
      security_type: rule.Equity,
      market_status: rule.Normal,
      from: [first_rule],
    )
  selected |> rule.common |> market_rule.buy_lot |> should.equal(500)

  rule.select(
    listing: second,
    on: civil(2024, 6, 1),
    security_type: rule.Equity,
    market_status: rule.Normal,
    from: [first_rule],
  )
  |> should.equal(Error(rule.UnknownRule))

  rule.select(
    listing: first,
    on: civil(2024, 6, 1),
    security_type: rule.Equity,
    market_status: rule.Suspended,
    from: [first_rule],
  )
  |> should.equal(Error(rule.UnknownRule))
}

pub fn current_official_spread_profile_requires_listing_evidence_test() {
  let assert Ok(profile) =
    official.applicable_hkd_equity(
      on: civil(2026, 8, 5),
      nominal_price: exact("9.99"),
      board_lot: 500,
      board_lot_source: "HKEX issuer profile for 00001 retrieved 2026-08-05",
    )
  profile
  |> official.tick_size
  |> decimal.to_string
  |> should.equal("0.005")
  profile |> official.board_lot |> should.equal(500)

  let assert Ok(at_ten) =
    official.applicable_hkd_equity(
      on: civil(2026, 8, 5),
      nominal_price: exact("10.00"),
      board_lot: 500,
      board_lot_source: "HKEX issuer profile",
    )
  at_ten |> official.tick_size |> decimal.to_string |> should.equal("0.01")

  official.applicable_hkd_equity(
    on: civil(2026, 8, 2),
    nominal_price: exact("9.99"),
    board_lot: 500,
    board_lot_source: "HKEX issuer profile",
  )
  |> should.equal(Error(official.OutsideReviewedInterval))
  official.applicable_hkd_equity(
    on: civil(2026, 8, 5),
    nominal_price: exact("50.00"),
    board_lot: 500,
    board_lot_source: "HKEX issuer profile",
  )
  |> should.equal(Error(official.UnsupportedPriceBand))
}

fn rule_record(
  listing: identity.Listing,
  status: rule.MarketStatus,
  lot: Int,
) -> rule.Rule {
  let assert Ok(value) =
    rule.new(
      listing: listing,
      effective: interval(),
      security_type: rule.Equity,
      market_status: status,
      tick_size: exact("0.01"),
      buy_lot: lot,
      sell_lot: lot,
      price_limit: market_rule.ProviderPublishedOnly,
      settlement: market_rule.BusinessDays(2),
      eligibility: ["synthetic_only"],
      source: source_ref(),
      evidence_id: None,
    )
  value
}

fn hk_listing(code: String, id: String) -> identity.Listing {
  let assert Ok(instrument_id) = identifier.instrument_id(id)
  let assert Ok(hkd) = currency.from_code("HKD")
  let assert Ok(value) =
    identity.new(
      instrument_id: instrument_id,
      code: code,
      board: identity.MainBoard,
      share_class: identity.OrdinaryShare,
      currency: hkd,
      status: instrument.Active,
    )
  value
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new("synthetic-hk-rules", "fixture/hk-rules", source.Synthetic)
  value
}

fn interval() -> effective.Interval {
  let assert Ok(value) = effective.new(civil(2024, 1, 1), None)
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn exact(value: String) -> decimal.Decimal {
  let assert Ok(parsed) = decimal.parse(value)
  parsed
}
