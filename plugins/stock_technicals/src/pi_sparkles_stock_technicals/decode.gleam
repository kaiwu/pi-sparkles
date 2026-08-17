import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None, Some}

pub type AlternativeInput {
  AlternativeInput(raw: String, source_reference: String)
}

pub type FactInput {
  FactInput(
    state: String,
    raw: Option(String),
    reason: Option(String),
    failed_checks: List(String),
    alternatives: List(AlternativeInput),
  )
}

pub type UnitInput {
  UnitInput(state: String, label: Option(String), reason: Option(String))
}

pub type BasisInput {
  BasisInput(
    kind: String,
    label: Option(String),
    instruction_ref: Option(String),
    evidence_roots: List(String),
  )
}

pub type SourceInput {
  SourceInput(
    provider: String,
    source_reference: String,
    acquisition_receipt: String,
    retrieval_time_unix_ms: Int,
    source_cutoff_unix_ms: Option(Int),
  )
}

pub type ContextInput {
  ContextInput(
    instruction_ref: Option(String),
    track: String,
    instrument_id: String,
    mic: String,
    timezone: String,
    date_start: String,
    date_end: String,
    source: SourceInput,
    input_field: String,
    input_unit: UnitInput,
    basis: BasisInput,
    retained_alternatives: List(String),
    gap_facts: List(String),
    evidence_roots: List(String),
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

pub type ProjectionInput {
  ProjectionInput(kind: String, prior_offset: Int)
}

pub type ObservationInput {
  ObservationInput(date: String, value: FactInput)
}

pub type BarInput {
  BarInput(date: String, high: FactInput, low: FactInput, close: FactInput)
}

pub type SmaInput {
  SmaInput(
    context: ContextInput,
    formula_variant: String,
    period: Int,
    window_variant: String,
    parseable_policy: String,
    rounding: RoundingInput,
    projection: ProjectionInput,
    observations: List(ObservationInput),
  )
}

pub type SmaRequest {
  DirectSma(SmaInput)
  ReceiptSma(
    series_receipt: String,
    formula_variant: String,
    period: Int,
    window_variant: String,
    parseable_policy: String,
    rounding: RoundingInput,
    projection: ProjectionInput,
  )
}

pub type RsiInput {
  RsiInput(
    context: ContextInput,
    formula_variant: String,
    period: Int,
    window_variant: String,
    seed_variant: String,
    gap_policy: String,
    zero_zero_convention: String,
    parseable_policy: String,
    rounding: RoundingInput,
    projection: ProjectionInput,
    observations: List(ObservationInput),
  )
}

pub type RsiRequest {
  DirectRsi(RsiInput)
  ReceiptRsi(
    series_receipt: String,
    formula_variant: String,
    period: Int,
    window_variant: String,
    seed_variant: String,
    gap_policy: String,
    zero_zero_convention: String,
    parseable_policy: String,
    rounding: RoundingInput,
    projection: ProjectionInput,
  )
}

pub type AtrInput {
  AtrInput(
    context: ContextInput,
    formula_variant: String,
    period: Int,
    window_variant: String,
    seed_variant: String,
    first_true_range: String,
    gap_policy: String,
    parseable_policy: String,
    rounding: RoundingInput,
    projection: ProjectionInput,
    bars: List(BarInput),
  )
}

pub type AtrRequest {
  DirectAtr(AtrInput)
  ReceiptAtr(
    series_receipt: String,
    formula_variant: String,
    period: Int,
    window_variant: String,
    seed_variant: String,
    first_true_range: String,
    gap_policy: String,
    parseable_policy: String,
    rounding: RoundingInput,
    projection: ProjectionInput,
  )
}

pub fn sma() -> decoder.Decoder(SmaRequest) {
  use context <- optional_context()
  use series_receipt <- optional_string("seriesReceipt")
  use calculation <- decoder.field("calculation", sma_calculation_decoder())
  use projection <- decoder.field("projection", projection_decoder())
  use observations <- decoder.optional_field(
    "observations",
    None,
    decoder.optional(decoder.list(of: observation_decoder())),
  )
  let #(formula, period, window, parseable, rounding) = calculation
  case context, series_receipt, observations {
    Some(context), None, Some(observations) ->
      decoder.success(
        DirectSma(SmaInput(
          context,
          formula,
          period,
          window,
          parseable,
          rounding,
          projection,
          observations,
        )),
      )
    None, Some(receipt), None ->
      decoder.success(ReceiptSma(
        receipt,
        formula,
        period,
        window,
        parseable,
        rounding,
        projection,
      ))
    _, _, _ ->
      decoder.failure(
        ReceiptSma("", formula, period, window, parseable, rounding, projection),
        "exactly one of seriesReceipt or context plus observations",
      )
  }
}

pub fn rsi() -> decoder.Decoder(RsiRequest) {
  use context <- optional_context()
  use series_receipt <- optional_string("seriesReceipt")
  use calculation <- decoder.field("calculation", rsi_calculation_decoder())
  use projection <- decoder.field("projection", projection_decoder())
  use observations <- decoder.optional_field(
    "observations",
    None,
    decoder.optional(decoder.list(of: observation_decoder())),
  )
  let #(formula, period, window, seed, gap, zero_zero, parseable, rounding) =
    calculation
  case context, series_receipt, observations {
    Some(context), None, Some(observations) ->
      decoder.success(
        DirectRsi(RsiInput(
          context,
          formula,
          period,
          window,
          seed,
          gap,
          zero_zero,
          parseable,
          rounding,
          projection,
          observations,
        )),
      )
    None, Some(receipt), None ->
      decoder.success(ReceiptRsi(
        receipt,
        formula,
        period,
        window,
        seed,
        gap,
        zero_zero,
        parseable,
        rounding,
        projection,
      ))
    _, _, _ ->
      decoder.failure(
        ReceiptRsi(
          "",
          formula,
          period,
          window,
          seed,
          gap,
          zero_zero,
          parseable,
          rounding,
          projection,
        ),
        "exactly one of seriesReceipt or context plus observations",
      )
  }
}

pub fn atr() -> decoder.Decoder(AtrRequest) {
  use context <- optional_context()
  use series_receipt <- optional_string("seriesReceipt")
  use calculation <- decoder.field("calculation", atr_calculation_decoder())
  use projection <- decoder.field("projection", projection_decoder())
  use bars <- decoder.optional_field(
    "bars",
    None,
    decoder.optional(decoder.list(of: bar_decoder())),
  )
  let #(formula, period, window, seed, first_tr, gap, parseable, rounding) =
    calculation
  case context, series_receipt, bars {
    Some(context), None, Some(bars) ->
      decoder.success(
        DirectAtr(AtrInput(
          context,
          formula,
          period,
          window,
          seed,
          first_tr,
          gap,
          parseable,
          rounding,
          projection,
          bars,
        )),
      )
    None, Some(receipt), None ->
      decoder.success(ReceiptAtr(
        receipt,
        formula,
        period,
        window,
        seed,
        first_tr,
        gap,
        parseable,
        rounding,
        projection,
      ))
    _, _, _ ->
      decoder.failure(
        ReceiptAtr(
          "",
          formula,
          period,
          window,
          seed,
          first_tr,
          gap,
          parseable,
          rounding,
          projection,
        ),
        "exactly one of seriesReceipt or context plus bars",
      )
  }
}

fn optional_context(
  next: fn(Option(ContextInput)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(
    "context",
    None,
    decoder.optional(context_decoder()),
    next,
  )
}

fn context_decoder() -> decoder.Decoder(ContextInput) {
  use instruction_ref <- optional_string("instructionRef")
  use track <- decoder.field("track", decoder.string)
  use instrument_id <- decoder.field("instrumentId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use timezone <- decoder.field("timezone", decoder.string)
  use date_start <- decoder.field("dateStart", decoder.string)
  use date_end <- decoder.field("dateEnd", decoder.string)
  use source <- decoder.field("source", source_decoder())
  use input_field <- decoder.field("inputField", decoder.string)
  use input_unit <- decoder.field("inputUnit", unit_decoder())
  use basis <- decoder.field("basis", basis_decoder())
  use retained_alternatives <- decoder.field(
    "retainedAlternatives",
    decoder.list(of: decoder.string),
  )
  use gap_facts <- decoder.field("gapFacts", decoder.list(of: decoder.string))
  use evidence_roots <- decoder.field(
    "evidenceRoots",
    decoder.list(of: decoder.string),
  )
  decoder.success(ContextInput(
    instruction_ref,
    track,
    instrument_id,
    mic,
    timezone,
    date_start,
    date_end,
    source,
    input_field,
    input_unit,
    basis,
    retained_alternatives,
    gap_facts,
    evidence_roots,
  ))
}

fn source_decoder() -> decoder.Decoder(SourceInput) {
  use provider <- decoder.field("provider", decoder.string)
  use source_reference <- decoder.field("sourceReference", decoder.string)
  use acquisition_receipt <- decoder.field("acquisitionReceipt", decoder.string)
  use retrieval <- decoder.field("retrievalTimeUnixMilliseconds", decoder.int)
  use cutoff <- decoder.optional_field(
    "sourceCutoffUnixMilliseconds",
    None,
    decoder.optional(decoder.int),
  )
  decoder.success(SourceInput(
    provider,
    source_reference,
    acquisition_receipt,
    retrieval,
    cutoff,
  ))
}

fn unit_decoder() -> decoder.Decoder(UnitInput) {
  use state <- decoder.field("state", decoder.string)
  use label <- optional_string("label")
  use reason <- optional_string("reason")
  decoder.success(UnitInput(state, label, reason))
}

fn basis_decoder() -> decoder.Decoder(BasisInput) {
  use kind <- decoder.field("kind", decoder.string)
  use label <- optional_string("label")
  use instruction_ref <- optional_string("instructionRef")
  use evidence_roots <- decoder.field(
    "evidenceRoots",
    decoder.list(of: decoder.string),
  )
  decoder.success(BasisInput(kind, label, instruction_ref, evidence_roots))
}

fn rounding_decoder() -> decoder.Decoder(RoundingInput) {
  use mode <- decoder.field("mode", decoder.string)
  use policy <- decoder.field("policy", decoder.string)
  use output_scale <- decoder.field("outputScale", decoder.int)
  use intermediate_scale <- decoder.field("intermediateScale", decoder.int)
  decoder.success(RoundingInput(mode, policy, output_scale, intermediate_scale))
}

fn projection_decoder() -> decoder.Decoder(ProjectionInput) {
  use kind <- decoder.field("kind", decoder.string)
  use prior_offset <- decoder.field("priorOffset", decoder.int)
  decoder.success(ProjectionInput(kind, prior_offset))
}

fn observation_decoder() -> decoder.Decoder(ObservationInput) {
  use date <- decoder.field("date", decoder.string)
  use value <- decoder.field("value", fact_decoder())
  decoder.success(ObservationInput(date, value))
}

fn bar_decoder() -> decoder.Decoder(BarInput) {
  use date <- decoder.field("date", decoder.string)
  use high <- decoder.field("high", fact_decoder())
  use low <- decoder.field("low", fact_decoder())
  use close <- decoder.field("close", fact_decoder())
  decoder.success(BarInput(date, high, low, close))
}

fn fact_decoder() -> decoder.Decoder(FactInput) {
  use state <- decoder.field("state", decoder.string)
  use raw <- optional_string("raw")
  use reason <- optional_string("reason")
  use failed_checks <- decoder.optional_field(
    "failedChecks",
    [],
    decoder.list(of: decoder.string),
  )
  use alternatives <- decoder.optional_field(
    "alternatives",
    [],
    decoder.list(of: alternative_decoder()),
  )
  decoder.success(FactInput(state, raw, reason, failed_checks, alternatives))
}

fn alternative_decoder() -> decoder.Decoder(AlternativeInput) {
  use raw <- decoder.field("raw", decoder.string)
  use source_reference <- decoder.field("sourceReference", decoder.string)
  decoder.success(AlternativeInput(raw, source_reference))
}

fn sma_calculation_decoder() -> decoder.Decoder(
  #(String, Int, String, String, RoundingInput),
) {
  use formula <- decoder.field("formulaVariant", decoder.string)
  use period <- decoder.field("period", decoder.int)
  use window <- decoder.field("windowVariant", decoder.string)
  use parseable <- decoder.field("parseablePolicy", decoder.string)
  use rounding <- decoder.field("rounding", rounding_decoder())
  use policy <- optional_string("policy")
  use output_scale <- optional_int("outputScale")
  use intermediate_scale <- optional_int("intermediateScale")
  let decoded = #(formula, period, window, parseable, rounding)
  case
    rounding_aliases_match(rounding, policy, output_scale, intermediate_scale)
  {
    True -> decoder.success(decoded)
    False -> decoder.failure(decoded, "rounding aliases must match rounding")
  }
}

fn rsi_calculation_decoder() -> decoder.Decoder(
  #(String, Int, String, String, String, String, String, RoundingInput),
) {
  use formula <- decoder.field("formulaVariant", decoder.string)
  use period <- decoder.field("period", decoder.int)
  use window <- decoder.field("windowVariant", decoder.string)
  use seed <- decoder.field("seedVariant", decoder.string)
  use gap <- decoder.field("gapPolicy", decoder.string)
  use zero_zero <- decoder.field("zeroZeroConvention", decoder.string)
  use parseable <- decoder.field("parseablePolicy", decoder.string)
  use rounding <- decoder.field("rounding", rounding_decoder())
  use policy <- optional_string("policy")
  use output_scale <- optional_int("outputScale")
  use intermediate_scale <- optional_int("intermediateScale")
  let decoded = #(
    formula,
    period,
    window,
    seed,
    gap,
    zero_zero,
    parseable,
    rounding,
  )
  case
    rounding_aliases_match(rounding, policy, output_scale, intermediate_scale)
  {
    True -> decoder.success(decoded)
    False -> decoder.failure(decoded, "rounding aliases must match rounding")
  }
}

fn atr_calculation_decoder() -> decoder.Decoder(
  #(String, Int, String, String, String, String, String, RoundingInput),
) {
  use formula <- decoder.field("formulaVariant", decoder.string)
  use period <- decoder.field("period", decoder.int)
  use window <- decoder.field("windowVariant", decoder.string)
  use seed <- decoder.field("seedVariant", decoder.string)
  use first_tr <- decoder.field("firstTrueRange", decoder.string)
  use gap <- decoder.field("gapPolicy", decoder.string)
  use parseable <- decoder.field("parseablePolicy", decoder.string)
  use rounding <- decoder.field("rounding", rounding_decoder())
  use policy <- optional_string("policy")
  use output_scale <- optional_int("outputScale")
  use intermediate_scale <- optional_int("intermediateScale")
  let decoded = #(
    formula,
    period,
    window,
    seed,
    first_tr,
    gap,
    parseable,
    rounding,
  )
  case
    rounding_aliases_match(rounding, policy, output_scale, intermediate_scale)
  {
    True -> decoder.success(decoded)
    False -> decoder.failure(decoded, "rounding aliases must match rounding")
  }
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

fn rounding_aliases_match(
  rounding: RoundingInput,
  policy: Option(String),
  output_scale: Option(Int),
  intermediate_scale: Option(Int),
) -> Bool {
  let RoundingInput(
    mode: _,
    policy: nested_policy,
    output_scale: nested_output_scale,
    intermediate_scale: nested_intermediate_scale,
  ) = rounding

  case policy, output_scale, intermediate_scale {
    Some(alias), _, _ if alias != nested_policy -> False
    _, Some(alias), _ if alias != nested_output_scale -> False
    _, _, Some(alias) if alias != nested_intermediate_scale -> False
    _, _, _ -> True
  }
}
