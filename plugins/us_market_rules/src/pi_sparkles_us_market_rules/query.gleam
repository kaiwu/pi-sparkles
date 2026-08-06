import finance_core/decimal
import finance_core/time.{type Date}
import finance_us_rules/official
import gleam/result

pub type QueryError {
  InvalidVenue
  InvalidPrice(decimal.ParseError)
  InvalidProfile(official.ProfileError)
}

pub fn venue_from_name(value: String) -> Result(official.Venue, QueryError) {
  case value {
    "nyse" -> Ok(official.Nyse)
    "nasdaq" -> Ok(official.Nasdaq)
    _ -> Error(InvalidVenue)
  }
}

pub fn run(
  venue venue_value: official.Venue,
  instrument_id instrument_id_value: String,
  symbol symbol_value: String,
  currency currency_value: String,
  security_class security_class_value: String,
  market_status market_status_value: String,
  regime regime_value: String,
  on date: Date,
  nominal_price price_text: String,
) -> Result(official.Profile, QueryError) {
  use price <- result.try(
    decimal.parse(price_text) |> result.map_error(InvalidPrice),
  )
  official.regular_displayed_nms_quote(
    venue: venue_value,
    instrument_id: instrument_id_value,
    symbol: symbol_value,
    currency: currency_value,
    security_class: security_class_value,
    market_status: market_status_value,
    regime: regime_value,
    on: date,
    nominal_price: price,
  )
  |> result.map_error(InvalidProfile)
}
