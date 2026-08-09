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

pub type AccountInput {
  AccountInput(
    account_id: String,
    net_liquidation_value: DecimalFactInput,
    cash_balance: Option(DecimalFactInput),
    liabilities: Option(DecimalFactInput),
    account_currency: String,
    as_of_unix_ms: Int,
    source_kind: String,
    source_receipt: String,
  )
}

pub type PositionInput {
  PositionInput(
    position_id: String,
    listing_id: String,
    mic: String,
    track: String,
    direction: String,
    quantity: DecimalFactInput,
    quantity_unit: String,
    lot_size: Option(DecimalFactInput),
    current_mark: DecimalFactInput,
    mark_time_unix_ms: Option(Int),
    cost_basis: Option(DecimalFactInput),
    desired_stop: DecimalFactInput,
    stop_time_unix_ms: Option(Int),
    entry_price: Option(DecimalFactInput),
    position_currency: String,
    as_of_unix_ms: Int,
  )
}

pub type HeatDenominatorInput {
  HeatDenominatorInput(kind: String, caller_capital: Option(DecimalFactInput))
}

pub type CalculationInput {
  CalculationInput(
    information_policy: String,
    max_staleness_seconds: Option(Int),
    heat_variant: String,
    heat_denominator: Option(HeatDenominatorInput),
    position_weight_format: String,
    rounding_mode: String,
    currency_scale: Int,
    weight_scale: Int,
    percentage_scale: Int,
    intermediate_scale: Int,
  )
}

pub type Input {
  Input(
    portfolio_id: String,
    instruction_ref: String,
    account: AccountInput,
    positions: List(PositionInput),
    calculation: CalculationInput,
    requested_summary_fields: List(String),
    projection: String,
  )
}

pub fn portfolio_risk() -> decoder.Decoder(Input) {
  use portfolio_id <- decoder.field("portfolioId", decoder.string)
  use instruction_ref <- decoder.field("instructionRef", decoder.string)
  use account <- decoder.field("account", account_decoder())
  use positions <- decoder.field(
    "positions",
    decoder.list(of: position_decoder()),
  )
  use calculation <- decoder.field("calculation", calculation_decoder())
  use fields <- decoder.field(
    "requestedSummaryFields",
    decoder.list(of: decoder.string),
  )
  use projection <- decoder.field("projection", decoder.string)
  decoder.success(Input(
    portfolio_id,
    instruction_ref,
    account,
    positions,
    calculation,
    fields,
    projection,
  ))
}

fn account_decoder() -> decoder.Decoder(AccountInput) {
  use account_id <- decoder.field("accountId", decoder.string)
  use nlv <- decoder.field("netLiquidationValue", decimal_fact_decoder())
  use cash <- optional_decimal_fact("cashBalance")
  use liabilities <- optional_decimal_fact("liabilities")
  use currency <- decoder.field("accountCurrency", decoder.string)
  use as_of <- decoder.field("asOfUnixMilliseconds", decoder.int)
  use source_kind <- decoder.field("sourceKind", decoder.string)
  use source_receipt <- decoder.field("sourceReceipt", decoder.string)
  decoder.success(AccountInput(
    account_id,
    nlv,
    cash,
    liabilities,
    currency,
    as_of,
    source_kind,
    source_receipt,
  ))
}

fn position_decoder() -> decoder.Decoder(PositionInput) {
  use position_id <- decoder.field("positionId", decoder.string)
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use direction <- decoder.field("direction", decoder.string)
  use quantity <- decoder.field("quantity", decimal_fact_decoder())
  use quantity_unit <- decoder.field("quantityUnit", decoder.string)
  use lot_size <- optional_decimal_fact("lotSize")
  use mark <- decoder.field("currentMark", decimal_fact_decoder())
  use mark_time <- optional_int("markTimeUnixMilliseconds")
  use cost_basis <- optional_decimal_fact("costBasis")
  use stop <- decoder.field("desiredStop", decimal_fact_decoder())
  use stop_time <- optional_int("stopTimeUnixMilliseconds")
  use entry_price <- optional_decimal_fact("entryPrice")
  use currency <- decoder.field("positionCurrency", decoder.string)
  use as_of <- decoder.field("asOfUnixMilliseconds", decoder.int)
  decoder.success(PositionInput(
    position_id,
    listing_id,
    mic,
    track,
    direction,
    quantity,
    quantity_unit,
    lot_size,
    mark,
    mark_time,
    cost_basis,
    stop,
    stop_time,
    entry_price,
    currency,
    as_of,
  ))
}

fn calculation_decoder() -> decoder.Decoder(CalculationInput) {
  use information_policy <- decoder.field("informationPolicy", decoder.string)
  use cutoff <- optional_int("maxStalenessSeconds")
  use heat_variant <- decoder.field("heatVariant", decoder.string)
  use denominator <- optional_heat_denominator("heatDenominator")
  use weight_format <- decoder.field("positionWeightFormat", decoder.string)
  use rounding <- decoder.field("roundingMode", decoder.string)
  use currency_scale <- decoder.field("currencyScale", decoder.int)
  use weight_scale <- decoder.field("weightScale", decoder.int)
  use percentage_scale <- decoder.field("percentageScale", decoder.int)
  use intermediate_scale <- decoder.field("intermediateScale", decoder.int)
  decoder.success(CalculationInput(
    information_policy,
    cutoff,
    heat_variant,
    denominator,
    weight_format,
    rounding,
    currency_scale,
    weight_scale,
    percentage_scale,
    intermediate_scale,
  ))
}

fn heat_denominator_decoder() -> decoder.Decoder(HeatDenominatorInput) {
  use kind <- decoder.field("kind", decoder.string)
  use caller_capital <- optional_decimal_fact("callerCapital")
  decoder.success(HeatDenominatorInput(kind, caller_capital))
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

fn optional_int(
  name: String,
  next: fn(Option(Int)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.int), next)
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

fn optional_heat_denominator(
  name: String,
  next: fn(Option(HeatDenominatorInput)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(
    name,
    None,
    decoder.optional(heat_denominator_decoder()),
    next,
  )
}
