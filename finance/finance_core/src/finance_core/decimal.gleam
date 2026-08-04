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
    left_digits <> string.repeat("0", times: common_scale - left_scale)
  let right_scaled =
    right_digits <> string.repeat("0", times: common_scale - right_scale)
  case int.compare(string.length(left_scaled), string.length(right_scaled)) {
    Eq -> string.compare(left_scaled, right_scaled)
    order -> order
  }
}

fn order_negate(order: Order) -> Order {
  case order {
    Lt -> Gt
    Eq -> Eq
    Gt -> Lt
  }
}
