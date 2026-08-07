import finance_core/decimal.{type Decimal}
import finance_core/time.{type Date, type Instant}
import finance_listing/listing.{type Key}
import finance_provenance/identity.{type EvidenceId, type Sha256}
import gleam/list
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string

pub type DeclarationOrigin {
  LlmProposed
  UserDeclared
}

pub opaque type ExactPrice {
  ExactPrice(raw: String, value: Decimal)
}

/// A desired analytical plan declared by the LLM or user.
///
/// It is not an executable order, risk approval, market-rule validation, or
/// provider fact. Construction only validates internal long-plan shape.
pub opaque type PlanDeclaration {
  PlanDeclaration(
    origin: DeclarationOrigin,
    listing: Key,
    definition_hash: Sha256,
    created_at: Instant,
    entry_session: Date,
    final_entry_session: Date,
    entry_ceiling: ExactPrice,
    desired_stop: ExactPrice,
    target: ExactPrice,
    protective_level_method: String,
    monitoring_intent: String,
    source_evidence_roots: List(EvidenceId),
  )
}

pub type PlanError {
  InvalidPrice
  NonPositivePrice
  InvalidEntryWindow
  InvalidLongPriceShape
  InvalidDeclaration
  DuplicateEvidenceRoot
}

pub fn exact_price(raw raw_value: String) -> Result(ExactPrice, PlanError) {
  case decimal.parse(raw_value) {
    Error(_) -> Error(InvalidPrice)
    Ok(value) ->
      case decimal.compare(value, decimal.zero()) == Gt {
        True -> Ok(ExactPrice(raw_value, value))
        False -> Error(NonPositivePrice)
      }
  }
}

pub fn declare(
  origin origin_value: DeclarationOrigin,
  listing listing_value: Key,
  definition_hash definition_hash_value: Sha256,
  created_at created_at_value: Instant,
  entry_session entry_session_value: Date,
  final_entry_session final_entry_session_value: Date,
  entry_ceiling entry_ceiling_value: ExactPrice,
  desired_stop desired_stop_value: ExactPrice,
  target target_value: ExactPrice,
  protective_level_method protective_level_method_value: String,
  monitoring_intent monitoring_intent_value: String,
  source_evidence_roots evidence_root_values: List(EvidenceId),
) -> Result(PlanDeclaration, PlanError) {
  use _ <- result.try(validate_window(
    entry_session_value,
    final_entry_session_value,
  ))
  use _ <- result.try(validate_price_shape(
    entry_ceiling_value,
    desired_stop_value,
    target_value,
  ))
  use _ <- result.try(validate_declaration(
    protective_level_method_value,
    monitoring_intent_value,
  ))
  use _ <- result.try(validate_roots(evidence_root_values, []))
  Ok(PlanDeclaration(
    origin_value,
    listing_value,
    definition_hash_value,
    created_at_value,
    entry_session_value,
    final_entry_session_value,
    entry_ceiling_value,
    desired_stop_value,
    target_value,
    protective_level_method_value,
    monitoring_intent_value,
    evidence_root_values,
  ))
}

pub fn origin(value: PlanDeclaration) -> DeclarationOrigin {
  value.origin
}

pub fn listing(value: PlanDeclaration) -> Key {
  value.listing
}

pub fn definition_hash(value: PlanDeclaration) -> Sha256 {
  value.definition_hash
}

pub fn created_at(value: PlanDeclaration) -> Instant {
  value.created_at
}

pub fn entry_session(value: PlanDeclaration) -> Date {
  value.entry_session
}

pub fn final_entry_session(value: PlanDeclaration) -> Date {
  value.final_entry_session
}

pub fn entry_ceiling(value: PlanDeclaration) -> ExactPrice {
  value.entry_ceiling
}

pub fn desired_stop(value: PlanDeclaration) -> ExactPrice {
  value.desired_stop
}

pub fn target(value: PlanDeclaration) -> ExactPrice {
  value.target
}

pub fn protective_level_method(value: PlanDeclaration) -> String {
  value.protective_level_method
}

pub fn monitoring_intent(value: PlanDeclaration) -> String {
  value.monitoring_intent
}

pub fn source_evidence_roots(value: PlanDeclaration) -> List(EvidenceId) {
  value.source_evidence_roots
}

pub fn price_raw(value: ExactPrice) -> String {
  value.raw
}

pub fn price_value(value: ExactPrice) -> Decimal {
  value.value
}

fn validate_window(start: Date, end: Date) -> Result(Nil, PlanError) {
  case date_number(end) >= date_number(start) {
    True -> Ok(Nil)
    False -> Error(InvalidEntryWindow)
  }
}

fn validate_price_shape(
  entry: ExactPrice,
  stop: ExactPrice,
  target: ExactPrice,
) -> Result(Nil, PlanError) {
  case
    decimal.compare(stop.value, entry.value),
    decimal.compare(entry.value, target.value)
  {
    Lt, Lt -> Ok(Nil)
    _, _ -> Error(InvalidLongPriceShape)
  }
}

fn validate_declaration(
  first: String,
  second: String,
) -> Result(Nil, PlanError) {
  case valid_identifier(first) && valid_identifier(second) {
    True -> Ok(Nil)
    False -> Error(InvalidDeclaration)
  }
}

fn validate_roots(
  roots: List(EvidenceId),
  seen: List(EvidenceId),
) -> Result(Nil, PlanError) {
  case roots {
    [] -> Ok(Nil)
    [root, ..rest] ->
      case list.contains(seen, root) {
        True -> Error(DuplicateEvidenceRoot)
        False -> validate_roots(rest, [root, ..seen])
      }
  }
}

fn valid_identifier(value: String) -> Bool {
  value != ""
  && string.length(value) <= 200
  && string.trim(value) == value
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn date_number(value: Date) -> Int {
  let #(year, month, day) = time.date_parts(value)
  year * 10_000 + month * 100 + day
}
