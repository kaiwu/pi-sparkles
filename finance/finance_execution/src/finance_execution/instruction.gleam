import finance_core/decimal.{type Decimal}
import finance_core/time.{type Instant}
import finance_execution/numeric
import finance_provenance/identity.{type Sha256}
import finance_track.{type Track}
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub type Side {
  Buy
  Sell
}

pub type Intent {
  Open
  Close
  Reduce
}

pub type QuantityUnit {
  Shares
  Lots
  CurrencyNotional
}

pub type TriggerBasis {
  LastSale
  Bid
  Ask
  Midpoint
  Mark
  Index(index_id: String)
  ProviderDefined(label: String)
}

pub type OrderBehavior {
  Market
  Limit(price: Decimal)
  Stop(trigger_price: Decimal, trigger_basis: TriggerBasis)
  StopLimit(
    trigger_price: Decimal,
    trigger_basis: TriggerBasis,
    limit_price: Decimal,
  )
  Auction(phase: String)
  MarketOnClose
  LimitOnClose(price: Decimal)
  TrailingStop(amount_or_fraction: Decimal, reference: String, cadence: String)
}

pub type TimeInForce {
  Day
  Gtc
  Ioc
  Fok
  Gtd(expiry: Instant)
  AuctionOnly
  ExtendedHours
}

pub type RequestedSession {
  PreOpenAuction
  Regular
  ClosingAuction
  Extended
}

pub type RetainedAlternatives {
  KnownAlternatives(values: List(String))
  AlternativesNotApplicable(reason: String)
}

pub opaque type DesiredInstruction {
  DesiredInstruction(
    instruction_id: String,
    instruction_receipt: Sha256,
    track: Track,
    listing_id: String,
    mic: String,
    account_scope: String,
    currency: String,
    side: Side,
    intent: Option(Intent),
    quantity: Decimal,
    quantity_unit: QuantityUnit,
    order_behavior: OrderBehavior,
    time_in_force: TimeInForce,
    requested_session: Option(RequestedSession),
    activation_time: Option(Instant),
    expiry_time: Option(Instant),
    timezone: String,
    rule_references: List(Sha256),
    capability_references: List(Sha256),
    account_references: List(Sha256),
    retained_alternatives: RetainedAlternatives,
  )
}

pub type InstructionError {
  InvalidText(field: String)
  NonPositiveQuantity
  InvalidBehavior(field: String)
  MissingAccountReference
}

pub fn desired(
  instruction_id instruction_id_value: String,
  instruction_receipt instruction_receipt_value: Sha256,
  track track_value: Track,
  listing_id listing_id_value: String,
  mic mic_value: String,
  account_scope account_scope_value: String,
  currency currency_value: String,
  side side_value: Side,
  intent intent_value: Option(Intent),
  quantity quantity_value: Decimal,
  quantity_unit quantity_unit_value: QuantityUnit,
  order_behavior behavior_value: OrderBehavior,
  time_in_force tif_value: TimeInForce,
  requested_session session_value: Option(RequestedSession),
  activation_time activation_value: Option(Instant),
  expiry_time expiry_value: Option(Instant),
  timezone timezone_value: String,
  rule_references rule_reference_values: List(Sha256),
  capability_references capability_reference_values: List(Sha256),
  account_references account_reference_values: List(Sha256),
  retained_alternatives alternative_values: RetainedAlternatives,
) -> Result(DesiredInstruction, InstructionError) {
  case
    valid_text(instruction_id_value),
    valid_text(listing_id_value),
    valid_text(mic_value),
    valid_text(account_scope_value),
    valid_text(currency_value),
    valid_text(timezone_value)
  {
    False, _, _, _, _, _ -> Error(InvalidText("instruction_id"))
    _, False, _, _, _, _ -> Error(InvalidText("listing_id"))
    _, _, False, _, _, _ -> Error(InvalidText("mic"))
    _, _, _, False, _, _ -> Error(InvalidText("account_scope"))
    _, _, _, _, False, _ -> Error(InvalidText("currency"))
    _, _, _, _, _, False -> Error(InvalidText("timezone"))
    True, True, True, True, True, True ->
      case numeric.positive(quantity_value), behavior_valid(behavior_value) {
        False, _ -> Error(NonPositiveQuantity)
        _, Error(field) -> Error(InvalidBehavior(field))
        True, Ok(Nil) ->
          case list.is_empty(account_reference_values) {
            True -> Error(MissingAccountReference)
            False ->
              Ok(DesiredInstruction(
                instruction_id_value,
                instruction_receipt_value,
                track_value,
                listing_id_value,
                mic_value,
                account_scope_value,
                currency_value,
                side_value,
                intent_value,
                quantity_value,
                quantity_unit_value,
                behavior_value,
                tif_value,
                session_value,
                activation_value,
                expiry_value,
                timezone_value,
                rule_reference_values,
                capability_reference_values,
                account_reference_values,
                alternative_values,
              ))
          }
      }
  }
}

pub fn instruction_id(value: DesiredInstruction) -> String {
  value.instruction_id
}

pub fn instruction_receipt(value: DesiredInstruction) -> Sha256 {
  value.instruction_receipt
}

pub fn track(value: DesiredInstruction) -> Track {
  value.track
}

pub fn listing_id(value: DesiredInstruction) -> String {
  value.listing_id
}

pub fn mic(value: DesiredInstruction) -> String {
  value.mic
}

pub fn account_scope(value: DesiredInstruction) -> String {
  value.account_scope
}

pub fn currency(value: DesiredInstruction) -> String {
  value.currency
}

pub fn side(value: DesiredInstruction) -> Side {
  value.side
}

pub fn intent(value: DesiredInstruction) -> Option(Intent) {
  value.intent
}

pub fn quantity(value: DesiredInstruction) -> Decimal {
  value.quantity
}

pub fn quantity_unit(value: DesiredInstruction) -> QuantityUnit {
  value.quantity_unit
}

pub fn order_behavior(value: DesiredInstruction) -> OrderBehavior {
  value.order_behavior
}

pub fn time_in_force(value: DesiredInstruction) -> TimeInForce {
  value.time_in_force
}

pub fn requested_session(
  value: DesiredInstruction,
) -> Option(RequestedSession) {
  value.requested_session
}

pub fn activation_time(value: DesiredInstruction) -> Option(Instant) {
  value.activation_time
}

pub fn expiry_time(value: DesiredInstruction) -> Option(Instant) {
  value.expiry_time
}

pub fn timezone(value: DesiredInstruction) -> String {
  value.timezone
}

pub fn rule_references(value: DesiredInstruction) -> List(Sha256) {
  value.rule_references
}

pub fn capability_references(value: DesiredInstruction) -> List(Sha256) {
  value.capability_references
}

pub fn account_references(value: DesiredInstruction) -> List(Sha256) {
  value.account_references
}

pub fn retained_alternatives(
  value: DesiredInstruction,
) -> RetainedAlternatives {
  value.retained_alternatives
}

pub fn side_name(value: Side) -> String {
  case value {
    Buy -> "buy"
    Sell -> "sell"
  }
}

pub fn quantity_unit_name(value: QuantityUnit) -> String {
  case value {
    Shares -> "shares"
    Lots -> "lots"
    CurrencyNotional -> "currency_notional"
  }
}

pub fn behavior_name(value: OrderBehavior) -> String {
  case value {
    Market -> "market"
    Limit(_) -> "limit"
    Stop(_, _) -> "stop"
    StopLimit(_, _, _) -> "stop_limit"
    Auction(_) -> "auction"
    MarketOnClose -> "market_on_close"
    LimitOnClose(_) -> "limit_on_close"
    TrailingStop(_, _, _) -> "trailing_stop"
  }
}

pub fn time_in_force_name(value: TimeInForce) -> String {
  case value {
    Day -> "day"
    Gtc -> "gtc"
    Ioc -> "ioc"
    Fok -> "fok"
    Gtd(_) -> "gtd"
    AuctionOnly -> "auction_only"
    ExtendedHours -> "extended_hours"
  }
}

fn behavior_valid(value: OrderBehavior) -> Result(Nil, String) {
  case value {
    Market | MarketOnClose -> Ok(Nil)
    Limit(price) | LimitOnClose(price) -> positive_price(price, "limit_price")
    Stop(price, _) -> positive_price(price, "stop_trigger_price")
    StopLimit(trigger, _, limit) ->
      case positive_price(trigger, "stop_trigger_price") {
        Error(error) -> Error(error)
        Ok(Nil) -> positive_price(limit, "limit_price")
      }
    Auction(phase) ->
      case valid_text(phase) {
        True -> Ok(Nil)
        False -> Error("auction_phase")
      }
    TrailingStop(amount, reference, cadence) ->
      case
        numeric.positive(amount),
        valid_text(reference),
        valid_text(cadence)
      {
        False, _, _ -> Error("trail_amount_or_fraction")
        _, False, _ -> Error("trail_reference")
        _, _, False -> Error("trail_cadence")
        True, True, True -> Ok(Nil)
      }
  }
}

fn positive_price(value: Decimal, field: String) -> Result(Nil, String) {
  case numeric.positive(value) {
    True -> Ok(Nil)
    False -> Error(field)
  }
}

fn valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
