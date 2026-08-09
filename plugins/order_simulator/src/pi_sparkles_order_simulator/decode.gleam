import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type SourceInput {
  SourceInput(
    kind: String,
    reference: String,
    effective_at_unix_ms: Int,
    retrieved_at_unix_ms: Int,
    currency: String,
    unit: String,
    source_lexeme: String,
    scope: String,
    retained_alternatives: List(String),
  )
}

pub type BarValueInput {
  BarValueInput(open: String, high: String, low: String, close: String)
}

pub type BarSourcedInput {
  BarSourcedInput(value: BarValueInput, source: SourceInput)
}

pub type BarFactInput {
  BarFactInput(
    state: String,
    value: Option(BarValueInput),
    source: Option(SourceInput),
    reason: Option(String),
    raw: Option(String),
    alternatives: List(BarSourcedInput),
  )
}

pub type BoolSourcedInput {
  BoolSourcedInput(value: Bool, source: SourceInput)
}

pub type BoolFactInput {
  BoolFactInput(
    state: String,
    value: Option(Bool),
    source: Option(SourceInput),
    reason: Option(String),
    raw: Option(String),
    alternatives: List(BoolSourcedInput),
  )
}

pub type TriggerBasisInput {
  TriggerBasisInput(kind: String, label: Option(String))
}

pub type OrderBehaviorInput {
  OrderBehaviorInput(
    kind: String,
    price: Option(String),
    trigger_price: Option(String),
    trigger_basis: Option(TriggerBasisInput),
    phase: Option(String),
    trail_value: Option(String),
    trail_reference: Option(String),
    trail_cadence: Option(String),
  )
}

pub type TimeInForceInput {
  TimeInForceInput(kind: String, expiry_unix_ms: Option(Int))
}

pub type RetainedAlternativesInput {
  RetainedAlternativesInput(
    state: String,
    values: List(String),
    reason: Option(String),
  )
}

pub type InstructionInput {
  InstructionInput(
    instruction_id: String,
    instruction_receipt: String,
    track: String,
    listing_id: String,
    mic: String,
    account_scope: String,
    currency: String,
    side: String,
    intent: Option(String),
    quantity: String,
    quantity_unit: String,
    order_behavior: OrderBehaviorInput,
    time_in_force: TimeInForceInput,
    requested_session: Option(String),
    activation_time_unix_ms: Option(Int),
    expiry_time_unix_ms: Option(Int),
    timezone: String,
    rule_references: List(String),
    capability_references: List(String),
    account_references: List(String),
    retained_alternatives: RetainedAlternativesInput,
  )
}

pub type ReferenceSetInput {
  ReferenceSetInput(
    capability_references: List(String),
    rule_references: List(String),
    calendar_references: List(String),
    market_event_references: List(String),
    lifecycle_references: List(String),
    position_references: List(String),
    risk_receipt_references: List(String),
    cost_receipt_references: List(String),
    fx_receipts: List(String),
  )
}

pub type RoundingInput {
  RoundingInput(output_scale: Int, mode: String)
}

pub type PolicyInput {
  PolicyInput(
    model: String,
    calculation_policy: String,
    capability_policy: String,
    branch_policy: String,
    session_scope: String,
    date_time_scope: String,
    currency_policy: String,
    rounding: RoundingInput,
    references: ReferenceSetInput,
    maximum_branches: Int,
    maximum_outputs: Int,
    maximum_bytes: Int,
    maximum_operations: Int,
    projection: String,
  )
}

pub type SimulationInput {
  SimulationInput(
    operation_id: String,
    instruction: InstructionInput,
    bar: BarFactInput,
    desired_order_supported: BoolFactInput,
    policy: PolicyInput,
  )
}

pub fn simulate_bar_paths() -> decoder.Decoder(SimulationInput) {
  use operation_id <- decoder.field("operationId", decoder.string)
  use instruction <- decoder.field("instruction", instruction_decoder())
  use bar <- decoder.field("bar", bar_fact_decoder())
  use supported <- decoder.field("desiredOrderSupported", bool_fact_decoder())
  use policy <- decoder.field("policy", policy_decoder())
  decoder.success(SimulationInput(
    operation_id,
    instruction,
    bar,
    supported,
    policy,
  ))
}

fn instruction_decoder() -> decoder.Decoder(InstructionInput) {
  use instruction_id <- decoder.field("instructionId", decoder.string)
  use instruction_receipt <- decoder.field("instructionReceipt", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use account_scope <- decoder.field("accountScope", decoder.string)
  use currency <- decoder.field("currency", decoder.string)
  use side <- decoder.field("side", decoder.string)
  use intent <- optional_string("intent")
  use quantity <- decoder.field("quantity", decoder.string)
  use quantity_unit <- decoder.field("quantityUnit", decoder.string)
  use behavior <- decoder.field("orderBehavior", order_behavior_decoder())
  use tif <- decoder.field("timeInForce", time_in_force_decoder())
  use session <- optional_string("requestedSession")
  use activation <- optional_int("activationTimeUnixMilliseconds")
  use expiry <- optional_int("expiryTimeUnixMilliseconds")
  use timezone <- decoder.field("timezone", decoder.string)
  use rule_references <- string_list("ruleReferences")
  use capability_references <- string_list("capabilityReferences")
  use account_references <- string_list("accountReferences")
  use alternatives <- decoder.field(
    "retainedAlternatives",
    retained_alternatives_decoder(),
  )
  decoder.success(InstructionInput(
    instruction_id,
    instruction_receipt,
    track,
    listing_id,
    mic,
    account_scope,
    currency,
    side,
    intent,
    quantity,
    quantity_unit,
    behavior,
    tif,
    session,
    activation,
    expiry,
    timezone,
    rule_references,
    capability_references,
    account_references,
    alternatives,
  ))
}

fn order_behavior_decoder() -> decoder.Decoder(OrderBehaviorInput) {
  use kind <- decoder.field("kind", decoder.string)
  use price <- optional_string("price")
  use trigger_price <- optional_string("triggerPrice")
  use trigger_basis <- optional_trigger_basis("triggerBasis")
  use phase <- optional_string("phase")
  use trail_value <- optional_string("trailValue")
  use trail_reference <- optional_string("trailReference")
  use trail_cadence <- optional_string("trailCadence")
  decoder.success(OrderBehaviorInput(
    kind,
    price,
    trigger_price,
    trigger_basis,
    phase,
    trail_value,
    trail_reference,
    trail_cadence,
  ))
}

fn trigger_basis_decoder() -> decoder.Decoder(TriggerBasisInput) {
  use kind <- decoder.field("kind", decoder.string)
  use label <- optional_string("label")
  decoder.success(TriggerBasisInput(kind, label))
}

fn time_in_force_decoder() -> decoder.Decoder(TimeInForceInput) {
  use kind <- decoder.field("kind", decoder.string)
  use expiry <- optional_int("expiryUnixMilliseconds")
  decoder.success(TimeInForceInput(kind, expiry))
}

fn retained_alternatives_decoder() -> decoder.Decoder(RetainedAlternativesInput) {
  use state <- decoder.field("state", decoder.string)
  use values <- decoder.field("values", decoder.list(of: decoder.string))
  use reason <- optional_string("reason")
  decoder.success(RetainedAlternativesInput(state, values, reason))
}

fn bar_fact_decoder() -> decoder.Decoder(BarFactInput) {
  use state <- decoder.field("state", decoder.string)
  use value <- optional_bar("value")
  use source <- optional_source("source")
  use reason <- optional_string("reason")
  use raw <- optional_string("raw")
  use alternatives <- decoder.optional_field(
    "alternatives",
    [],
    decoder.list(of: bar_sourced_decoder()),
  )
  decoder.success(BarFactInput(state, value, source, reason, raw, alternatives))
}

fn bar_decoder() -> decoder.Decoder(BarValueInput) {
  use open <- decoder.field("open", decoder.string)
  use high <- decoder.field("high", decoder.string)
  use low <- decoder.field("low", decoder.string)
  use close <- decoder.field("close", decoder.string)
  decoder.success(BarValueInput(open, high, low, close))
}

fn bar_sourced_decoder() -> decoder.Decoder(BarSourcedInput) {
  use value <- decoder.field("value", bar_decoder())
  use source <- decoder.field("source", source_decoder())
  decoder.success(BarSourcedInput(value, source))
}

fn bool_fact_decoder() -> decoder.Decoder(BoolFactInput) {
  use state <- decoder.field("state", decoder.string)
  use value <- optional_bool("value")
  use source <- optional_source("source")
  use reason <- optional_string("reason")
  use raw <- optional_string("raw")
  use alternatives <- decoder.optional_field(
    "alternatives",
    [],
    decoder.list(of: bool_sourced_decoder()),
  )
  decoder.success(BoolFactInput(state, value, source, reason, raw, alternatives))
}

fn bool_sourced_decoder() -> decoder.Decoder(BoolSourcedInput) {
  use value <- decoder.field("value", decoder.bool)
  use source <- decoder.field("source", source_decoder())
  decoder.success(BoolSourcedInput(value, source))
}

fn policy_decoder() -> decoder.Decoder(PolicyInput) {
  use model <- decoder.field("model", decoder.string)
  use calculation_policy <- decoder.field("calculationPolicy", decoder.string)
  use capability_policy <- decoder.field("capabilityPolicy", decoder.string)
  use branch_policy <- decoder.field("branchPolicy", decoder.string)
  use session_scope <- decoder.field("sessionScope", decoder.string)
  use date_time_scope <- decoder.field("dateTimeScope", decoder.string)
  use currency_policy <- decoder.field("currencyPolicy", decoder.string)
  use rounding <- decoder.field("rounding", rounding_decoder())
  use references <- decoder.field("references", reference_set_decoder())
  use maximum_branches <- decoder.field("maximumBranches", decoder.int)
  use maximum_outputs <- decoder.field("maximumOutputs", decoder.int)
  use maximum_bytes <- decoder.field("maximumBytes", decoder.int)
  use maximum_operations <- decoder.field("maximumOperations", decoder.int)
  use projection <- decoder.field("projection", decoder.string)
  decoder.success(PolicyInput(
    model,
    calculation_policy,
    capability_policy,
    branch_policy,
    session_scope,
    date_time_scope,
    currency_policy,
    rounding,
    references,
    maximum_branches,
    maximum_outputs,
    maximum_bytes,
    maximum_operations,
    projection,
  ))
}

fn rounding_decoder() -> decoder.Decoder(RoundingInput) {
  use output_scale <- decoder.field("outputScale", decoder.int)
  use mode <- decoder.field("mode", decoder.string)
  decoder.success(RoundingInput(output_scale, mode))
}

fn reference_set_decoder() -> decoder.Decoder(ReferenceSetInput) {
  use capability <- string_list("capabilityReferences")
  use rules <- string_list("ruleReferences")
  use calendars <- string_list("calendarReferences")
  use market_events <- string_list("marketEventReferences")
  use lifecycle <- string_list("lifecycleReferences")
  use positions <- string_list("positionReferences")
  use risk <- string_list("riskReceiptReferences")
  use cost <- string_list("costReceiptReferences")
  use fx <- string_list("fxReceipts")
  decoder.success(ReferenceSetInput(
    capability,
    rules,
    calendars,
    market_events,
    lifecycle,
    positions,
    risk,
    cost,
    fx,
  ))
}

fn source_decoder() -> decoder.Decoder(SourceInput) {
  use kind <- decoder.field("kind", decoder.string)
  use reference <- decoder.field("reference", decoder.string)
  use effective_at <- decoder.field("effectiveAtUnixMilliseconds", decoder.int)
  use retrieved_at <- decoder.field("retrievedAtUnixMilliseconds", decoder.int)
  use currency <- decoder.field("currency", decoder.string)
  use unit <- decoder.field("unit", decoder.string)
  use source_lexeme <- decoder.field("sourceLexeme", decoder.string)
  use scope <- decoder.field("scope", decoder.string)
  use alternatives <- decoder.field(
    "retainedAlternatives",
    decoder.list(of: decoder.string),
  )
  decoder.success(SourceInput(
    kind,
    reference,
    effective_at,
    retrieved_at,
    currency,
    unit,
    source_lexeme,
    scope,
    alternatives,
  ))
}

fn string_list(
  name: String,
  next: fn(List(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.field(name, decoder.list(of: decoder.string), next)
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}

fn optional_int(
  name: String,
  next: fn(Option(Int)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.int), next)
}

fn optional_bool(
  name: String,
  next: fn(Option(Bool)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.bool), next)
}

fn optional_source(
  name: String,
  next: fn(Option(SourceInput)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(source_decoder()), next)
}

fn optional_bar(
  name: String,
  next: fn(Option(BarValueInput)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(bar_decoder()), next)
}

fn optional_trigger_basis(
  name: String,
  next: fn(Option(TriggerBasisInput)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(
    name,
    None,
    decoder.optional(trigger_basis_decoder()),
    next,
  )
}
