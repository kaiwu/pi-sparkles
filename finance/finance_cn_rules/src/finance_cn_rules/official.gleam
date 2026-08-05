import finance_core/decimal.{type Decimal}
import finance_core/source.{type SourceRef}
import finance_core/time.{type Date}
import finance_listing/effective.{type Interval}
import gleam/option.{type Option, None, Some}

/// Venue and board are separate so invalid combinations fail instead of being
/// silently normalised.
pub type Venue {
  Sse
  Szse
  Bse
}

pub type Board {
  MainBoard
  StarMarket
  ChiNext
  BeijingMarket
}

pub type OddLotExit {
  SellRemainderOnce(threshold: Int)
}

/// A deliberately narrow, source-reviewed profile for established, normally
/// traded CNY A-shares. IPO, relisting, delisting, warning, suspension, block,
/// after-hours, and Connect rules are different regimes and are not inferred.
pub opaque type Profile {
  Profile(
    venue: Venue,
    board: Board,
    effective: Interval,
    tick_size: Decimal,
    minimum_buy_quantity: Int,
    buy_quantity_increment: Option(Int),
    odd_lot_exit: OddLotExit,
    daily_price_limit: Decimal,
    source: SourceRef,
    clauses: List(String),
    limitations: List(String),
  )
}

pub type ProfileError {
  InvalidVenueBoard
  OutsideReviewedInterval
}

pub fn established_equity(
  venue venue_value: Venue,
  board board_value: Board,
  on date: Date,
) -> Result(Profile, ProfileError) {
  case valid_combination(venue_value, board_value) {
    False -> Error(InvalidVenueBoard)
    True -> {
      let interval = current_interval()
      case effective.contains(interval, date) {
        False -> Error(OutsideReviewedInterval)
        True ->
          Ok(Profile(
            venue: venue_value,
            board: board_value,
            effective: interval,
            tick_size: exact("0.01"),
            minimum_buy_quantity: minimum_for_board(board_value),
            buy_quantity_increment: buy_increment(board_value),
            odd_lot_exit: SellRemainderOnce(odd_lot_threshold(board_value)),
            daily_price_limit: price_limit(board_value),
            source: source_ref(venue_value),
            clauses: clause_ids(venue_value, board_value),
            limitations: limitation_ids(board_value),
          ))
      }
    }
  }
}

pub fn venue(value: Profile) -> Venue {
  value.venue
}

pub fn board(value: Profile) -> Board {
  value.board
}

pub fn effective(value: Profile) -> Interval {
  value.effective
}

pub fn tick_size(value: Profile) -> Decimal {
  value.tick_size
}

pub fn minimum_buy_quantity(value: Profile) -> Int {
  value.minimum_buy_quantity
}

pub fn buy_quantity_increment(value: Profile) -> Option(Int) {
  value.buy_quantity_increment
}

pub fn odd_lot_exit(value: Profile) -> OddLotExit {
  value.odd_lot_exit
}

pub fn daily_price_limit(value: Profile) -> Decimal {
  value.daily_price_limit
}

pub fn source(value: Profile) -> SourceRef {
  value.source
}

pub fn clauses(value: Profile) -> List(String) {
  value.clauses
}

pub fn limitations(value: Profile) -> List(String) {
  value.limitations
}

pub fn venue_name(value: Venue) -> String {
  case value {
    Sse -> "sse"
    Szse -> "szse"
    Bse -> "bse"
  }
}

pub fn board_name(value: Board) -> String {
  case value {
    MainBoard -> "main"
    StarMarket -> "star"
    ChiNext -> "chinext"
    BeijingMarket -> "beijing"
  }
}

fn valid_combination(venue: Venue, board: Board) -> Bool {
  case venue, board {
    Sse, MainBoard
    | Sse, StarMarket
    | Szse, MainBoard
    | Szse, ChiNext
    | Bse, BeijingMarket
    -> True
    _, _ -> False
  }
}

fn current_interval() -> Interval {
  let assert Ok(start) = time.date(2026, 7, 6)
  let assert Ok(value) = effective.new(start, None)
  value
}

fn minimum_for_board(board: Board) -> Int {
  case board {
    StarMarket -> 200
    MainBoard | ChiNext | BeijingMarket -> 100
  }
}

fn buy_increment(board: Board) -> Option(Int) {
  case board {
    MainBoard | ChiNext -> Some(100)
    StarMarket | BeijingMarket -> None
  }
}

fn odd_lot_threshold(board: Board) -> Int {
  case board {
    StarMarket -> 200
    MainBoard | ChiNext | BeijingMarket -> 100
  }
}

fn price_limit(board: Board) -> Decimal {
  case board {
    MainBoard -> exact("0.10")
    StarMarket | ChiNext -> exact("0.20")
    BeijingMarket -> exact("0.30")
  }
}

fn source_ref(venue: Venue) -> SourceRef {
  let #(provider, reference) = case venue {
    Sse -> #(
      "Shanghai Stock Exchange",
      "https://www.sse.com.cn/lawandrules/sselawsrules2025/stocks/exchange/c/c_20260424_10816482.shtml",
    )
    Szse -> #(
      "Shenzhen Stock Exchange",
      "https://investor.szse.cn/lawrules/rule/trade/t20260424_620190.html",
    )
    Bse -> #(
      "Beijing Stock Exchange",
      "https://www.bse.cn/jygl_list/200028217.html",
    )
  }
  let assert Ok(value) = source.new(provider, reference, source.Exchange)
  value
}

fn clause_ids(venue: Venue, board: Board) -> List(String) {
  case venue, board {
    Sse, MainBoard -> ["3.3.8", "3.3.11", "3.3.13"]
    Sse, StarMarket -> ["3.3.11", "6.6", "6.7"]
    Szse, MainBoard | Szse, ChiNext -> ["3.3.8", "3.3.11", "3.3.13"]
    Bse, BeijingMarket -> ["3.3.8", "3.3.10", "3.3.11"]
    _, _ -> []
  }
}

fn limitation_ids(board: Board) -> List(String) {
  let quantity_gap = case board {
    StarMarket | BeijingMarket -> [
      "quantity_increment_not_claimed_from_reviewed_clauses",
    ]
    MainBoard | ChiNext -> []
  }
  [
    "established_normal_cny_a_share_continuous_auction_only",
    "ipo_relisting_delisting_warning_suspension_block_after_hours_and_connect_regimes_excluded",
    "price_limit_is_a_ratio_not_a_computed_order_price",
    "settlement_and_investor_eligibility_not_in_this_profile",
    ..quantity_gap
  ]
}

fn exact(value: String) -> Decimal {
  let assert Ok(parsed) = decimal.parse(value)
  parsed
}
