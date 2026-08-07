import finance_core/decimal.{type Decimal}
import gleam/int
import gleam/order.{Eq, Gt, Lt}
import gleam/string

pub fn fixed(value: Decimal, scale: Int) -> String {
  let text = decimal.to_string(value)
  case scale <= 0 {
    True -> text
    False ->
      case string.split(text, on: ".") {
        [whole] -> whole <> "." <> string.repeat("0", times: scale)
        [whole, fraction] ->
          whole
          <> "."
          <> fraction
          <> string.repeat(
            "0",
            times: int.max(scale - string.length(fraction), 0),
          )
        _ -> text
      }
  }
}

pub fn nonnegative_floor_int(value: Decimal) -> Int {
  case decimal.compare(value, decimal.zero()) {
    Lt | Eq -> 0
    Gt -> {
      let assert Ok(integer) =
        decimal.quantize(value, scale: 0, rounding: decimal.TowardZero)
      let assert Ok(result) = int.parse(decimal.to_string(integer))
      result
    }
  }
}

pub fn minimum(left: Decimal, right: Decimal) -> Decimal {
  case decimal.compare(left, right) {
    Gt -> right
    Eq | Lt -> left
  }
}

pub fn nonnegative(value: Decimal) -> Decimal {
  case decimal.compare(value, decimal.zero()) {
    Lt -> decimal.zero()
    Eq | Gt -> value
  }
}
