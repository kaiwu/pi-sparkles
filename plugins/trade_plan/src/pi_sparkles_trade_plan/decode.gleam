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

pub type DecimalSourcedInput {
  DecimalSourcedInput(value: String, source: SourceInput)
}

pub type DecimalFactInput {
  DecimalFactInput(
    state: String,
    value: Option(String),
    source: Option(SourceInput),
    reason: Option(String),
    raw: Option(String),
    alternatives: List(DecimalSourcedInput),
  )
}

pub type TradeUnitValueInput {
  TradeUnitValueInput(minimum: Int, increment: Int)
}

pub type TradeUnitSourcedInput {
  TradeUnitSourcedInput(value: TradeUnitValueInput, source: SourceInput)
}

pub type TradeUnitFactInput {
  TradeUnitFactInput(
    state: String,
    value: Option(TradeUnitValueInput),
    source: Option(SourceInput),
    reason: Option(String),
    raw: Option(String),
    alternatives: List(TradeUnitSourcedInput),
  )
}

pub type RoundingInput {
  RoundingInput(
    mode: String,
    policy: String,
    output_scale: Int,
    intermediate_scale: Int,
  )
}

pub type BranchPolicyInput {
  BranchPolicyInput(
    kind: String,
    branch_id: Option(String),
    instruction_ref: Option(String),
  )
}

pub type ContextInput {
  ContextInput(
    instruction_ref: String,
    account_scope: String,
    portfolio_scope: String,
    track: String,
    listing_id: String,
    as_of_unix_ms: Int,
    native_currency: String,
    evidence_roots: List(String),
  )
}

pub type CommonInput {
  CommonInput(
    context: ContextInput,
    rounding: RoundingInput,
    branch_policy: BranchPolicyInput,
    maximum_operations: Int,
    maximum_outputs: Int,
    projection: String,
  )
}

pub type DenominatorInput {
  DenominatorInput(
    kind: String,
    operand_name: Option(String),
    formula_variant: Option(String),
    output_unit: Option(String),
    value: Option(DecimalFactInput),
    entry: Option(DecimalFactInput),
    stop: Option(DecimalFactInput),
  )
}

pub type BoundInput {
  BoundInput(
    bound_id: String,
    formula_variant: String,
    numerator_name: String,
    numerator: DecimalFactInput,
    denominator: DenominatorInput,
  )
}

pub type IntersectionInput {
  IntersectionInput(
    state: String,
    operation_id: Option(String),
    selected_bound_ids: List(String),
  )
}

pub type LossInput {
  LossInput(
    common: CommonInput,
    operation_id: String,
    entry: DecimalFactInput,
    stop: DecimalFactInput,
  )
}

pub type BoundsInput {
  BoundsInput(
    common: CommonInput,
    bounds: List(BoundInput),
    trade_unit: TradeUnitFactInput,
    intersection: IntersectionInput,
  )
}

pub type GridInput {
  GridInput(
    common: CommonInput,
    bound: BoundInput,
    trade_unit: TradeUnitFactInput,
  )
}

pub fn plan_loss() -> decoder.Decoder(LossInput) {
  use common <- decoder.field("common", common_decoder())
  use operation_id <- decoder.field("operationId", decoder.string)
  use entry <- decoder.field("entry", decimal_fact_decoder())
  use stop <- decoder.field("stop", decimal_fact_decoder())
  decoder.success(LossInput(common, operation_id, entry, stop))
}

pub fn plan_bounds() -> decoder.Decoder(BoundsInput) {
  use common <- decoder.field("common", common_decoder())
  use bounds <- decoder.field("bounds", decoder.list(of: bound_decoder()))
  use trade_unit <- decoder.field("tradeUnit", trade_unit_fact_decoder())
  use intersection <- decoder.field("intersection", intersection_decoder())
  decoder.success(BoundsInput(common, bounds, trade_unit, intersection))
}

pub fn plan_grid_projection() -> decoder.Decoder(GridInput) {
  use common <- decoder.field("common", common_decoder())
  use bound <- decoder.field("bound", bound_decoder())
  use trade_unit <- decoder.field("tradeUnit", trade_unit_fact_decoder())
  decoder.success(GridInput(common, bound, trade_unit))
}

fn common_decoder() -> decoder.Decoder(CommonInput) {
  use context <- decoder.field("context", context_decoder())
  use rounding <- decoder.field("rounding", rounding_decoder())
  use branch_policy <- decoder.field("branchPolicy", branch_policy_decoder())
  use maximum_operations <- decoder.field("maximumOperations", decoder.int)
  use maximum_outputs <- decoder.field("maximumOutputs", decoder.int)
  use projection <- decoder.field("projection", decoder.string)
  decoder.success(CommonInput(
    context,
    rounding,
    branch_policy,
    maximum_operations,
    maximum_outputs,
    projection,
  ))
}

fn context_decoder() -> decoder.Decoder(ContextInput) {
  use instruction_ref <- decoder.field("instructionRef", decoder.string)
  use account_scope <- decoder.field("accountScope", decoder.string)
  use portfolio_scope <- decoder.field("portfolioScope", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use listing_id <- decoder.field("listingId", decoder.string)
  use as_of <- decoder.field("asOfUnixMilliseconds", decoder.int)
  use native_currency <- decoder.field("nativeCurrency", decoder.string)
  use evidence_roots <- decoder.field(
    "evidenceRoots",
    decoder.list(of: decoder.string),
  )
  decoder.success(ContextInput(
    instruction_ref,
    account_scope,
    portfolio_scope,
    track,
    listing_id,
    as_of,
    native_currency,
    evidence_roots,
  ))
}

fn rounding_decoder() -> decoder.Decoder(RoundingInput) {
  use mode <- decoder.field("mode", decoder.string)
  use policy <- decoder.field("policy", decoder.string)
  use output_scale <- decoder.field("outputScale", decoder.int)
  use intermediate_scale <- decoder.field("intermediateScale", decoder.int)
  decoder.success(RoundingInput(mode, policy, output_scale, intermediate_scale))
}

fn branch_policy_decoder() -> decoder.Decoder(BranchPolicyInput) {
  use kind <- decoder.field("kind", decoder.string)
  use branch_id <- optional_string("branchId")
  use instruction_ref <- optional_string("instructionRef")
  decoder.success(BranchPolicyInput(kind, branch_id, instruction_ref))
}

fn bound_decoder() -> decoder.Decoder(BoundInput) {
  use bound_id <- decoder.field("boundId", decoder.string)
  use formula_variant <- decoder.field("formulaVariant", decoder.string)
  use numerator_name <- decoder.field("numeratorName", decoder.string)
  use numerator <- decoder.field("numerator", decimal_fact_decoder())
  use denominator <- decoder.field("denominator", denominator_decoder())
  decoder.success(BoundInput(
    bound_id,
    formula_variant,
    numerator_name,
    numerator,
    denominator,
  ))
}

fn denominator_decoder() -> decoder.Decoder(DenominatorInput) {
  use kind <- decoder.field("kind", decoder.string)
  use operand_name <- optional_string("operandName")
  use formula_variant <- optional_string("formulaVariant")
  use output_unit <- optional_string("outputUnit")
  use value <- optional_decimal_fact("value")
  use entry <- optional_decimal_fact("entry")
  use stop <- optional_decimal_fact("stop")
  decoder.success(DenominatorInput(
    kind,
    operand_name,
    formula_variant,
    output_unit,
    value,
    entry,
    stop,
  ))
}

fn intersection_decoder() -> decoder.Decoder(IntersectionInput) {
  use state <- decoder.field("state", decoder.string)
  use operation_id <- optional_string("operationId")
  use bound_ids <- decoder.field(
    "selectedBoundIds",
    decoder.list(of: decoder.string),
  )
  decoder.success(IntersectionInput(state, operation_id, bound_ids))
}

fn decimal_fact_decoder() -> decoder.Decoder(DecimalFactInput) {
  use state <- decoder.field("state", decoder.string)
  use value <- optional_string("value")
  use source <- optional_source("source")
  use reason <- optional_string("reason")
  use raw <- optional_string("raw")
  use alternatives <- decoder.optional_field(
    "alternatives",
    [],
    decoder.list(of: decimal_sourced_decoder()),
  )
  decoder.success(DecimalFactInput(
    state,
    value,
    source,
    reason,
    raw,
    alternatives,
  ))
}

fn decimal_sourced_decoder() -> decoder.Decoder(DecimalSourcedInput) {
  use value <- decoder.field("value", decoder.string)
  use source <- decoder.field("source", source_decoder())
  decoder.success(DecimalSourcedInput(value, source))
}

fn trade_unit_fact_decoder() -> decoder.Decoder(TradeUnitFactInput) {
  use state <- decoder.field("state", decoder.string)
  use value <- optional_trade_unit("value")
  use source <- optional_source("source")
  use reason <- optional_string("reason")
  use raw <- optional_string("raw")
  use alternatives <- decoder.optional_field(
    "alternatives",
    [],
    decoder.list(of: trade_unit_sourced_decoder()),
  )
  decoder.success(TradeUnitFactInput(
    state,
    value,
    source,
    reason,
    raw,
    alternatives,
  ))
}

fn trade_unit_decoder() -> decoder.Decoder(TradeUnitValueInput) {
  use minimum <- decoder.field("minimum", decoder.int)
  use increment <- decoder.field("increment", decoder.int)
  decoder.success(TradeUnitValueInput(minimum, increment))
}

fn trade_unit_sourced_decoder() -> decoder.Decoder(TradeUnitSourcedInput) {
  use value <- decoder.field("value", trade_unit_decoder())
  use source <- decoder.field("source", source_decoder())
  decoder.success(TradeUnitSourcedInput(value, source))
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

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}

fn optional_source(
  name: String,
  next: fn(Option(SourceInput)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(source_decoder()), next)
}

fn optional_decimal_fact(
  name: String,
  next: fn(Option(DecimalFactInput)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(
    name,
    None,
    decoder.optional(decimal_fact_decoder()),
    next,
  )
}

fn optional_trade_unit(
  name: String,
  next: fn(Option(TradeUnitValueInput)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(
    name,
    None,
    decoder.optional(trade_unit_decoder()),
    next,
  )
}
