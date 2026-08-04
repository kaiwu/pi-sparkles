import gleam/list
import gleam/string

pub opaque type Currency {
  Currency(code: String)
}

pub type CurrencyError {
  InvalidCurrency
}

pub fn from_code(code: String) -> Result(Currency, CurrencyError) {
  let normalized = string.uppercase(code)
  case
    string.length(normalized) == 3
    && {
      normalized
      |> string.to_graphemes
      |> list.all(fn(character) {
        string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", character)
      })
    }
  {
    True -> Ok(Currency(normalized))
    False -> Error(InvalidCurrency)
  }
}

pub fn code(currency: Currency) -> String {
  let Currency(code) = currency
  code
}
