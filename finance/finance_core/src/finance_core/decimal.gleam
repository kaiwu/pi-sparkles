import gleam/int
import gleam/list
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/string

pub opaque type Decimal {
  Decimal(sign: Sign, digits: String, scale: Int)
}

pub type Sign {
  Positive
  Negative
}

pub type ParseError {
  Empty
  SurroundingWhitespace
  InvalidFormat
  InvalidDigit
}

pub type RoundingMode {
  TowardZero
  AwayFromZero
  HalfUp
  HalfEven
}

pub type QuantizeError {
  NegativeScale
}

pub type ArithmeticError {
  DivisionByZero
  NegativeResultScale
}

pub type PowerError {
  NegativeExponent
}

pub fn power(decimal: Decimal, exponent: Int) -> Result(Decimal, PowerError) {
  case exponent < 0 {
    True -> Error(NegativeExponent)
    False -> Ok(power_loop(decimal, exponent, parse_one()))
  }
}

fn power_loop(base: Decimal, exponent: Int, result: Decimal) -> Decimal {
  case exponent {
    0 -> result
    _ -> {
      let next_result = case exponent % 2 == 1 {
        True -> multiply(result, base)
        False -> result
      }
      power_loop(multiply(base, base), exponent / 2, next_result)
    }
  }
}

fn parse_one() -> Decimal {
  let assert Ok(one) = parse("1")
  one
}

pub fn zero() -> Decimal {
  Decimal(Positive, "0", 0)
}

pub fn parse(input: String) -> Result(Decimal, ParseError) {
  case input {
    "" -> Error(Empty)
    _ ->
      case string.trim(input) == input {
        False -> Error(SurroundingWhitespace)
        True -> {
          let #(sign, unsigned) = case input {
            "-" <> rest -> #(Negative, rest)
            "+" <> rest -> #(Positive, rest)
            _ -> #(Positive, input)
          }
          parse_unsigned(unsigned, sign)
        }
      }
  }
}

pub fn to_string(decimal: Decimal) -> String {
  let Decimal(sign, digits, scale) = decimal
  let unsigned = case scale {
    0 -> digits
    _ -> {
      let digits_length = string.length(digits)
      case digits_length > scale {
        True ->
          string.slice(digits, at_index: 0, length: digits_length - scale)
          <> "."
          <> string.slice(
            digits,
            at_index: digits_length - scale,
            length: scale,
          )
        False ->
          "0." <> string.repeat("0", times: scale - digits_length) <> digits
      }
    }
  }
  case sign, digits {
    Negative, "0" -> unsigned
    Negative, _ -> "-" <> unsigned
    Positive, _ -> unsigned
  }
}

pub fn compare(left: Decimal, right: Decimal) -> Order {
  let Decimal(left_sign, _, _) = left
  let Decimal(right_sign, _, _) = right
  case left_sign, right_sign {
    Positive, Negative -> Gt
    Negative, Positive -> Lt
    Positive, Positive -> compare_magnitude(left, right)
    Negative, Negative -> compare_magnitude(left, right) |> order_negate
  }
}

pub fn negate(decimal: Decimal) -> Decimal {
  let Decimal(sign, digits, scale) = decimal
  case sign, digits {
    _, "0" -> zero()
    Positive, _ -> Decimal(Negative, digits, scale)
    Negative, _ -> Decimal(Positive, digits, scale)
  }
}

pub fn add(left: Decimal, right: Decimal) -> Decimal {
  let Decimal(left_sign, left_digits, left_scale) = left
  let Decimal(right_sign, right_digits, right_scale) = right
  let common_scale = int.max(left_scale, right_scale)
  let left_scaled =
    left_digits <> string.repeat("0", times: common_scale - left_scale)
  let right_scaled =
    right_digits <> string.repeat("0", times: common_scale - right_scale)
  case left_sign, right_sign {
    same, other if same == other ->
      from_scaled(same, add_unsigned(left_scaled, right_scaled), common_scale)
    _, _ ->
      case compare_unsigned(left_scaled, right_scaled) {
        Eq -> zero()
        Gt ->
          from_scaled(
            left_sign,
            subtract_unsigned(left_scaled, right_scaled),
            common_scale,
          )
        Lt ->
          from_scaled(
            right_sign,
            subtract_unsigned(right_scaled, left_scaled),
            common_scale,
          )
      }
  }
}

pub fn subtract(left: Decimal, right: Decimal) -> Decimal {
  add(left, negate(right))
}

pub fn multiply(left: Decimal, right: Decimal) -> Decimal {
  let Decimal(left_sign, left_digits, left_scale) = left
  let Decimal(right_sign, right_digits, right_scale) = right
  let sign = case left_sign == right_sign {
    True -> Positive
    False -> Negative
  }
  from_scaled(
    sign,
    multiply_unsigned(left_digits, right_digits),
    left_scale + right_scale,
  )
}

pub fn quantize(
  decimal: Decimal,
  scale target_scale: Int,
  rounding rounding: RoundingMode,
) -> Result(Decimal, QuantizeError) {
  let Decimal(sign, digits, current_scale) = decimal
  case target_scale < 0 {
    True -> Error(NegativeScale)
    False if target_scale >= current_scale -> Ok(decimal)
    False -> {
      let dropped_count = current_scale - target_scale
      let retained_count = int.max(string.length(digits) - dropped_count, 0)
      let retained = string.slice(digits, at_index: 0, length: retained_count)
      let removed =
        string.slice(digits, at_index: retained_count, length: dropped_count)
      let magnitude = case should_increment(retained, removed, rounding) {
        True -> increment_unsigned(retained)
        False ->
          case retained {
            "" -> "0"
            _ -> retained
          }
      }
      Ok(from_scaled(sign, magnitude, target_scale))
    }
  }
}

pub fn divide(
  dividend: Decimal,
  by divisor: Decimal,
  scale result_scale: Int,
  rounding rounding: RoundingMode,
) -> Result(Decimal, ArithmeticError) {
  let Decimal(dividend_sign, dividend_digits, dividend_scale) = dividend
  let Decimal(divisor_sign, divisor_digits, divisor_scale) = divisor
  case divisor_digits, result_scale < 0 {
    "0", _ -> Error(DivisionByZero)
    _, True -> Error(NegativeResultScale)
    _, False -> {
      let exponent = divisor_scale + result_scale - dividend_scale
      let #(numerator, denominator) = case exponent >= 0 {
        True -> #(
          dividend_digits <> string.repeat("0", times: exponent),
          divisor_digits,
        )
        False -> #(
          dividend_digits,
          divisor_digits <> string.repeat("0", times: 0 - exponent),
        )
      }
      let #(quotient, remainder) = divide_unsigned(numerator, denominator)
      let rounded = case
        should_increment_division(quotient, remainder, denominator, rounding)
      {
        True -> increment_unsigned(quotient)
        False -> quotient
      }
      let sign = case dividend_sign == divisor_sign {
        True -> Positive
        False -> Negative
      }
      Ok(from_scaled(sign, rounded, result_scale))
    }
  }
}

pub fn scale(decimal: Decimal) -> Int {
  let Decimal(_, _, scale) = decimal
  scale
}

pub fn coefficient(decimal: Decimal) -> String {
  let Decimal(sign, digits, _) = decimal
  case sign, digits {
    Negative, "0" -> "0"
    Negative, _ -> "-" <> digits
    Positive, _ -> digits
  }
}

fn parse_unsigned(unsigned: String, sign: Sign) -> Result(Decimal, ParseError) {
  case string.split(unsigned, on: ".") {
    [""] -> Error(Empty)
    [whole] -> normalize(sign, whole, "")
    [whole, fraction] if whole != "" && fraction != "" ->
      normalize(sign, whole, fraction)
    _ -> Error(InvalidFormat)
  }
}

fn normalize(
  sign: Sign,
  whole: String,
  fraction: String,
) -> Result(Decimal, ParseError) {
  let all_digits = whole <> fraction
  case all_digits |> string.to_graphemes |> list.all(is_digit) {
    False -> Error(InvalidDigit)
    True -> {
      let fraction_digits =
        fraction
        |> string.to_graphemes
        |> list.reverse
        |> drop_zeroes
        |> list.reverse
      let scale = list.length(fraction_digits)
      let digits =
        { whole <> string.concat(fraction_digits) }
        |> string.to_graphemes
        |> drop_zeroes
        |> string.concat
      case digits {
        "" -> Ok(zero())
        _ -> Ok(Decimal(sign, digits, scale))
      }
    }
  }
}

fn drop_zeroes(digits: List(String)) -> List(String) {
  case digits {
    ["0", ..rest] -> drop_zeroes(rest)
    _ -> digits
  }
}

fn is_digit(grapheme: String) -> Bool {
  string.length(grapheme) == 1 && string.contains("0123456789", grapheme)
}

fn compare_magnitude(left: Decimal, right: Decimal) -> Order {
  let Decimal(_, left_digits, left_scale) = left
  let Decimal(_, right_digits, right_scale) = right
  let common_scale = int.max(left_scale, right_scale)
  let left_scaled =
    normalize_unsigned(
      left_digits <> string.repeat("0", times: common_scale - left_scale),
    )
  let right_scaled =
    normalize_unsigned(
      right_digits <> string.repeat("0", times: common_scale - right_scale),
    )
  case int.compare(string.length(left_scaled), string.length(right_scaled)) {
    Eq -> string.compare(left_scaled, right_scaled)
    order -> order
  }
}

fn from_scaled(sign: Sign, digits: String, scale: Int) -> Decimal {
  let digits_length = string.length(digits)
  let #(whole, fraction) = case scale {
    0 -> #(digits, "")
    _ if digits_length > scale -> #(
      string.slice(digits, at_index: 0, length: digits_length - scale),
      string.slice(digits, at_index: digits_length - scale, length: scale),
    )
    _ -> #("0", string.repeat("0", times: scale - digits_length) <> digits)
  }
  let assert Ok(decimal) = normalize(sign, whole, fraction)
  decimal
}

fn compare_unsigned(left: String, right: String) -> Order {
  let width = int.max(string.length(left), string.length(right))
  let left = string.pad_start(left, to: width, with: "0")
  let right = string.pad_start(right, to: width, with: "0")
  string.compare(left, right)
}

@external(javascript, "./decimal_ffi.mjs", "add_unsigned")
fn add_unsigned(left: String, right: String) -> String

@external(javascript, "./decimal_ffi.mjs", "subtract_unsigned")
fn subtract_unsigned(left: String, right: String) -> String

@external(javascript, "./decimal_ffi.mjs", "multiply_unsigned")
fn multiply_unsigned(left: String, right: String) -> String

fn multiply_by_digit(value: String, multiplier: Int) -> String {
  multiply_unsigned(value, int.to_string(multiplier))
}

fn increment_unsigned(value: String) -> String {
  add_unsigned(non_empty_zero(value), "1")
}

@external(javascript, "./decimal_ffi.mjs", "divide_unsigned")
fn divide_unsigned(numerator: String, denominator: String) -> #(String, String)

fn should_increment_division(
  quotient: String,
  remainder: String,
  denominator: String,
  rounding: RoundingMode,
) -> Bool {
  case remainder {
    "0" -> False
    _ ->
      case rounding {
        TowardZero -> False
        AwayFromZero -> True
        HalfUp ->
          compare_unsigned(multiply_by_digit(remainder, 2), denominator) != Lt
        HalfEven ->
          case compare_unsigned(multiply_by_digit(remainder, 2), denominator) {
            Lt -> False
            Gt -> True
            Eq -> last_digit(non_empty_zero(quotient)) % 2 == 1
          }
      }
  }
}

fn normalize_unsigned(value: String) -> String {
  value
  |> string.to_graphemes
  |> drop_zeroes
  |> string.concat
  |> non_empty_zero
}

fn should_increment(
  retained: String,
  removed: String,
  rounding: RoundingMode,
) -> Bool {
  let has_removed_value =
    removed |> string.to_graphemes |> list.any(fn(digit) { digit != "0" })
  case rounding, has_removed_value {
    TowardZero, _ | _, False -> False
    AwayFromZero, True -> True
    HalfUp, True -> first_digit(removed) >= 5
    HalfEven, True -> {
      let first = first_digit(removed)
      first > 5
      || {
        first == 5
        && {
          removed_has_nonzero_tail(removed)
          || { last_digit(non_empty_zero(retained)) % 2 == 1 }
        }
      }
    }
  }
}

fn removed_has_nonzero_tail(value: String) -> Bool {
  value
  |> string.drop_start(up_to: 1)
  |> string.to_graphemes
  |> list.any(fn(digit) { digit != "0" })
}

fn first_digit(value: String) -> Int {
  value |> string.slice(at_index: 0, length: 1) |> digit_value
}

fn last_digit(value: String) -> Int {
  value
  |> string.slice(at_index: string.length(value) - 1, length: 1)
  |> digit_value
}

fn digit_value(value: String) -> Int {
  let assert Ok(value) = int.parse(value)
  value
}

fn non_empty_zero(value: String) -> String {
  case value {
    "" -> "0"
    _ -> value
  }
}

fn order_negate(order: Order) -> Order {
  case order {
    Lt -> Gt
    Eq -> Eq
    Gt -> Lt
  }
}
