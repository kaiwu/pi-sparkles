import finance_core/decimal.{type Decimal}
import finance_core/source.{type SourceRef}
import finance_core/time.{type Date}
import finance_listing/effective.{type Interval}
import gleam/option.{None}
import gleam/order.{Gt, Lt}
import gleam/string

pub type PriceBand {
  HalfToTen
  TenToTwenty
  TwentyToFifty
}

/// Current HKEX board-lot-market profile for an applicable HKD equity.
///
/// The issuer-specific board lot is caller supplied with its own evidence
/// reference. This profile never manufactures a universal Hong Kong lot size.
pub opaque type Profile {
  Profile(
    effective: Interval,
    nominal_price: Decimal,
    price_band: PriceBand,
    tick_size: Decimal,
    board_lot: Int,
    board_lot_source: String,
    spread_source: SourceRef,
    board_lot_rule_source: SourceRef,
    clauses: List(String),
    limitations: List(String),
  )
}

pub type ProfileError {
  OutsideReviewedInterval
  UnsupportedPriceBand
  InvalidBoardLot
  InvalidBoardLotSource
}

pub fn applicable_hkd_equity(
  on date: Date,
  nominal_price price: Decimal,
  board_lot board_lot_value: Int,
  board_lot_source evidence_reference: String,
) -> Result(Profile, ProfileError) {
  let interval = current_interval()
  case
    effective.contains(interval, date),
    price_band(price),
    board_lot_value > 0,
    valid_evidence_reference(evidence_reference)
  {
    False, _, _, _ -> Error(OutsideReviewedInterval)
    _, Error(_), _, _ -> Error(UnsupportedPriceBand)
    _, _, False, _ -> Error(InvalidBoardLot)
    _, _, _, False -> Error(InvalidBoardLotSource)
    True, Ok(band), True, True ->
      Ok(
        Profile(
          effective: interval,
          nominal_price: price,
          price_band: band,
          tick_size: tick_for(band),
          board_lot: board_lot_value,
          board_lot_source: evidence_reference,
          spread_source: official_spread_source(),
          board_lot_rule_source: official_board_lot_rule_source(),
          clauses: [
            "phase_1_price_bands",
            "phase_2_price_band",
            "board_lot_faq",
          ],
          limitations: [
            "caller_declares_applicable_hkd_equity_and_nominal_price",
            "board_lot_value_and_evidence_reference_are_caller_supplied_not_fetched_or_verified",
            "only_nominal_prices_from_0_50_inclusive_to_50_00_exclusive_are_supported",
            "etps_debt_options_structured_products_and_non_hkd_counters_are_excluded",
            "odd_lots_use_a_separate_non_auto_matching_market",
            "vcm_cas_short_selling_settlement_and_listing_specific_eligibility_are_excluded",
          ],
        ),
      )
  }
}

pub fn effective(value: Profile) -> Interval {
  value.effective
}

pub fn nominal_price(value: Profile) -> Decimal {
  value.nominal_price
}

pub fn price_band(value: Decimal) -> Result(PriceBand, Nil) {
  case
    decimal.compare(value, exact("0.50")),
    decimal.compare(value, exact("10.00")),
    decimal.compare(value, exact("20.00")),
    decimal.compare(value, exact("50.00"))
  {
    Lt, _, _, _ -> Error(Nil)
    _, Lt, _, _ -> Ok(HalfToTen)
    _, _, Lt, _ -> Ok(TenToTwenty)
    _, _, _, Lt -> Ok(TwentyToFifty)
    _, _, _, Gt -> Error(Nil)
    _, _, _, _ -> Error(Nil)
  }
}

pub fn selected_price_band(value: Profile) -> PriceBand {
  value.price_band
}

pub fn tick_size(value: Profile) -> Decimal {
  value.tick_size
}

pub fn board_lot(value: Profile) -> Int {
  value.board_lot
}

pub fn board_lot_source(value: Profile) -> String {
  value.board_lot_source
}

pub fn spread_source(value: Profile) -> SourceRef {
  value.spread_source
}

pub fn board_lot_rule_source(value: Profile) -> SourceRef {
  value.board_lot_rule_source
}

pub fn clauses(value: Profile) -> List(String) {
  value.clauses
}

pub fn limitations(value: Profile) -> List(String) {
  value.limitations
}

pub fn price_band_name(value: PriceBand) -> String {
  case value {
    HalfToTen -> "0.50_to_10.00"
    TenToTwenty -> "10.00_to_20.00"
    TwentyToFifty -> "20.00_to_50.00"
  }
}

fn tick_for(value: PriceBand) -> Decimal {
  case value {
    HalfToTen -> exact("0.005")
    TenToTwenty -> exact("0.01")
    TwentyToFifty -> exact("0.02")
  }
}

fn current_interval() -> Interval {
  let assert Ok(start) = time.date(2026, 8, 3)
  let assert Ok(value) = effective.new(start, None)
  value
}

fn official_spread_source() -> SourceRef {
  let assert Ok(value) =
    source.new(
      "Hong Kong Exchanges and Clearing",
      "https://www.hkex.com.hk/Services/Trading/Securities/Overview/Trading-Mechanism/Reduction-of-Minimum-Spreads?sc_lang=en",
      source.Exchange,
    )
  value
}

fn official_board_lot_rule_source() -> SourceRef {
  let assert Ok(value) =
    source.new(
      "Hong Kong Exchanges and Clearing",
      "https://www.hkex.com.hk/Global/Exchange/FAQ/Securities-Market/Trading/Securities-Market-Operations?sc_lang=en&search=Special+Trading+Unit+Market",
      source.Exchange,
    )
  value
}

fn valid_evidence_reference(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 500
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn exact(value: String) -> Decimal {
  let assert Ok(parsed) = decimal.parse(value)
  parsed
}
