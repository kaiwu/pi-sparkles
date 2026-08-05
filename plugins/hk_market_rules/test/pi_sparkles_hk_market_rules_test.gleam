import finance_core/decimal
import finance_core/time
import finance_hk_rules/official
import gleeunit
import gleeunit/should
import pi_sparkles_hk_market_rules/query

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn scope_and_boundaries_are_explicit_test() {
  let assert Ok(date) = time.date(2026, 8, 5)
  let assert Ok(value) =
    query.run(
      currency: "HKD",
      product_class: "applicable_equity",
      on: date,
      nominal_price: "9.995",
      board_lot: 500,
      board_lot_source: "HKEX issuer profile for 00001",
    )
  value |> official.tick_size |> decimal.to_string |> should.equal("0.005")
  query.run(
    currency: "CNY",
    product_class: "applicable_equity",
    on: date,
    nominal_price: "9.995",
    board_lot: 500,
    board_lot_source: "HKEX issuer profile for 00001",
  )
  |> should.equal(Error(query.InvalidCurrency))
  query.run(
    currency: "HKD",
    product_class: "etp",
    on: date,
    nominal_price: "9.995",
    board_lot: 500,
    board_lot_source: "HKEX issuer profile for 00001",
  )
  |> should.equal(Error(query.InvalidProductClass))
}
