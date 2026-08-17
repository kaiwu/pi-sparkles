import finance_core/decimal
import finance_core/time
import finance_indicators/atr
import finance_indicators/calculation
import finance_indicators/chart_handoff
import finance_indicators/input
import finance_indicators/model
import finance_indicators/receipt
import finance_indicators/rsi
import finance_indicators/sma
import finance_provenance/hash
import finance_provenance/identity
import finance_track
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pi_sparkles_stock_technicals/decode

const maximum_inputs = 2000

pub opaque type Response {
  Response(summary: String, details: Json, chart_handoff: chart_handoff.Handoff)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  OperationFailed(operation: String, reason: String)
}

type Projection {
  Compact(prior_offset: Int)
  Intermediate(prior_offset: Int)
}

type InstructionRefOrigin {
  CallerSuppliedInstructionRef
  DerivedFromCanonicalRequest
}

type FactCounts {
  FactCounts(
    known: Int,
    parseable_with_failed_checks: Int,
    unknown: Int,
    not_obtained: Int,
    conflicting: Int,
    decode_failure: Int,
  )
}

pub fn summary(value: Response) -> String {
  value.summary
}

/// Pi renders only the first content line by default, but sends every content
/// line to the LLM. Keep the first line concise for the user and place the
/// exact structured projection on the second line for model consumption.
pub fn model_content(value: Response) -> String {
  value.summary <> "\nMODEL_DATA " <> json.to_string(value.details)
}

pub fn details(value: Response) -> Json {
  value.details
}

pub fn chart_handoff(value: Response) -> chart_handoff.Handoff {
  value.chart_handoff
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid explicit stock-technicals field " <> field <> ": " <> reason
    OperationFailed(operation, reason) ->
      "Requested stock-technicals operation "
      <> operation
      <> " could not run: "
      <> reason
  }
}

pub fn run_sma(value: decode.SmaInput) -> Result(Response, DomainError) {
  use _ <- result.try(exact(
    "calculation.formulaVariant",
    value.formula_variant,
    "sma_v1",
  ))
  use _ <- result.try(exact(
    "calculation.windowVariant",
    value.window_variant,
    "slot_window_v1",
  ))
  use projection <- result.try(projection(value.projection))
  use slots <- result.try(price_slots(value.observations))
  use _ <- result.try(input_bound(list.length(slots)))
  let spec = model.SmaV1(value.period, model.SlotWindowV1)
  use request_value <- result.try(request(
    value.context,
    spec,
    value.parseable_policy,
    value.rounding,
    projection_offset(projection),
  ))
  let #(request, instruction_ref_origin) = request_value
  use calculated <- result.try(
    sma.calculate(request, slots)
    |> result.map_error(fn(error) {
      OperationFailed("sma_v1", string.inspect(error))
    }),
  )
  response(request, calculated, projection, instruction_ref_origin, [
    #("windowVariant", json.string("slot_window_v1")),
    #("seedVariant", json.string("not_applicable:non_recursive_formula")),
    #("gapPolicy", json.string("not_applicable:non_recursive_formula")),
  ])
}

pub fn run_rsi(value: decode.RsiInput) -> Result(Response, DomainError) {
  use _ <- result.try(exact(
    "calculation.formulaVariant",
    value.formula_variant,
    "rsi_wilder_v1",
  ))
  use _ <- result.try(exact(
    "calculation.windowVariant",
    value.window_variant,
    "slot_window_v1",
  ))
  use _ <- result.try(exact(
    "calculation.seedVariant",
    value.seed_variant,
    "seed_wilder_first_n",
  ))
  use _ <- result.try(exact(
    "calculation.gapPolicy",
    value.gap_policy,
    "stop_at_gap_v1",
  ))
  use _ <- result.try(exact(
    "calculation.zeroZeroConvention",
    value.zero_zero_convention,
    "zero_zero_unperformed_v1",
  ))
  use projection <- result.try(projection(value.projection))
  use slots <- result.try(price_slots(value.observations))
  use _ <- result.try(input_bound(list.length(slots)))
  let spec =
    model.WilderRsiV1(
      value.period,
      model.SlotWindowV1,
      model.StopAtGapV1,
      model.ZeroZeroUnperformedV1,
    )
  use request_value <- result.try(request(
    value.context,
    spec,
    value.parseable_policy,
    value.rounding,
    projection_offset(projection),
  ))
  let #(request, instruction_ref_origin) = request_value
  use calculated <- result.try(
    rsi.calculate(request, slots)
    |> result.map_error(fn(error) {
      OperationFailed("rsi_wilder_v1", string.inspect(error))
    }),
  )
  response(request, calculated, projection, instruction_ref_origin, [
    #("windowVariant", json.string("slot_window_v1")),
    #("seedVariant", json.string("seed_wilder_first_n")),
    #("gapPolicy", json.string("stop_at_gap_v1")),
    #("zeroZeroConvention", json.string("zero_zero_unperformed_v1")),
  ])
}

pub fn run_atr(value: decode.AtrInput) -> Result(Response, DomainError) {
  use _ <- result.try(exact(
    "calculation.formulaVariant",
    value.formula_variant,
    "atr_wilder_v1",
  ))
  use _ <- result.try(exact(
    "calculation.windowVariant",
    value.window_variant,
    "slot_window_v1",
  ))
  use _ <- result.try(exact(
    "calculation.seedVariant",
    value.seed_variant,
    "seed_wilder_tr_mean_v1",
  ))
  use _ <- result.try(exact(
    "calculation.firstTrueRange",
    value.first_true_range,
    "tr_first_hl_v1",
  ))
  use _ <- result.try(exact(
    "calculation.gapPolicy",
    value.gap_policy,
    "stop_at_gap_v1",
  ))
  use projection <- result.try(projection(value.projection))
  use slots <- result.try(bar_slots(value.bars))
  use _ <- result.try(input_bound(list.length(slots)))
  let spec =
    model.WilderAtrV1(value.period, model.SlotWindowV1, model.StopAtGapV1)
  use request_value <- result.try(request(
    value.context,
    spec,
    value.parseable_policy,
    value.rounding,
    projection_offset(projection),
  ))
  let #(request, instruction_ref_origin) = request_value
  use calculated <- result.try(
    atr.calculate(request, slots)
    |> result.map_error(fn(error) {
      OperationFailed("atr_wilder_v1", string.inspect(error))
    }),
  )
  response(request, calculated, projection, instruction_ref_origin, [
    #("windowVariant", json.string("slot_window_v1")),
    #("seedVariant", json.string("seed_wilder_tr_mean_v1")),
    #("firstTrueRange", json.string("tr_first_hl_v1")),
    #("gapPolicy", json.string("stop_at_gap_v1")),
  ])
}

fn request(
  context_input: decode.ContextInput,
  spec: model.CalculationSpec,
  parseable_input: String,
  rounding_input: decode.RoundingInput,
  prior_offset: Int,
) -> Result(#(model.Request, InstructionRefOrigin), DomainError) {
  use context <- result.try(context(context_input))
  use parseable <- result.try(parseable_policy(parseable_input))
  use rounding <- result.try(rounding(rounding_input))
  use instruction <- result.try(instruction_ref(
    context_input,
    spec,
    parseable_input,
    rounding_input,
    prior_offset,
  ))
  let #(instruction_ref, origin) = instruction
  model.request(instruction_ref, context, spec, parseable, rounding, [
    model.LatestValue,
    model.PriorValue(prior_offset),
  ])
  |> result.map(fn(value) { #(value, origin) })
  |> result.map_error(fn(error) {
    InvalidField("calculation", string.inspect(error))
  })
}

fn instruction_ref(
  context: decode.ContextInput,
  spec: model.CalculationSpec,
  parseable_policy: String,
  rounding: decode.RoundingInput,
  prior_offset: Int,
) -> Result(#(identity.Sha256, InstructionRefOrigin), DomainError) {
  case context.instruction_ref {
    Some(value) ->
      sha("context.instructionRef", value)
      |> result.map(fn(reference) { #(reference, CallerSuppliedInstructionRef) })
    None -> {
      let canonical =
        json.object([
          #("schema", json.string("pi-sparkles/derived-indicator-instruction")),
          #("schemaVersion", json.int(1)),
          #("track", json.string(context.track)),
          #("instrumentId", json.string(context.instrument_id)),
          #("mic", json.string(context.mic)),
          #("dateStart", json.string(context.date_start)),
          #("dateEnd", json.string(context.date_end)),
          #("provider", json.string(context.source.provider)),
          #("sourceReference", json.string(context.source.source_reference)),
          #(
            "acquisitionReceipt",
            json.string(context.source.acquisition_receipt),
          ),
          #("inputField", json.string(context.input_field)),
          #("calculationId", json.string(model.calculation_id(spec))),
          #("period", json.int(model.period(spec))),
          #("parseablePolicy", json.string(parseable_policy)),
          #("roundingMode", json.string(rounding.mode)),
          #("roundingPolicy", json.string(rounding.policy)),
          #("outputScale", json.int(rounding.output_scale)),
          #("intermediateScale", json.int(rounding.intermediate_scale)),
          #("priorOffset", json.int(prior_offset)),
        ])
        |> json.to_string
      hash.text(canonical)
      |> result.map(fn(reference) { #(reference, DerivedFromCanonicalRequest) })
      |> result.map_error(fn(error) {
        OperationFailed("instruction_ref", string.inspect(error))
      })
    }
  }
}

fn context(value: decode.ContextInput) -> Result(model.Context, DomainError) {
  use track <- result.try(track(value.track))
  use timezone <- result.try(
    time.timezone(value.timezone)
    |> result.map_error(fn(_) {
      InvalidField("context.timezone", "expected an explicit IANA timezone")
    }),
  )
  use date_start <- result.try(date("context.dateStart", value.date_start))
  use date_end <- result.try(date("context.dateEnd", value.date_end))
  use source <- result.try(source_leg(value.source))
  use cutoff <- result.try(optional_instant(
    "context.source.sourceCutoffUnixMilliseconds",
    value.source.source_cutoff_unix_ms,
  ))
  use unit <- result.try(unit(value.input_unit))
  use basis <- result.try(basis(value.basis))
  let context_root_inputs = case value.basis.kind {
    "raw" -> list.append(value.evidence_roots, value.basis.evidence_roots)
    _ -> value.evidence_roots
  }
  use roots <- result.try(evidence_roots(
    "context.evidenceRoots",
    list.unique(context_root_inputs),
  ))
  use _ <- result.try(text_list(
    "context.retainedAlternatives",
    value.retained_alternatives,
  ))
  use _ <- result.try(text_list("context.gapFacts", value.gap_facts))
  model.context(
    track,
    value.instrument_id,
    value.mic,
    timezone,
    date_start,
    date_end,
    source,
    cutoff,
    value.input_field,
    unit,
    basis,
    value.retained_alternatives,
    value.gap_facts,
    roots,
  )
  |> result.map_error(fn(error) {
    InvalidField("context", string.inspect(error))
  })
}

fn source_leg(
  value: decode.SourceInput,
) -> Result(model.SourceLeg, DomainError) {
  use acquisition <- result.try(sha(
    "context.source.acquisitionReceipt",
    value.acquisition_receipt,
  ))
  use retrieval <- result.try(instant(
    "context.source.retrievalTimeUnixMilliseconds",
    value.retrieval_time_unix_ms,
  ))
  model.source_leg(
    value.provider,
    value.source_reference,
    acquisition,
    retrieval,
  )
  |> result.map_error(fn(error) {
    InvalidField("context.source", string.inspect(error))
  })
}

fn unit(value: decode.UnitInput) -> Result(model.UnitFact, DomainError) {
  case value.state, value.label, value.reason {
    "known", Some(label), None -> Ok(model.KnownUnit(label))
    "unknown", None, Some(reason) -> Ok(model.UnknownUnit(reason))
    "known", _, _ ->
      Error(InvalidField(
        "context.inputUnit",
        "known requires label and forbids reason",
      ))
    "unknown", _, _ ->
      Error(InvalidField(
        "context.inputUnit",
        "unknown requires reason and forbids label",
      ))
    _, _, _ ->
      Error(InvalidField("context.inputUnit.state", "expected known or unknown"))
  }
}

fn basis(value: decode.BasisInput) -> Result(model.InputBasis, DomainError) {
  use roots <- result.try(evidence_roots(
    "context.basis.evidenceRoots",
    value.evidence_roots,
  ))
  case value.kind, value.label, value.instruction_ref {
    "raw", None, None -> Ok(model.Raw)
    "split_adjusted", None, None -> Ok(model.SplitAdjusted(roots))
    "dividend_adjusted", None, None -> Ok(model.DividendAdjusted(roots))
    "total_return", None, None -> Ok(model.TotalReturn(roots))
    "provider_defined", Some(label), None ->
      Ok(model.ProviderDefined(label, roots))
    "llm_projection", Some(label), Some(reference) -> {
      use instruction <- result.try(sha(
        "context.basis.instructionRef",
        reference,
      ))
      Ok(model.LlmProjection(label, instruction, roots))
    }
    "raw", _, _
    | "split_adjusted", _, _
    | "dividend_adjusted", _, _
    | "total_return", _, _
    ->
      Error(InvalidField(
        "context.basis",
        "this basis kind forbids label and instructionRef",
      ))
    "provider_defined", _, _ ->
      Error(InvalidField(
        "context.basis",
        "provider_defined requires label and forbids instructionRef",
      ))
    "llm_projection", _, _ ->
      Error(InvalidField(
        "context.basis",
        "llm_projection requires label and instructionRef",
      ))
    _, _, _ ->
      Error(InvalidField("context.basis.kind", "unsupported explicit basis"))
  }
}

fn parseable_policy(
  value: String,
) -> Result(model.ParseablePolicy, DomainError) {
  case value {
    "include_parseable_with_checks" -> Ok(model.IncludeParseableWithChecks)
    "exclude_parseable_with_checks" -> Ok(model.ExcludeParseableWithChecks)
    _ ->
      Error(InvalidField(
        "calculation.parseablePolicy",
        "expected include_parseable_with_checks or exclude_parseable_with_checks",
      ))
  }
}

fn rounding(
  value: decode.RoundingInput,
) -> Result(model.RoundingSpec, DomainError) {
  use _ <- result.try(exact(
    "calculation.rounding.policy",
    value.policy,
    "per_step",
  ))
  let mode = case value.mode {
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    "half_up" -> Ok(decimal.HalfUp)
    "half_even" -> Ok(decimal.HalfEven)
    _ ->
      Error(InvalidField(
        "calculation.rounding.mode",
        "expected toward_zero, away_from_zero, half_up, or half_even",
      ))
  }
  use mode <- result.try(mode)
  case
    value.output_scale >= 0
    && value.output_scale <= 30
    && value.intermediate_scale >= value.output_scale
    && value.intermediate_scale <= 30
  {
    True ->
      Ok(model.RoundingSpec(
        value.output_scale,
        mode,
        model.PerStep,
        value.intermediate_scale,
      ))
    False ->
      Error(InvalidField(
        "calculation.rounding",
        "scales must satisfy 0 <= outputScale <= intermediateScale <= 30",
      ))
  }
}

fn projection(
  value: decode.ProjectionInput,
) -> Result(Projection, DomainError) {
  case value.prior_offset >= 1 && value.prior_offset <= maximum_inputs {
    False ->
      Error(InvalidField(
        "projection.priorOffset",
        "expected an integer from 1 through 2000",
      ))
    True ->
      case value.kind {
        "compact" -> Ok(Compact(value.prior_offset))
        "intermediate" -> Ok(Intermediate(value.prior_offset))
        _ ->
          Error(InvalidField(
            "projection.kind",
            "expected compact or intermediate",
          ))
      }
  }
}

fn price_slots(
  values: List(decode.ObservationInput),
) -> Result(List(input.PriceSlot), DomainError) {
  list.try_map(values, fn(value) {
    use date <- result.try(date("observations[].date", value.date))
    use fact <- result.try(fact("observations[].value", value.value))
    Ok(input.PriceSlot(date, fact))
  })
}

fn bar_slots(
  values: List(decode.BarInput),
) -> Result(List(input.BarSlot), DomainError) {
  list.try_map(values, fn(value) {
    use date <- result.try(date("bars[].date", value.date))
    use high <- result.try(fact("bars[].high", value.high))
    use low <- result.try(fact("bars[].low", value.low))
    use close <- result.try(fact("bars[].close", value.close))
    Ok(input.BarSlot(date, high, low, close))
  })
}

fn fact(
  field: String,
  value: decode.FactInput,
) -> Result(input.NumericFact, DomainError) {
  case
    value.state,
    value.raw,
    value.reason,
    value.failed_checks,
    value.alternatives
  {
    "known", Some(raw), None, [], [] ->
      input.known(raw)
      |> result.map_error(fn(error) {
        InvalidField(field <> ".raw", string.inspect(error))
      })
    "parseable_with_failed_checks", Some(raw), None, checks, [] ->
      case checks {
        [] ->
          Error(InvalidField(
            field <> ".failedChecks",
            "parseable_with_failed_checks requires at least one named check",
          ))
        _ -> {
          use _ <- result.try(text_list(field <> ".failedChecks", checks))
          input.parseable_with_failed_checks(raw, checks)
          |> result.map_error(fn(error) {
            InvalidField(field <> ".raw", string.inspect(error))
          })
        }
      }
    "unknown", None, Some(reason), [], [] ->
      text(field <> ".reason", reason)
      |> result.map(fn(_) { input.Unknown(reason) })
    "not_obtained", None, Some(reason), [], [] ->
      text(field <> ".reason", reason)
      |> result.map(fn(_) { input.NotObtained(reason) })
    "decode_failure", Some(raw), Some(reason), [], [] -> {
      use _ <- result.try(text(field <> ".reason", reason))
      Ok(input.DecodeFailure(raw, reason))
    }
    "conflicting", None, None, [], alternatives -> {
      use values <- result.try(
        list.try_map(alternatives, fn(alternative) {
          use _ <- result.try(text(
            field <> ".alternatives[].sourceReference",
            alternative.source_reference,
          ))
          input.alternative(alternative.raw, alternative.source_reference)
          |> result.map_error(fn(error) {
            InvalidField(field <> ".alternatives[].raw", string.inspect(error))
          })
        }),
      )
      input.conflicting(values)
      |> result.map_error(fn(error) {
        InvalidField(field <> ".alternatives", string.inspect(error))
      })
    }
    _, _, _, _, _ ->
      Error(InvalidField(field, "fact fields do not match the explicit state"))
  }
}

fn response(
  request: model.Request,
  calculated: calculation.ResultData,
  projection: Projection,
  instruction_ref_origin: InstructionRefOrigin,
  explicit_policies: List(#(String, Json)),
) -> Result(Response, DomainError) {
  use request_receipt <- result.try(
    receipt.request_receipt(request)
    |> result.map_error(fn(error) {
      OperationFailed("request_receipt", string.inspect(error))
    }),
  )
  use semantic_receipt <- result.try(
    receipt.semantic_result_receipt(request, calculated)
    |> result.map_error(fn(error) {
      OperationFailed("semantic_result_receipt", string.inspect(error))
    }),
  )
  let calculated_outputs = calculation.calculated_outputs(calculated)
  let unperformed_outputs = calculation.unperformed_outputs(calculated)
  let counts = fact_counts(calculated.inputs)
  let context = model.request_context(request)
  let calculation_spec = model.calculation(request)
  let source_leg = model.context_source_leg(context)
  let source_series_receipt =
    model.acquisition_receipt(source_leg) |> identity.sha256_value
  let calculation_receipt =
    receipt.canonical_content_hash(semantic_receipt)
    |> identity.sha256_value
  let #(indicator_id, indicator_label, indicator_panel) =
    chart_identity(calculation_spec)
  use chart_binding <- result.try(
    chart_handoff.new(
      series_receipt: source_series_receipt,
      calculation_receipt: calculation_receipt,
      indicator_id: indicator_id,
      label: indicator_label,
      panel: indicator_panel,
      unit: chart_unit(calculation_spec, calculated.outputs, context),
      warmup_sessions: leading_unperformed(calculated.outputs),
      points: list.map(calculated.outputs, chart_point),
    )
    |> result.map_error(fn(error) {
      OperationFailed("chart_handoff", chart_handoff.error_message(error))
    }),
  )
  let projection_name = case projection {
    Compact(_) -> "compact"
    Intermediate(_) -> "intermediate"
  }
  let prior_offset = projection_offset(projection)
  let base_fields = [
    #("schema", json.string("pi-sparkles/stock-technicals-result")),
    #("schemaVersion", json.int(1)),
    #("projection", json.string(projection_name)),
    #("calculationId", json.string(calculated.calculation_id)),
    #("formulaVariant", json.string(calculated.formula_variant)),
    #("period", json.int(model.period(calculation_spec))),
    #("policies", json.object(explicit_policies)),
    #("track", json.string(finance_track.name(model.context_track(context)))),
    #("instrumentId", json.string(model.instrument_id(context))),
    #("mic", json.string(model.mic(context))),
    #("inputField", json.string(model.input_field(context))),
    #("inputUnit", unit_json(model.input_unit(context))),
    #("adjustmentBasis", basis_json(model.adjustment_basis(context))),
    #("evidenceRoots", roots_json(model.evidence_roots(context))),
    #(
      "instructionRef",
      model.instruction_ref(request) |> identity.sha256_value |> json.string,
    ),
    #(
      "instructionRefOrigin",
      json.string(instruction_ref_origin_name(instruction_ref_origin)),
    ),
    #(
      "requestReceiptHandle",
      receipt.canonical_content_hash(request_receipt)
        |> identity.sha256_value
        |> json.string,
    ),
    #("semanticReceiptHandle", json.string(calculation_receipt)),
    #("sourceSeriesReceipt", json.string(source_series_receipt)),
    #(
      "chartHandoffReceipt",
      chart_handoff.handoff_receipt(chart_binding) |> json.string,
    ),
    #(
      "counts",
      counts_json(
        counts,
        input_count(calculated.inputs),
        list.length(calculated_outputs),
        list.length(unperformed_outputs),
      ),
    ),
    #("firstCalculatedDate", first_date_json(calculated_outputs)),
    #("latestValue", offset_value_json(calculated_outputs, 0)),
    #("priorValue", offset_value_json(calculated_outputs, prior_offset)),
    #("priorOffset", json.int(prior_offset)),
    #(
      "priorOffsetRule",
      json.string("offset_over_calculated_outputs_newest_first"),
    ),
    #("availableOperations", json.array(available_operations(), json.string)),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], json.string)),
    #("limitations", json.array(limitations(), json.string)),
  ]
  let details = case projection {
    Compact(_) ->
      json.object(
        list.append(base_fields, [
          #(
            "receiptPayloads",
            json.object([
              #("state", json.string("omitted")),
              #(
                "reason",
                json.string(
                  "compact_projection_returns_content_hash_handles_without_duplicating_full_inputs_and_outputs",
                ),
              ),
            ]),
          ),
        ]),
      )
    Intermediate(_) ->
      json.object(
        list.append(base_fields, [
          #("requestReceiptJson", json.string(receipt.encode(request_receipt))),
          #(
            "semanticReceiptJson",
            json.string(receipt.encode(semantic_receipt)),
          ),
          #("orderedOutputs", json.array(calculated.outputs, output_json)),
        ]),
      )
  }
  let summary =
    finance_track.name(model.context_track(context))
    <> " | "
    <> model.instrument_id(context)
    <> " | "
    <> calculated.calculation_id
    <> "("
    <> int.to_string(model.period(calculation_spec))
    <> ") | "
    <> projection_name
    <> " | calculated "
    <> int.to_string(list.length(calculated_outputs))
    <> ", unperformed "
    <> int.to_string(list.length(unperformed_outputs))
    <> " | values and evidence only; interpretation belongs to the LLM"
  Ok(Response(summary, details, chart_binding))
}

fn chart_identity(spec: model.CalculationSpec) -> #(String, String, String) {
  let period = model.period(spec)
  case spec {
    model.SmaV1(_, _) -> #(
      "sma_" <> int.to_string(period),
      "SMA " <> int.to_string(period),
      "price_overlay",
    )
    model.WilderRsiV1(_, _, _, _) -> #(
      "rsi_" <> int.to_string(period),
      "RSI " <> int.to_string(period),
      "lower_panel",
    )
    model.WilderAtrV1(_, _, _) -> #(
      "atr_" <> int.to_string(period),
      "ATR " <> int.to_string(period),
      "lower_panel",
    )
  }
}

fn chart_unit(
  spec: model.CalculationSpec,
  outputs: List(calculation.Output),
  context: model.Context,
) -> String {
  case first_calculated_unit(outputs) {
    Some(value) -> value
    None ->
      case spec, model.input_unit(context) {
        model.WilderRsiV1(_, _, _, _), _ -> "ratio_0_100"
        _, model.KnownUnit(value) -> value
        _, model.UnknownUnit(_) -> "unknown_unit"
      }
  }
}

fn first_calculated_unit(outputs: List(calculation.Output)) -> Option(String) {
  case outputs {
    [] -> None
    [calculation.Calculated(_, _, unit, _), ..] -> Some(unit)
    [_, ..rest] -> first_calculated_unit(rest)
  }
}

fn leading_unperformed(outputs: List(calculation.Output)) -> Int {
  leading_unperformed_loop(outputs, 0)
}

fn leading_unperformed_loop(
  outputs: List(calculation.Output),
  count: Int,
) -> Int {
  case outputs {
    [calculation.Unperformed(_, _, _), ..rest] ->
      leading_unperformed_loop(rest, count + 1)
    _ -> count
  }
}

fn chart_point(value: calculation.Output) -> chart_handoff.Point {
  case value {
    calculation.Calculated(date, value, _, _) ->
      chart_handoff.Calculated(date_text(date), value)
    calculation.Unperformed(date, reason, _) ->
      chart_handoff.Unperformed(date_text(date), unperformed_text(reason))
  }
}

fn unperformed_text(value: calculation.UnperformedReason) -> String {
  case value {
    calculation.InsufficientInputs(available, required) ->
      "insufficient_inputs:available="
      <> int.to_string(available)
      <> ":required="
      <> int.to_string(required)
    calculation.InputUnavailable(details) ->
      "input_unavailable:" <> string.join(details, with: ",")
    calculation.StoppedAfterGap(reason) -> "stopped_after_gap:" <> reason
    calculation.ZeroGainAndLoss -> "zero_gain_and_loss"
  }
}

fn instruction_ref_origin_name(value: InstructionRefOrigin) -> String {
  case value {
    CallerSuppliedInstructionRef -> "caller_supplied"
    DerivedFromCanonicalRequest -> "derived_from_canonical_request"
  }
}

fn output_json(value: calculation.Output) -> Json {
  case value {
    calculation.Calculated(date, value, unit, intermediates) ->
      json.object([
        #("state", json.string("calculated")),
        #("date", json.string(date_text(date))),
        #("value", json.string(value)),
        #("unit", json.string(unit)),
        #(
          "intermediateValues",
          json.array(intermediates, fn(item) {
            json.object([
              #("name", json.string(item.name)),
              #("value", json.string(item.value)),
            ])
          }),
        ),
      ])
    calculation.Unperformed(date, reason, operands) ->
      json.object([
        #("state", json.string("unperformed")),
        #("date", json.string(date_text(date))),
        #("reason", unperformed_json(reason)),
        #("operands", json.array(operands, json.string)),
      ])
  }
}

fn unperformed_json(value: calculation.UnperformedReason) -> Json {
  case value {
    calculation.InsufficientInputs(available, required) ->
      json.object([
        #("kind", json.string("insufficient_inputs")),
        #("available", json.int(available)),
        #("required", json.int(required)),
      ])
    calculation.InputUnavailable(details) ->
      json.object([
        #("kind", json.string("input_unavailable")),
        #("details", json.array(details, json.string)),
      ])
    calculation.StoppedAfterGap(reason) ->
      json.object([
        #("kind", json.string("stopped_after_gap")),
        #("reason", json.string(reason)),
      ])
    calculation.ZeroGainAndLoss ->
      json.object([#("kind", json.string("zero_gain_and_loss"))])
  }
}

fn offset_value_json(values: List(calculation.Output), offset: Int) -> Json {
  let newest_first = list.reverse(values)
  case list.drop(newest_first, offset) {
    [value, ..] ->
      json.object([
        #("state", json.string("known")),
        #("output", output_json(value)),
      ])
    [] ->
      json.object([
        #("state", json.string("not_applicable")),
        #("reason", json.string("no_calculated_output_at_requested_offset")),
      ])
  }
}

fn first_date_json(values: List(calculation.Output)) -> Json {
  case values {
    [calculation.Calculated(date, _, _, _), ..] ->
      json.object([
        #("state", json.string("known")),
        #("date", json.string(date_text(date))),
      ])
    _ ->
      json.object([
        #("state", json.string("not_applicable")),
        #("reason", json.string("no_calculated_output_exists")),
      ])
  }
}

fn fact_counts(value: input.InputSnapshot) -> FactCounts {
  input_facts(value)
  |> list.fold(FactCounts(0, 0, 0, 0, 0, 0), fn(counts, fact) {
    case fact {
      input.Known(_, _) -> FactCounts(..counts, known: counts.known + 1)
      input.ParseableWithFailedChecks(_, _, _) ->
        FactCounts(
          ..counts,
          parseable_with_failed_checks: counts.parseable_with_failed_checks + 1,
        )
      input.Unknown(_) -> FactCounts(..counts, unknown: counts.unknown + 1)
      input.NotObtained(_) ->
        FactCounts(..counts, not_obtained: counts.not_obtained + 1)
      input.Conflicting(_) ->
        FactCounts(..counts, conflicting: counts.conflicting + 1)
      input.DecodeFailure(_, _) ->
        FactCounts(..counts, decode_failure: counts.decode_failure + 1)
    }
  })
}

fn input_facts(value: input.InputSnapshot) -> List(input.NumericFact) {
  case value {
    input.PriceInputs(slots) -> list.map(slots, fn(slot) { slot.value })
    input.BarInputs(slots) ->
      list.flat_map(slots, fn(slot) { [slot.high, slot.low, slot.close] })
  }
}

fn input_count(value: input.InputSnapshot) -> Int {
  case value {
    input.PriceInputs(slots) -> list.length(slots)
    input.BarInputs(slots) -> list.length(slots)
  }
}

fn counts_json(
  counts: FactCounts,
  inputs: Int,
  calculated: Int,
  unperformed: Int,
) -> Json {
  json.object([
    #("inputObservations", json.int(inputs)),
    #("calculatedOutputs", json.int(calculated)),
    #("unperformedOutputs", json.int(unperformed)),
    #("knownFacts", json.int(counts.known)),
    #(
      "parseableWithFailedChecks",
      json.int(counts.parseable_with_failed_checks),
    ),
    #("unknownFacts", json.int(counts.unknown)),
    #("notObtainedFacts", json.int(counts.not_obtained)),
    #("conflictingFacts", json.int(counts.conflicting)),
    #("decodeFailures", json.int(counts.decode_failure)),
  ])
}

fn unit_json(value: model.UnitFact) -> Json {
  case value {
    model.KnownUnit(label) ->
      json.object([
        #("state", json.string("known")),
        #("label", json.string(label)),
      ])
    model.UnknownUnit(reason) ->
      json.object([
        #("state", json.string("unknown")),
        #("reason", json.string(reason)),
      ])
  }
}

fn basis_json(value: model.InputBasis) -> Json {
  case value {
    model.Raw -> json.object([#("kind", json.string("raw"))])
    model.SplitAdjusted(roots) -> basis_roots("split_adjusted", roots)
    model.DividendAdjusted(roots) -> basis_roots("dividend_adjusted", roots)
    model.TotalReturn(roots) -> basis_roots("total_return", roots)
    model.ProviderDefined(label, roots) ->
      json.object([
        #("kind", json.string("provider_defined")),
        #("label", json.string(label)),
        #("evidenceRoots", roots_json(roots)),
      ])
    model.LlmProjection(label, instruction, roots) ->
      json.object([
        #("kind", json.string("llm_projection")),
        #("label", json.string(label)),
        #("instructionRef", instruction |> identity.sha256_value |> json.string),
        #("evidenceRoots", roots_json(roots)),
      ])
  }
}

fn basis_roots(kind: String, roots: List(identity.EvidenceId)) -> Json {
  json.object([
    #("kind", json.string(kind)),
    #("evidenceRoots", roots_json(roots)),
  ])
}

fn roots_json(values: List(identity.EvidenceId)) -> Json {
  json.array(values, fn(value) {
    value |> identity.evidence_id_value |> json.string
  })
}

fn available_operations() -> List(String) {
  [
    "repeat_with_projection:compact",
    "repeat_with_projection:intermediate",
    "repeat_with_explicit_period",
    "repeat_with_explicit_rounding",
    "repeat_with_explicit_input_basis",
  ]
}

fn limitations() -> List(String) {
  [
    "calculation_uses_only_caller_supplied_exact_observations",
    "content_hash_proves_reproduction_not_source_correctness_or_origin_authentication",
    "unknown_conflicting_and_failed_check_facts_are_information_for_the_llm",
    "no_provider_selection_fetch_imputation_interpretation_signal_rank_or_trade_decision",
    "first_slice_supports_only_sma_v1_rsi_wilder_v1_and_atr_wilder_v1",
  ]
}

fn projection_offset(value: Projection) -> Int {
  case value {
    Compact(offset) | Intermediate(offset) -> offset
  }
}

fn input_bound(count: Int) -> Result(Nil, DomainError) {
  case count >= 1 && count <= maximum_inputs {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "observations",
        "expected between 1 and 2000 exact observations",
      ))
  }
}

fn exact(
  field: String,
  received: String,
  expected: String,
) -> Result(Nil, DomainError) {
  case received == expected {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "first slice requires " <> expected))
  }
}

fn track(value: String) -> Result(finance_track.Track, DomainError) {
  case value {
    "cn" -> Ok(finance_track.Cn)
    "hk" -> Ok(finance_track.Hk)
    "us" -> Ok(finance_track.Us)
    _ -> Error(InvalidField("context.track", "expected cn, hk, or us"))
  }
}

fn date(field: String, value: String) -> Result(time.Date, DomainError) {
  case string.split(value, "-") {
    [year, month, day] -> {
      use year <- result.try(parsed_int(field, year))
      use month <- result.try(parsed_int(field, month))
      use day <- result.try(parsed_int(field, day))
      time.date(year, month, day)
      |> result.map_error(fn(_) {
        InvalidField(field, "expected a valid YYYY-MM-DD date")
      })
    }
    _ -> Error(InvalidField(field, "expected a valid YYYY-MM-DD date"))
  }
}

fn parsed_int(field: String, value: String) -> Result(Int, DomainError) {
  int.parse(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "expected a valid YYYY-MM-DD date")
  })
}

fn date_text(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn instant(field: String, value: Int) -> Result(time.Instant, DomainError) {
  time.instant(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "instant is outside the supported range")
  })
}

fn optional_instant(
  field: String,
  value: Option(Int),
) -> Result(Option(time.Instant), DomainError) {
  case value {
    None -> Ok(None)
    Some(value) -> instant(field, value) |> result.map(Some)
  }
}

fn sha(field: String, value: String) -> Result(identity.Sha256, DomainError) {
  identity.sha256(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "expected exactly 64 hexadecimal SHA-256 characters")
  })
}

fn evidence_roots(
  field: String,
  values: List(String),
) -> Result(List(identity.EvidenceId), DomainError) {
  list.try_map(values, fn(value) {
    sha(field <> "[]", value) |> result.map(identity.evidence_id)
  })
}

fn text_list(field: String, values: List(String)) -> Result(Nil, DomainError) {
  list.try_each(values, fn(value) { text(field <> "[]", value) })
}

fn text(field: String, value: String) -> Result(Nil, DomainError) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "expected non-empty trimmed text"))
  }
}
