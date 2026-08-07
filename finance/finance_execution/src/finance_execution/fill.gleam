import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/time.{type Instant}
import finance_execution/instruction.{type Side}
import finance_execution/numeric
import finance_math/exact
import finance_provenance/identity.{type EvidenceId, type Sha256}
import gleam/list
import gleam/option.{type Option}
import gleam/order.{Eq, Gt, Lt}
import gleam/string

pub type FillKind {
  Hypothetical
  HistoricalReplay
  ObservedBrokerReceipt
  LlmDeclaredScenario
  PaperBroker
}

pub opaque type Fill {
  Fill(
    fill_id: String,
    broker_order_id: Option(String),
    exchange_order_id: Option(String),
    client_instruction_id: String,
    listing_id: String,
    venue_route: String,
    account_id: String,
    side: Side,
    quantity: Decimal,
    quantity_lexeme: String,
    quantity_unit: String,
    price: Decimal,
    price_lexeme: String,
    currency: String,
    retrieval_timestamp: Instant,
    kind: FillKind,
    raw_receipt_hash: Sha256,
    source_reference: Sha256,
    entitlement: String,
    licence: String,
    evidence_roots: List(EvidenceId),
    correction_lineage: List(String),
    bust_lineage: List(String),
  )
}

pub type FillError {
  InvalidText(field: String)
  NonPositiveQuantity
  NonPositivePrice
  QuantityLexemeMismatch
  PriceLexemeMismatch
}

pub type AggregateValue {
  AggregateCalculated(value: Decimal, output_lexeme: String)
  AggregateUnperformed(reason: String)
}

pub opaque type Aggregate {
  Aggregate(
    ordered_fills: List(Fill),
    cumulative_quantity: AggregateValue,
    total_notional: AggregateValue,
    weighted_fill_price: AggregateValue,
    currency: String,
    quantity_unit: String,
    result_kind: FillKind,
  )
}

pub fn fill(
  fill_id fill_id_value: String,
  broker_order_id broker_order_value: Option(String),
  exchange_order_id exchange_order_value: Option(String),
  client_instruction_id instruction_value: String,
  listing_id listing_value: String,
  venue_route venue_value: String,
  account_id account_value: String,
  side side_value: Side,
  quantity quantity_value: Decimal,
  quantity_lexeme quantity_lexeme_value: String,
  quantity_unit quantity_unit_value: String,
  price price_value: Decimal,
  price_lexeme price_lexeme_value: String,
  currency currency_value: String,
  retrieval_timestamp retrieval_value: Instant,
  kind kind_value: FillKind,
  raw_receipt_hash raw_hash_value: Sha256,
  source_reference source_value: Sha256,
  entitlement entitlement_value: String,
  licence licence_value: String,
  evidence_roots root_values: List(EvidenceId),
  correction_lineage correction_values: List(String),
  bust_lineage bust_values: List(String),
) -> Result(Fill, FillError) {
  case
    first_invalid_text([
      #("fill_id", fill_id_value),
      #("client_instruction_id", instruction_value),
      #("listing_id", listing_value),
      #("venue_route", venue_value),
      #("account_id", account_value),
      #("quantity_unit", quantity_unit_value),
      #("currency", currency_value),
      #("entitlement", entitlement_value),
      #("licence", licence_value),
    ])
  {
    Ok(field) -> Error(InvalidText(field))
    Error(Nil) ->
      case numeric.positive(quantity_value), numeric.positive(price_value) {
        False, _ -> Error(NonPositiveQuantity)
        _, False -> Error(NonPositivePrice)
        True, True ->
          case
            decimal.parse(quantity_lexeme_value),
            decimal.parse(price_lexeme_value)
          {
            Error(_), _ -> Error(QuantityLexemeMismatch)
            _, Error(_) -> Error(PriceLexemeMismatch)
            Ok(quantity_lexeme), Ok(price_lexeme) ->
              case
                decimal.compare(quantity_lexeme, quantity_value),
                decimal.compare(price_lexeme, price_value)
              {
                Lt, _ | Gt, _ -> Error(QuantityLexemeMismatch)
                Eq, Lt | Eq, Gt -> Error(PriceLexemeMismatch)
                Eq, Eq ->
                  Ok(Fill(
                    fill_id_value,
                    broker_order_value,
                    exchange_order_value,
                    instruction_value,
                    listing_value,
                    venue_value,
                    account_value,
                    side_value,
                    quantity_value,
                    quantity_lexeme_value,
                    quantity_unit_value,
                    price_value,
                    price_lexeme_value,
                    currency_value,
                    retrieval_value,
                    kind_value,
                    raw_hash_value,
                    source_value,
                    entitlement_value,
                    licence_value,
                    root_values,
                    correction_values,
                    bust_values,
                  ))
              }
          }
      }
  }
}

pub fn aggregate(
  ordered_fills values: List(Fill),
  output_scale output_scale_value: Int,
  rounding rounding_value: RoundingMode,
) -> Result(Aggregate, String) {
  case values {
    [] -> Error("empty_fill_list")
    [first, ..rest] -> {
      let mismatch =
        list.find(rest, fn(value) {
          value.currency != first.currency
          || value.quantity_unit != first.quantity_unit
          || value.listing_id != first.listing_id
          || value.side != first.side
          || value.kind != first.kind
        })
      case mismatch {
        Ok(_) -> Error("incompatible_fill_identity_currency_unit_side_or_kind")
        Error(_) -> {
          let quantity =
            list.fold(values, decimal.zero(), fn(total, value) {
              decimal.add(total, value.quantity)
            })
          let notional =
            list.fold(values, decimal.zero(), fn(total, value) {
              decimal.add(total, decimal.multiply(value.quantity, value.price))
            })
          let quantity_value =
            AggregateCalculated(
              quantity,
              numeric.fixed(quantity, output_scale_value),
            )
          let notional_value =
            AggregateCalculated(
              notional,
              numeric.fixed(notional, output_scale_value),
            )
          let vwap = case numeric.positive(quantity) {
            False -> AggregateUnperformed("zero_cumulative_quantity")
            True ->
              case
                exact.ratio(
                  notional,
                  quantity,
                  output_scale_value,
                  rounding_value,
                )
              {
                Ok(value) ->
                  AggregateCalculated(
                    value,
                    numeric.fixed(value, output_scale_value),
                  )
                Error(_) -> AggregateUnperformed("division_by_zero")
              }
          }
          Ok(Aggregate(
            values,
            quantity_value,
            notional_value,
            vwap,
            first.currency,
            first.quantity_unit,
            first.kind,
          ))
        }
      }
    }
  }
}

pub fn fill_id(value: Fill) -> String {
  value.fill_id
}

pub fn client_instruction_id(value: Fill) -> String {
  value.client_instruction_id
}

pub fn listing_id(value: Fill) -> String {
  value.listing_id
}

pub fn broker_order_id(value: Fill) -> Option(String) {
  value.broker_order_id
}

pub fn exchange_order_id(value: Fill) -> Option(String) {
  value.exchange_order_id
}

pub fn venue_route(value: Fill) -> String {
  value.venue_route
}

pub fn account_id(value: Fill) -> String {
  value.account_id
}

pub fn side(value: Fill) -> Side {
  value.side
}

pub fn quantity(value: Fill) -> Decimal {
  value.quantity
}

pub fn quantity_lexeme(value: Fill) -> String {
  value.quantity_lexeme
}

pub fn quantity_unit(value: Fill) -> String {
  value.quantity_unit
}

pub fn price(value: Fill) -> Decimal {
  value.price
}

pub fn price_lexeme(value: Fill) -> String {
  value.price_lexeme
}

pub fn currency(value: Fill) -> String {
  value.currency
}

pub fn retrieval_timestamp(value: Fill) -> Instant {
  value.retrieval_timestamp
}

pub fn kind(value: Fill) -> FillKind {
  value.kind
}

pub fn raw_receipt_hash(value: Fill) -> Sha256 {
  value.raw_receipt_hash
}

pub fn source_reference(value: Fill) -> Sha256 {
  value.source_reference
}

pub fn entitlement(value: Fill) -> String {
  value.entitlement
}

pub fn licence(value: Fill) -> String {
  value.licence
}

pub fn evidence_roots(value: Fill) -> List(EvidenceId) {
  value.evidence_roots
}

pub fn correction_lineage(value: Fill) -> List(String) {
  value.correction_lineage
}

pub fn bust_lineage(value: Fill) -> List(String) {
  value.bust_lineage
}

pub fn ordered_fills(value: Aggregate) -> List(Fill) {
  value.ordered_fills
}

pub fn cumulative_quantity(value: Aggregate) -> AggregateValue {
  value.cumulative_quantity
}

pub fn total_notional(value: Aggregate) -> AggregateValue {
  value.total_notional
}

pub fn weighted_fill_price(value: Aggregate) -> AggregateValue {
  value.weighted_fill_price
}

pub fn aggregate_currency(value: Aggregate) -> String {
  value.currency
}

pub fn aggregate_quantity_unit(value: Aggregate) -> String {
  value.quantity_unit
}

pub fn aggregate_result_kind(value: Aggregate) -> FillKind {
  value.result_kind
}

pub fn fill_kind_name(value: FillKind) -> String {
  case value {
    Hypothetical -> "hypothetical"
    HistoricalReplay -> "historical_replay"
    ObservedBrokerReceipt -> "observed_broker_receipt"
    LlmDeclaredScenario -> "llm_declared_scenario"
    PaperBroker -> "paper_broker"
  }
}

fn first_invalid_text(values: List(#(String, String))) -> Result(String, Nil) {
  case values {
    [] -> Error(Nil)
    [#(field, value), ..rest] ->
      case value == "" || string.trim(value) != value {
        True -> Ok(field)
        False -> first_invalid_text(rest)
      }
  }
}
