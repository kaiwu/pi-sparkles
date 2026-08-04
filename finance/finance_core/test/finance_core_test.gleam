import finance_core
import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/money
import finance_core/observation
import finance_core/source
import finance_core/time
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_implementing_test() {
  finance_core.status()
  |> should.equal(finance_core.Implementing)
}

pub fn decimal_normalization_is_exact_test() {
  let assert Ok(value) = decimal.parse("-000123.4500")

  decimal.to_string(value)
  |> should.equal("-123.45")
  decimal.coefficient(value)
  |> should.equal("-12345")
  decimal.scale(value)
  |> should.equal(2)
}

pub fn decimal_zero_has_one_canonical_form_test() {
  let assert Ok(value) = decimal.parse("-000.000")

  decimal.to_string(value)
  |> should.equal("0")
}

pub fn decimal_comparison_aligns_scale_without_float_test() {
  let assert Ok(left) = decimal.parse("9007199254740993.01")
  let assert Ok(equal) = decimal.parse("9007199254740993.0100")
  let assert Ok(right) = decimal.parse("9007199254740993.02")

  decimal.compare(left, equal)
  |> should.equal(order.Eq)
  decimal.compare(left, right)
  |> should.equal(order.Lt)
}

pub fn decimal_rejects_ambiguous_input_test() {
  decimal.parse(" 1.0")
  |> should.equal(Error(decimal.SurroundingWhitespace))
  decimal.parse("1e3")
  |> should.equal(Error(decimal.InvalidDigit))
}

pub fn decimal_canonical_encoding_is_idempotent_test() {
  [
    "0",
    "1",
    "-1",
    "0.00001",
    "123456789012345678901234567890.123456789",
  ]
  |> list.each(fn(input) {
    let assert Ok(first) = decimal.parse(input)
    let canonical = decimal.to_string(first)
    let assert Ok(second) = decimal.parse(canonical)

    decimal.to_string(second)
    |> should.equal(canonical)
    decimal.compare(first, second)
    |> should.equal(order.Eq)
  })
}

pub fn date_validation_handles_leap_years_test() {
  time.date(2024, 2, 29)
  |> should.be_ok
  time.date(2023, 2, 29)
  |> should.equal(Error(time.InvalidDate))
}

pub fn identifiers_are_normalized_but_not_guessed_test() {
  let assert Ok(symbol) = identifier.symbol("aapl")
  let assert Ok(mic) = identifier.mic("xnas")

  identifier.symbol_value(symbol)
  |> should.equal("AAPL")
  identifier.mic_value(mic)
  |> should.equal("XNAS")
  identifier.mic("NASDAQ")
  |> should.equal(Error(identifier.InvalidMic))
}

pub fn money_requires_matching_currency_test() {
  let assert Ok(amount) = decimal.parse("12.34")
  let assert Ok(usd) = currency.from_code("usd")
  let assert Ok(cny) = currency.from_code("CNY")
  let dollars = money.new(amount, usd)

  money.to_string(dollars)
  |> should.equal("USD 12.34")
  money.same_currency(dollars, money.new(amount, cny))
  |> should.equal(Error(money.CurrencyMismatch("USD", "CNY")))
}

pub fn observation_map_preserves_metadata_test() {
  let assert Ok(as_of) = time.instant(1_700_000_000_000)
  let assert Ok(retrieved_at) = time.instant(1_700_000_001_000)
  let assert Ok(maximum_age) = time.duration(5000)
  let assert Ok(source) =
    source.new(
      provider: "test-provider",
      reference: "quote/AAPL",
      kind: source.Synthetic,
    )
  let original =
    observation.Observation(
      value: 21,
      as_of: as_of,
      retrieved_at: retrieved_at,
      source: source,
      evidence_id: Some("evidence-1"),
      freshness: observation.Fresh(maximum_age),
      entitlement: observation.Delayed(maximum_age),
      quality: observation.Reported,
    )
  let mapped = observation.map(original, fn(value) { value * 2 })

  mapped.value
  |> should.equal(42)
  mapped.source
  |> should.equal(source)
  mapped.evidence_id
  |> should.equal(Some("evidence-1"))
  original.evidence_id
  |> should.not_equal(None)
  observation.map(original, fn(value) { value })
  |> should.equal(original)
  observation.map(observation.map(original, fn(value) { value * 2 }), fn(value) {
    value + 1
  })
  |> should.equal(observation.map(original, fn(value) { value * 2 + 1 }))
}
