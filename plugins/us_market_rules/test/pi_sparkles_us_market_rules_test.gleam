import finance_core/decimal
import finance_core/time
import finance_us_rules/official
import gleeunit
import gleeunit/should
import pi_sparkles_us_market_rules/query

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_venue_identity_and_regime_are_required_test() {
  query.venue_from_name("NYSE") |> should.equal(Error(query.InvalidVenue))
  let assert Ok(date) = time.date(2026, 8, 6)
  let assert Ok(value) =
    query.run(
      venue: official.Nyse,
      instrument_id: "figi:BBG000B9XRY4",
      symbol: "AAPL",
      currency: "USD",
      security_class: "nms_stock",
      market_status: "normal",
      regime: "regular_displayed_quote",
      on: date,
      nominal_price: "182.375",
    )
  value
  |> official.minimum_price_increment
  |> decimal.to_string
  |> should.equal("0.01")

  query.run(
    venue: official.Nyse,
    instrument_id: "figi:BBG000B9XRY4",
    symbol: "AAPL",
    currency: "USD",
    security_class: "nms_stock",
    market_status: "normal",
    regime: "customer_limit_order",
    on: date,
    nominal_price: "182.375",
  )
  |> should.be_error
}

pub fn sub_dollar_nasdaq_increment_is_exact_test() {
  let assert Ok(date) = time.date(2026, 8, 6)
  let assert Ok(value) =
    query.run(
      venue: official.Nasdaq,
      instrument_id: "figi:BBG000TEST01",
      symbol: "TEST",
      currency: "USD",
      security_class: "nms_stock",
      market_status: "normal",
      regime: "regular_displayed_quote",
      on: date,
      nominal_price: "0.123456",
    )
  value
  |> official.minimum_price_increment
  |> decimal.to_string
  |> should.equal("0.0001")
}
