import finance_core/decimal
import finance_core/time.{type Date}
import finance_hk_rules/official
import gleam/result

pub type QueryError {
  InvalidCurrency
  InvalidProductClass
  InvalidPrice(decimal.ParseError)
  InvalidProfile(official.ProfileError)
}

pub fn run(
  currency currency_value: String,
  product_class product_class_value: String,
  on date: Date,
  nominal_price price_text: String,
  board_lot board_lot_value: Int,
  board_lot_source evidence_reference: String,
) -> Result(official.Profile, QueryError) {
  case currency_value, product_class_value {
    "HKD", "applicable_equity" ->
      case decimal.parse(price_text) {
        Error(error) -> Error(InvalidPrice(error))
        Ok(price) ->
          official.applicable_hkd_equity(
            on: date,
            nominal_price: price,
            board_lot: board_lot_value,
            board_lot_source: evidence_reference,
          )
          |> result.map_error(InvalidProfile)
      }
    "HKD", _ -> Error(InvalidProductClass)
    _, _ -> Error(InvalidCurrency)
  }
}
