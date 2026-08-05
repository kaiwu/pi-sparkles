import finance_core
import finance_core/adjustment
import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/market
import finance_core/money
import finance_core/observation
import finance_core/observation_json
import finance_core/source
import finance_core/time
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_core.status()
  |> should.equal(finance_core.Experimental)
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
  decimal.compare(parsed_decimal("0.5"), decimal.zero())
  |> should.equal(order.Gt)
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

pub fn decimal_arithmetic_stays_exact_beyond_javascript_integer_range_test() {
  decimal.add(parsed_decimal("9007199254740993.01"), parsed_decimal("0.99"))
  |> decimal.to_string
  |> should.equal("9007199254740994")
  decimal.subtract(parsed_decimal("1.25"), parsed_decimal("2.5"))
  |> decimal.to_string
  |> should.equal("-1.25")
  decimal.multiply(
    parsed_decimal("-12345678901234567890.12"),
    parsed_decimal("3"),
  )
  |> decimal.to_string
  |> should.equal("-37037036703703703670.36")
}

pub fn decimal_arithmetic_laws_hold_for_canonical_values_test() {
  let a = parsed_decimal("123.45")
  let b = parsed_decimal("-7.5")
  let c = parsed_decimal("0.125")

  decimal.add(a, b)
  |> should.equal(decimal.add(b, a))
  decimal.add(decimal.add(a, b), c)
  |> should.equal(decimal.add(a, decimal.add(b, c)))
  decimal.multiply(a, decimal.add(b, c))
  |> should.equal(decimal.add(decimal.multiply(a, b), decimal.multiply(a, c)))
  decimal.subtract(a, a)
  |> should.equal(decimal.zero())
}

pub fn decimal_integer_power_is_exact_and_domain_checked_test() {
  decimal.power(parsed_decimal("1.25"), 3)
  |> should.equal(Ok(parsed_decimal("1.953125")))
  decimal.power(parsed_decimal("9"), 0)
  |> should.equal(Ok(parsed_decimal("1")))
  decimal.power(parsed_decimal("2"), -1)
  |> should.equal(Error(decimal.NegativeExponent))
}

pub fn decimal_quantization_has_explicit_rounding_test() {
  decimal.quantize(
    parsed_decimal("1.245"),
    scale: 2,
    rounding: decimal.HalfEven,
  )
  |> should.equal(Ok(parsed_decimal("1.24")))
  decimal.quantize(
    parsed_decimal("1.255"),
    scale: 2,
    rounding: decimal.HalfEven,
  )
  |> should.equal(Ok(parsed_decimal("1.26")))
  decimal.quantize(
    parsed_decimal("-1.251"),
    scale: 2,
    rounding: decimal.AwayFromZero,
  )
  |> should.equal(Ok(parsed_decimal("-1.26")))
  decimal.quantize(
    parsed_decimal("-1.251"),
    scale: 2,
    rounding: decimal.TowardZero,
  )
  |> should.equal(Ok(parsed_decimal("-1.25")))
  decimal.quantize(parsed_decimal("9.999"), scale: 2, rounding: decimal.HalfUp)
  |> should.equal(Ok(parsed_decimal("10")))
  decimal.quantize(parsed_decimal("1"), scale: -1, rounding: decimal.HalfEven)
  |> should.equal(Error(decimal.NegativeScale))
}

pub fn decimal_arithmetic_matches_exhaustive_small_integer_model_test() {
  check_integer_range(-20, 20)
}

pub fn decimal_division_has_explicit_precision_and_rounding_test() {
  decimal.divide(
    parsed_decimal("1"),
    by: parsed_decimal("8"),
    scale: 3,
    rounding: decimal.HalfEven,
  )
  |> should.equal(Ok(parsed_decimal("0.125")))
  decimal.divide(
    parsed_decimal("2"),
    by: parsed_decimal("3"),
    scale: 4,
    rounding: decimal.HalfUp,
  )
  |> should.equal(Ok(parsed_decimal("0.6667")))
  decimal.divide(
    parsed_decimal("5"),
    by: parsed_decimal("2"),
    scale: 0,
    rounding: decimal.HalfEven,
  )
  |> should.equal(Ok(parsed_decimal("2")))
  decimal.divide(
    parsed_decimal("7"),
    by: parsed_decimal("2"),
    scale: 0,
    rounding: decimal.HalfEven,
  )
  |> should.equal(Ok(parsed_decimal("4")))
  decimal.divide(
    parsed_decimal("-10"),
    by: parsed_decimal("4"),
    scale: 2,
    rounding: decimal.TowardZero,
  )
  |> should.equal(Ok(parsed_decimal("-2.5")))
}

pub fn decimal_division_stays_exact_for_large_coefficients_test() {
  let numerator = parsed_decimal("90071992547409931234567890")
  let denominator = parsed_decimal("10")
  let assert Ok(result) =
    decimal.divide(
      numerator,
      by: denominator,
      scale: 1,
      rounding: decimal.HalfEven,
    )

  decimal.to_string(result)
  |> should.equal("9007199254740993123456789")
  decimal.multiply(result, denominator)
  |> should.equal(numerator)
}

pub fn decimal_division_rejects_invalid_domain_test() {
  decimal.divide(
    parsed_decimal("1"),
    by: decimal.zero(),
    scale: 2,
    rounding: decimal.HalfEven,
  )
  |> should.equal(Error(decimal.DivisionByZero))
  decimal.divide(
    parsed_decimal("1"),
    by: parsed_decimal("2"),
    scale: -1,
    rounding: decimal.HalfEven,
  )
  |> should.equal(Error(decimal.NegativeResultScale))
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
  let assert Ok(timezone) = time.timezone("America/New_York")
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
      timezone: Some(timezone),
      source: source,
      evidence_id: Some("evidence-1"),
      freshness: observation.Fresh(maximum_age),
      entitlement: observation.Delayed(maximum_age),
      quality: observation.Reported,
      unit: Some(market.Scalar),
      adjustment: Some(adjustment.Raw),
      session: Some(market.Regular),
    )
  let mapped = observation.map(original, fn(value) { value * 2 })

  mapped.value
  |> should.equal(42)
  mapped.source
  |> should.equal(source)
  mapped.evidence_id
  |> should.equal(Some("evidence-1"))
  mapped.timezone
  |> should.equal(Some(timezone))
  original.evidence_id
  |> should.not_equal(None)
  observation.map(original, fn(value) { value })
  |> should.equal(original)
  observation.map(observation.map(original, fn(value) { value * 2 }), fn(value) {
    value + 1
  })
  |> should.equal(observation.map(original, fn(value) { value * 2 + 1 }))
}

pub fn source_references_reject_common_credential_shapes_test() {
  source.new(
    provider: "provider",
    reference: "quotes?symbol=AAPL&api_key=secret",
    kind: source.LicensedVendor,
  )
  |> should.equal(Error(source.UnsafeReference))
}

pub fn money_arithmetic_is_currency_safe_test() {
  let assert Ok(usd) = currency.from_code("USD")
  let assert Ok(cny) = currency.from_code("CNY")
  let left = money.new(parsed_decimal("12.25"), usd)
  let right = money.new(parsed_decimal("0.75"), usd)

  money.add(left, right)
  |> should.equal(Ok(money.new(parsed_decimal("13"), usd)))
  money.subtract(left, right)
  |> should.equal(Ok(money.new(parsed_decimal("11.5"), usd)))
  money.compare(left, right)
  |> should.equal(Ok(order.Gt))
  money.add(left, money.new(parsed_decimal("1"), cny))
  |> should.equal(Error(money.CurrencyMismatch("USD", "CNY")))
}

pub fn identity_resolution_never_guesses_ambiguous_symbols_test() {
  identifier.resolve(["AAPL@XNAS", "AAPL@XMEX"])
  |> should.equal(identifier.Ambiguous("AAPL@XNAS", "AAPL@XMEX", []))
  identifier.resolve(["0700@XHKG"])
  |> should.equal(identifier.Unique("0700@XHKG"))
  identifier.resolve([])
  |> should.equal(identifier.NoMatch)
}

pub fn civil_time_and_timezone_values_are_validated_test() {
  let assert Ok(noon) = time.time_of_day(12, 30)
  let assert Ok(zone) = time.timezone("Asia/Shanghai")

  time.time_of_day_parts(noon)
  |> should.equal(#(12, 30))
  time.timezone_name(zone)
  |> should.equal("Asia/Shanghai")
  time.time_of_day(24, 0)
  |> should.equal(Error(time.InvalidHour))
  time.timezone("CST")
  |> should.equal(Error(time.InvalidTimezone))
}

pub fn observation_json_is_canonical_versioned_and_round_trips_test() {
  let assert Ok(as_of) = time.instant(1_700_000_000_000)
  let assert Ok(retrieved_at) = time.instant(1_700_000_001_000)
  let assert Ok(age) = time.duration(1000)
  let assert Ok(maximum_age) = time.duration(500)
  let assert Ok(source_ref) =
    source.new(
      provider: "licensed-provider",
      reference: "quotes/0700",
      kind: source.LicensedVendor,
    )
  let assert Ok(hkd) = currency.from_code("HKD")
  let assert Ok(provider_adjustment) =
    adjustment.provider_adjusted(
      provider: "licensed-provider",
      basis: "split-and-cash-dividend-v2",
    )
  let assert Ok(session) = market.other_session("midday-reopen-auction")
  let assert Ok(timezone) = time.timezone("Asia/Hong_Kong")
  let original =
    observation.Observation(
      value: "321.40",
      as_of: as_of,
      retrieved_at: retrieved_at,
      timezone: Some(timezone),
      source: source_ref,
      evidence_id: Some("sha256:evidence"),
      freshness: observation.Stale(age, maximum_age),
      entitlement: observation.Delayed(maximum_age),
      quality: observation.Missing(observation.NotReported),
      unit: Some(market.CurrencyPerShare(hkd)),
      adjustment: Some(provider_adjustment),
      session: Some(session),
    )
  let encoded = observation_json.encode(original, json.string)
  let assert Ok(decoded) = observation_json.decode(encoded, decode.string)

  decoded
  |> should.equal(original)
  observation_json.encode(decoded, json.string)
  |> should.equal(encoded)
  encoded
  |> string_starts_with("{\"schemaVersion\":2,\"value\":\"321.40\"")
}

pub fn observation_json_decodes_v1_without_inventing_timezone_test() {
  let version_one =
    canonical_minimal_observation_json()
    |> replace_once("\"schemaVersion\":2", "\"schemaVersion\":1")
    |> replace_once(",\"timezone\":null", "")
  let assert Ok(decoded) = observation_json.decode(version_one, decode.int)

  decoded.timezone
  |> should.equal(None)
}

pub fn observation_json_rejects_unknown_versions_and_enum_values_test() {
  let valid = canonical_minimal_observation_json()
  valid
  |> observation_json.decode(decode.int)
  |> should.be_ok
  valid
  |> replace_once("\"schemaVersion\":2", "\"schemaVersion\":3")
  |> observation_json.decode(decode.int)
  |> should.be_error
  valid
  |> replace_once("\"tag\":\"reported\"", "\"tag\":\"invented\"")
  |> observation_json.decode(decode.int)
  |> should.be_error
}

fn canonical_minimal_observation_json() -> String {
  let assert Ok(instant) = time.instant(0)
  let assert Ok(source_ref) =
    source.new(
      provider: "synthetic",
      reference: "fixture",
      kind: source.Synthetic,
    )
  observation.Observation(
    value: 1,
    as_of: instant,
    retrieved_at: instant,
    timezone: None,
    source: source_ref,
    evidence_id: None,
    freshness: observation.UnknownFreshness,
    entitlement: observation.UnknownEntitlement,
    quality: observation.Reported,
    unit: None,
    adjustment: None,
    session: None,
  )
  |> observation_json.encode(json.int)
}

fn string_starts_with(value: String, prefix: String) -> Nil {
  value
  |> string.starts_with(prefix)
  |> should.be_true
}

fn replace_once(value: String, pattern: String, replacement: String) -> String {
  string.replace(value, pattern, replacement)
}

fn parsed_decimal(value: String) -> decimal.Decimal {
  let assert Ok(value) = decimal.parse(value)
  value
}

fn check_integer_range(value: Int, maximum: Int) -> Nil {
  case value > maximum {
    True -> Nil
    False -> {
      check_integer_pairs(value, -20, maximum)
      check_integer_range(value + 1, maximum)
    }
  }
}

fn check_integer_pairs(left: Int, right: Int, maximum: Int) -> Nil {
  case right > maximum {
    True -> Nil
    False -> {
      let left_decimal = left |> int.to_string |> parsed_decimal
      let right_decimal = right |> int.to_string |> parsed_decimal

      decimal.add(left_decimal, right_decimal)
      |> decimal.to_string
      |> should.equal(int.to_string(left + right))
      decimal.subtract(left_decimal, right_decimal)
      |> decimal.to_string
      |> should.equal(int.to_string(left - right))
      decimal.multiply(left_decimal, right_decimal)
      |> decimal.to_string
      |> should.equal(int.to_string(left * right))
      check_integer_pairs(left, right + 1, maximum)
    }
  }
}
