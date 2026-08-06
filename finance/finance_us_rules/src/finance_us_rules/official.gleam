import finance_core/decimal.{type Decimal}
import finance_core/identifier
import finance_core/source.{type SourceRef}
import finance_core/time.{type Date}
import finance_listing/effective.{type Interval}
import finance_listing/listing.{type Key}
import finance_track
import gleam/list
import gleam/option.{Some}
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string

pub type Venue {
  Nyse
  Nasdaq
}

pub type PriceBand {
  BelowOneDollar
  AtOrAboveOneDollar
}

/// A deliberately narrow rule profile for a regular displayed quotation in a
/// caller-identified, normally traded NMS stock.
///
/// The listing key is retained but remains caller supplied. The profile does
/// not resolve identity or classify the security as an NMS stock.
pub opaque type Profile {
  Profile(
    listing: Key,
    venue: Venue,
    effective: Interval,
    nominal_price: Decimal,
    price_band: PriceBand,
    minimum_price_increment: Decimal,
    exchange_source: SourceRef,
    sec_relief_source: SourceRef,
    clauses: List(String),
    limitations: List(String),
  )
}

pub type ProfileError {
  InvalidInstrumentId
  InvalidSymbol
  InvalidCurrency
  InvalidSecurityClass
  InvalidMarketStatus
  InvalidRegime
  OutsideReviewedInterval
  NonPositivePrice
}

/// Current NYSE/Nasdaq displayed-quotation increment during the SEC's
/// temporary relief from compliance with amended Rule 612.
///
/// The reviewed interval begins with SEC Release 34-105656 and ends the day
/// before the first business day of November 2027.
pub fn regular_displayed_nms_quote(
  venue venue_value: Venue,
  instrument_id instrument_id_value: String,
  symbol symbol_value: String,
  currency currency_value: String,
  security_class security_class_value: String,
  market_status market_status_value: String,
  regime regime_value: String,
  on date: Date,
  nominal_price price: Decimal,
) -> Result(Profile, ProfileError) {
  use listing_key <- result.try(build_listing(
    venue_value,
    instrument_id_value,
    symbol_value,
  ))
  let interval = reviewed_interval()
  case
    currency_value,
    security_class_value,
    market_status_value,
    regime_value,
    effective.contains(interval, date),
    decimal.compare(price, decimal.zero())
  {
    "USD", "nms_stock", "normal", "regular_displayed_quote", True, Gt -> {
      let band = price_band(price)
      Ok(Profile(
        listing: listing_key,
        venue: venue_value,
        effective: interval,
        nominal_price: price,
        price_band: band,
        minimum_price_increment: increment_for(band),
        exchange_source: venue_exchange_source(venue_value),
        sec_relief_source: official_sec_relief_source(),
        clauses: clause_ids(venue_value),
        limitations: limitation_ids(),
      ))
    }
    value, _, _, _, _, _ if value != "USD" -> Error(InvalidCurrency)
    _, value, _, _, _, _ if value != "nms_stock" -> Error(InvalidSecurityClass)
    _, _, value, _, _, _ if value != "normal" -> Error(InvalidMarketStatus)
    _, _, _, value, _, _ if value != "regular_displayed_quote" ->
      Error(InvalidRegime)
    _, _, _, _, False, _ -> Error(OutsideReviewedInterval)
    _, _, _, _, _, _ -> Error(NonPositivePrice)
  }
}

pub fn listing(value: Profile) -> Key {
  value.listing
}

pub fn venue(value: Profile) -> Venue {
  value.venue
}

pub fn effective(value: Profile) -> Interval {
  value.effective
}

pub fn nominal_price(value: Profile) -> Decimal {
  value.nominal_price
}

pub fn selected_price_band(value: Profile) -> PriceBand {
  value.price_band
}

pub fn minimum_price_increment(value: Profile) -> Decimal {
  value.minimum_price_increment
}

pub fn exchange_source(value: Profile) -> SourceRef {
  value.exchange_source
}

pub fn sec_relief_source(value: Profile) -> SourceRef {
  value.sec_relief_source
}

pub fn sources(value: Profile) -> List(SourceRef) {
  [value.exchange_source, value.sec_relief_source]
}

pub fn clauses(value: Profile) -> List(String) {
  value.clauses
}

pub fn limitations(value: Profile) -> List(String) {
  value.limitations
}

pub fn venue_name(value: Venue) -> String {
  case value {
    Nyse -> "nyse"
    Nasdaq -> "nasdaq"
  }
}

pub fn venue_mic_name(value: Venue) -> String {
  case value {
    Nyse -> "XNYS"
    Nasdaq -> "XNAS"
  }
}

pub fn price_band_name(value: PriceBand) -> String {
  case value {
    BelowOneDollar -> "below_1_usd"
    AtOrAboveOneDollar -> "at_or_above_1_usd"
  }
}

fn build_listing(
  venue: Venue,
  instrument_id_value: String,
  symbol_value: String,
) -> Result(Key, ProfileError) {
  use _ <- result.try(validate_instrument_id(instrument_id_value))
  use instrument_id <- result.try(
    identifier.instrument_id(instrument_id_value)
    |> result.map_error(fn(_) { InvalidInstrumentId }),
  )
  use symbol <- result.try(
    identifier.symbol(symbol_value)
    |> result.map_error(fn(_) { InvalidSymbol }),
  )
  case
    identifier.symbol_value(symbol) == symbol_value,
    string.length(symbol_value) <= 32
  {
    True, True -> {
      let assert Ok(mic) = identifier.mic(venue_mic_name(venue))
      Ok(listing.new(finance_track.Us, instrument_id, symbol, mic))
    }
    _, _ -> Error(InvalidSymbol)
  }
}

fn validate_instrument_id(value: String) -> Result(Nil, ProfileError) {
  let valid =
    string.length(value) <= 200
    && string.contains(value, ":")
    && !string.starts_with(value, ":")
    && !string.ends_with(value, ":")
    && {
      value
      |> string.to_graphemes
      |> list.all(fn(character) {
        string.contains(
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-/",
          character,
        )
      })
    }
  case valid {
    True -> Ok(Nil)
    False -> Error(InvalidInstrumentId)
  }
}

fn price_band(value: Decimal) -> PriceBand {
  case decimal.compare(value, exact("1")) {
    Lt -> BelowOneDollar
    _ -> AtOrAboveOneDollar
  }
}

fn increment_for(value: PriceBand) -> Decimal {
  case value {
    BelowOneDollar -> exact("0.0001")
    AtOrAboveOneDollar -> exact("0.01")
  }
}

fn reviewed_interval() -> Interval {
  let assert Ok(start) = time.date(2026, 6, 11)
  let assert Ok(end) = time.date(2027, 10, 31)
  let assert Ok(value) = effective.new(start, Some(end))
  value
}

fn venue_exchange_source(value: Venue) -> SourceRef {
  let #(provider, reference) = case value {
    Nyse -> #(
      "New York Stock Exchange",
      "https://www.nyse.com/publicdocs/nyse/regulation/nyse/NYSE_Rules.pdf",
    )
    Nasdaq -> #(
      "The Nasdaq Stock Market",
      "https://listingcenter.nasdaq.com/rulebook/nasdaq/rules/nasdaq-equity-2",
    )
  }
  let assert Ok(value) = source.new(provider, reference, source.Exchange)
  value
}

fn official_sec_relief_source() -> SourceRef {
  let assert Ok(value) =
    source.new(
      "U.S. Securities and Exchange Commission",
      "https://www.sec.gov/files/rules/exorders/2026/34-105656.pdf",
      source.Regulator,
    )
  value
}

fn clause_ids(value: Venue) -> List(String) {
  let exchange_clause = case value {
    Nyse -> "nyse_rule_7_6"
    Nasdaq -> "nasdaq_equity_2_section_5_a_2_i"
  }
  [exchange_clause, "sec_release_34_105656"]
}

fn limitation_ids() -> List(String) {
  [
    "caller_declares_exact_listing_nms_stock_and_normal_status_without_provider_verification",
    "regular_displayed_exchange_quotation_increment_only",
    "amended_half_cent_rule_612_assignment_not_required_during_reviewed_relief_interval",
    "later_sec_order_or_exchange_rule_may_supersede_this_profile",
    "round_lot_odd_lot_order_entry_order_types_auctions_extended_hours_luld_halts_short_sales_access_fees_settlement_and_fees_excluded",
    "no_order_acceptance_execution_or_best_execution_claim",
    "redistribution_rights_unknown",
  ]
}

fn exact(value: String) -> Decimal {
  let assert Ok(parsed) = decimal.parse(value)
  parsed
}
