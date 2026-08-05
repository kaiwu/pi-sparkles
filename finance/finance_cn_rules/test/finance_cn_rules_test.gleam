import finance_cn_identity/identity
import finance_cn_rules
import finance_cn_rules/official
import finance_cn_rules/rule
import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/instrument
import finance_core/source
import finance_core/time
import finance_listing/effective
import finance_market_rules/rule as market_rule
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_cn_rules.status() |> should.equal(finance_cn_rules.Experimental)
}

pub fn board_status_and_regime_are_exact_selection_dimensions_test() {
  let listing = mainland_listing(identity.SseMainBoard)
  let normal_old =
    rule_record(
      listing,
      rule.Normal,
      100,
      civil(2020, 1, 1),
      Some(civil(2023, 12, 31)),
    )
  let normal_new =
    rule_record(listing, rule.Normal, 200, civil(2024, 1, 1), None)
  let special =
    rule_record(listing, rule.SpecialTreatment, 50, civil(2024, 1, 1), None)

  let assert Ok(selected) =
    rule.select(
      listing: listing,
      on: civil(2024, 6, 1),
      security_type: rule.Equity,
      market_status: rule.Normal,
      from: [normal_old, normal_new, special],
    )
  selected |> rule.common |> market_rule.buy_lot |> should.equal(200)

  rule.select(
    listing: mainland_listing(identity.StarMarket),
    on: civil(2024, 6, 1),
    security_type: rule.Equity,
    market_status: rule.Normal,
    from: [normal_new],
  )
  |> should.equal(Error(rule.UnknownRule))
}

pub fn suspension_is_not_silently_treated_as_normal_test() {
  let listing = mainland_listing(identity.SzseMainBoard)
  let normal = rule_record(listing, rule.Normal, 100, civil(2024, 1, 1), None)
  rule.select(
    listing: listing,
    on: civil(2024, 6, 1),
    security_type: rule.Equity,
    market_status: rule.Suspended,
    from: [normal],
  )
  |> should.equal(Error(rule.UnknownRule))
}

pub fn official_profiles_are_dated_and_board_exact_test() {
  let assert Ok(main) =
    official.established_equity(
      venue: official.Sse,
      board: official.MainBoard,
      on: civil(2026, 8, 5),
    )
  main
  |> official.daily_price_limit
  |> decimal.to_string
  |> should.equal("0.1")
  main |> official.minimum_buy_quantity |> should.equal(100)
  main |> official.buy_quantity_increment |> should.equal(Some(100))

  let assert Ok(star) =
    official.established_equity(
      venue: official.Sse,
      board: official.StarMarket,
      on: civil(2026, 8, 5),
    )
  star |> official.minimum_buy_quantity |> should.equal(200)
  star |> official.buy_quantity_increment |> should.equal(None)

  official.established_equity(
    venue: official.Bse,
    board: official.MainBoard,
    on: civil(2026, 8, 5),
  )
  |> should.equal(Error(official.InvalidVenueBoard))
  official.established_equity(
    venue: official.Szse,
    board: official.ChiNext,
    on: civil(2026, 7, 5),
  )
  |> should.equal(Error(official.OutsideReviewedInterval))
}

fn rule_record(
  listing: identity.Listing,
  status: rule.MarketStatus,
  lot: Int,
  start: time.Date,
  end: Option(time.Date),
) -> rule.Rule {
  let assert Ok(value) =
    rule.new(
      listing: listing,
      effective: interval(start, end),
      security_type: rule.Equity,
      market_status: status,
      tick_size: exact("0.01"),
      buy_lot: lot,
      sell_lot: 1,
      price_limit: market_rule.ProviderPublishedOnly,
      settlement: market_rule.BusinessDays(1),
      eligibility: ["synthetic_only"],
      source: source_ref(),
      evidence_id: None,
    )
  value
}

fn mainland_listing(board: identity.Board) -> identity.Listing {
  let assert Ok(instrument_id) = identifier.instrument_id("cn-synthetic")
  let assert Ok(cny) = currency.from_code("CNY")
  let venue = case board {
    identity.SseMainBoard | identity.StarMarket -> identity.Sse
    identity.SzseMainBoard | identity.ChiNext -> identity.Szse
    identity.BeijingMarket -> identity.Bse
  }
  let assert Ok(value) =
    identity.new(
      instrument_id: instrument_id,
      code: "000001",
      venue: venue,
      board: board,
      share_class: identity.AShare,
      currency: cny,
      status: instrument.Active,
    )
  value
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new("synthetic-cn-rules", "fixture/cn-rules", source.Synthetic)
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

fn exact(value: String) -> decimal.Decimal {
  let assert Ok(parsed) = decimal.parse(value)
  parsed
}
