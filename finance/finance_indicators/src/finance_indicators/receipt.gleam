import finance_core/decimal
import finance_core/time.{type Date, type Instant}
import finance_indicators/calculation.{type Output, type ResultData}
import finance_indicators/input.{type InputSnapshot, type NumericFact}
import finance_indicators/model.{type InputBasis, type Request}
import finance_provenance/hash
import finance_provenance/identity.{type EvidenceId, type Sha256}
import finance_track
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const request_schema_version = 1

pub const semantic_schema_version = 1

pub const implementation_version = "finance_indicators/0.1.0"

pub opaque type Envelope {
  Envelope(payload: Json, canonical_content_hash: Sha256)
}

pub type ReceiptError {
  HashFailure
  CalculationMismatch(expected: String, received: String)
}

pub fn request_receipt(request: Request) -> Result(Envelope, ReceiptError) {
  envelope(request_payload(request))
}

pub fn semantic_result_receipt(
  request: Request,
  result: ResultData,
) -> Result(Envelope, ReceiptError) {
  let expected = model.calculation_id(model.calculation(request))
  case result.calculation_id == expected {
    False -> Error(CalculationMismatch(expected, result.calculation_id))
    True -> {
      use request_envelope <- result.try(request_receipt(request))
      use input_hash <- result.try(hash_json(input_json(result.inputs)))
      envelope(semantic_payload(
        request,
        result,
        request_envelope.canonical_content_hash,
        input_hash,
      ))
    }
  }
}

pub fn encode(value: Envelope) -> String {
  json.object([
    #("payload", value.payload),
    #(
      "canonical_content_hash",
      value.canonical_content_hash
        |> identity.sha256_value
        |> json.string,
    ),
  ])
  |> json.to_string
}

pub fn payload_text(value: Envelope) -> String {
  value.payload |> json.to_string
}

pub fn canonical_content_hash(value: Envelope) -> Sha256 {
  value.canonical_content_hash
}

pub fn verify(value: Envelope) -> Bool {
  case hash.text(json.to_string(value.payload)) {
    Ok(actual) -> actual == value.canonical_content_hash
    Error(_) -> False
  }
}

fn envelope(payload: Json) -> Result(Envelope, ReceiptError) {
  case hash.text(json.to_string(payload)) {
    Ok(value) -> Ok(Envelope(payload, value))
    Error(_) -> Error(HashFailure)
  }
}

fn hash_json(value: Json) -> Result(Sha256, ReceiptError) {
  case hash.text(json.to_string(value)) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(HashFailure)
  }
}

fn request_payload(request: Request) -> Json {
  let context = model.request_context(request)
  let source = model.context_source_leg(context)
  let spec = model.calculation(request)
  let rounding = model.rounding(request)
  json.object([
    #("schema", json.string("pi-sparkles/indicator-request")),
    #("schema_version", json.int(request_schema_version)),
    #(
      "instruction_ref",
      model.instruction_ref(request) |> identity.sha256_value |> json.string,
    ),
    #("calculation_id", json.string(model.calculation_id(spec))),
    #("formula_variant", json.string(model.formula_variant(spec))),
    #("parameters", parameters_json(spec)),
    #("track", json.string(finance_track.name(model.context_track(context)))),
    #("instrument_id", json.string(model.instrument_id(context))),
    #("mic", json.string(model.mic(context))),
    #("timezone", json.string(time.timezone_name(model.timezone(context)))),
    #(
      "date_range",
      json.object([
        #("start", json.string(date_text(model.date_start(context)))),
        #("end", json.string(date_text(model.date_end(context)))),
      ]),
    ),
    #(
      "source_leg",
      json.object([
        #("provider", json.string(model.source_provider(source))),
        #("source_reference", json.string(model.source_reference(source))),
        #(
          "acquisition_receipt",
          model.acquisition_receipt(source)
            |> identity.sha256_value
            |> json.string,
        ),
        #(
          "retrieval_time_unix_ms",
          model.retrieval_time(source)
            |> time.unix_milliseconds
            |> json.int,
        ),
      ]),
    ),
    #("source_cutoff", instant_option_json(model.source_cutoff(context))),
    #("input_field", json.string(model.input_field(context))),
    #("input_unit", unit_json(model.input_unit(context))),
    #("adjustment_basis", basis_json(model.adjustment_basis(context))),
    #(
      "retained_alternatives",
      json.array(model.retained_alternatives(context), json.string),
    ),
    #("gap_facts", json.array(model.gap_facts(context), json.string)),
    #("evidence_roots", roots_json(model.evidence_roots(context))),
    #(
      "window_variant",
      model.window_variant(spec)
        |> model.window_variant_name
        |> json.string,
    ),
    #("gap_policy", gap_policy_json(spec)),
    #(
      "parseable_policy",
      model.parseable_policy(request)
        |> model.parseable_policy_name
        |> json.string,
    ),
    #("seed_variant", seed_variant_json(spec)),
    #("scale_and_rounding", rounding_json(rounding)),
    #(
      "summary_fields",
      json.array(model.summary_fields(request), summary_field_json),
    ),
  ])
}

fn semantic_payload(
  request: Request,
  result: ResultData,
  request_hash: Sha256,
  input_hash: Sha256,
) -> Json {
  let context = model.request_context(request)
  let source = model.context_source_leg(context)
  let spec = model.calculation(request)
  let calculated = calculation.calculated_outputs(result)
  let unperformed = calculation.unperformed_outputs(result)
  json.object([
    #("schema", json.string("pi-sparkles/indicator-receipt")),
    #("schema_version", json.int(semantic_schema_version)),
    #("calculation_id", json.string(result.calculation_id)),
    #("formula_variant", json.string(result.formula_variant)),
    #(
      "instruction_ref",
      model.instruction_ref(request) |> identity.sha256_value |> json.string,
    ),
    #(
      "request_receipt_hash",
      request_hash |> identity.sha256_value |> json.string,
    ),
    #("parameters", parameters_json(spec)),
    #("track", json.string(finance_track.name(model.context_track(context)))),
    #("instrument_id", json.string(model.instrument_id(context))),
    #("mic", json.string(model.mic(context))),
    #("timezone", json.string(time.timezone_name(model.timezone(context)))),
    #(
      "source_leg",
      json.object([
        #("provider", json.string(model.source_provider(source))),
        #("source_reference", json.string(model.source_reference(source))),
        #(
          "acquisition_receipt",
          model.acquisition_receipt(source)
            |> identity.sha256_value
            |> json.string,
        ),
      ]),
    ),
    #(
      "retained_alternatives",
      state_list_json(model.retained_alternatives(context), "no alternatives"),
    ),
    #("input_field", json.string(model.input_field(context))),
    #("input_unit", unit_json(model.input_unit(context))),
    #("adjustment_basis", basis_json(model.adjustment_basis(context))),
    #(
      "factor_evidence_roots",
      factor_roots_json(model.adjustment_basis(context)),
    ),
    #(
      "window_variant",
      model.window_variant(spec)
        |> model.window_variant_name
        |> json.string,
    ),
    #("gap_policy", gap_policy_json(spec)),
    #(
      "parseable_policy",
      model.parseable_policy(request)
        |> model.parseable_policy_name
        |> json.string,
    ),
    #("input_content_hash", input_hash |> identity.sha256_value |> json.string),
    #("ordered_inputs", input_json(result.inputs)),
    #("source_cutoff", instant_option_json(model.source_cutoff(context))),
    #(
      "retrieval_time_unix_ms",
      model.retrieval_time(source)
        |> time.unix_milliseconds
        |> json.int,
    ),
    #("gap_facts", state_list_json(model.gap_facts(context), "no gap facts")),
    #("conflict_facts", fact_state_json(result.inputs, "conflicting")),
    #("unknown_facts", fact_state_json(result.inputs, "unknown")),
    #("decode_failure_facts", fact_state_json(result.inputs, "decode_failure")),
    #(
      "mechanical_check_facts",
      fact_state_json(result.inputs, "mechanical_check"),
    ),
    #("seed_variant", receipt_string_slot_json(result.seed_variant)),
    #("seed_inputs", receipt_strings_slot_json(result.seed_inputs)),
    #("scale_and_rounding", rounding_json(model.rounding(request))),
    #("outputs", json.array(calculated, output_json)),
    #("unperformed_outputs", state_outputs_json(unperformed)),
    #("omission_count", json.int(list.length(unperformed))),
    #("first_calculated_date", first_calculated_json(calculated)),
    #("implementation_version", json.string(implementation_version)),
    #("evidence_roots", roots_json(model.evidence_roots(context))),
    #(
      "available_operations",
      json.array(result.available_operations, json.string),
    ),
  ])
}

fn parameters_json(value: model.CalculationSpec) -> Json {
  let base = [#("period", json.int(model.period(value)))]
  case value {
    model.WilderRsiV1(_, _, _, convention) ->
      json.object(
        list.append(base, [
          #("zero_zero_convention", zero_zero_json(convention)),
        ]),
      )
    model.SmaV1(_, _) | model.WilderAtrV1(_, _, _) -> json.object(base)
  }
}

fn rounding_json(value: model.RoundingSpec) -> Json {
  json.object([
    #("output_scale", json.int(model.output_scale(value))),
    #(
      "rounding_mode",
      json.string(rounding_mode_name(model.rounding_mode(value))),
    ),
    #(
      "rounding_policy",
      value
        |> model.rounding_policy
        |> model.rounding_policy_name
        |> json.string,
    ),
    #("intermediate_scale", json.int(model.intermediate_scale(value))),
  ])
}

fn input_json(value: InputSnapshot) -> Json {
  case value {
    input.PriceInputs(slots) ->
      json.array(slots, fn(slot) {
        json.object([
          #("date", json.string(date_text(slot.date))),
          #("fields", json.object([#("value", numeric_fact_json(slot.value))])),
        ])
      })
    input.BarInputs(slots) ->
      json.array(slots, fn(slot) {
        json.object([
          #("date", json.string(date_text(slot.date))),
          #(
            "fields",
            json.object([
              #("high", numeric_fact_json(slot.high)),
              #("low", numeric_fact_json(slot.low)),
              #("close", numeric_fact_json(slot.close)),
            ]),
          ),
        ])
      })
  }
}

fn numeric_fact_json(value: NumericFact) -> Json {
  case value {
    input.Known(raw, value) ->
      json.object([
        #("state", json.string("known")),
        #("raw", json.string(raw)),
        #("parsed", json.string(decimal.to_string(value))),
      ])
    input.ParseableWithFailedChecks(raw, value, checks) ->
      json.object([
        #("state", json.string("parseable_with_failed_checks")),
        #("raw", json.string(raw)),
        #("parsed", json.string(decimal.to_string(value))),
        #("failed_checks", json.array(checks, json.string)),
      ])
    input.Unknown(reason) -> unavailable_fact_json("unknown", reason)
    input.NotObtained(reason) -> unavailable_fact_json("not_obtained", reason)
    input.DecodeFailure(raw, reason) ->
      json.object([
        #("state", json.string("decode_failure")),
        #("raw", json.string(raw)),
        #("reason", json.string(reason)),
      ])
    input.Conflicting(alternatives) ->
      json.object([
        #("state", json.string("conflicting")),
        #(
          "alternatives",
          json.array(alternatives, fn(alternative) {
            json.object([
              #("raw", json.string(alternative.raw)),
              #("parsed", json.string(decimal.to_string(alternative.value))),
              #("source_reference", json.string(alternative.source_reference)),
            ])
          }),
        ),
      ])
  }
}

fn output_json(value: Output) -> Json {
  case value {
    calculation.Calculated(date, value, unit, intermediates) ->
      json.object([
        #("output_date", json.string(date_text(date))),
        #("output_value", json.string(value)),
        #("output_unit", json.string(unit)),
        #(
          "intermediate_values",
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
        #("output_date", json.string(date_text(date))),
        #("reason", unperformed_reason_json(reason)),
        #("operands", json.array(operands, json.string)),
      ])
  }
}

fn unperformed_reason_json(value: calculation.UnperformedReason) -> Json {
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

fn fact_state_json(snapshot: InputSnapshot, kind: String) -> Json {
  let values =
    input_fact_entries(snapshot)
    |> list.filter(fn(entry) { fact_kind(entry.2) == kind })
    |> list.map(fn(entry) {
      json.object([
        #("date", json.string(date_text(entry.0))),
        #("field", json.string(entry.1)),
        #("fact", numeric_fact_json(entry.2)),
      ])
    })
  case values {
    [] -> not_applicable_json("no " <> kind <> " facts")
    _ -> known_json(json.array(values, fn(value) { value }))
  }
}

fn input_fact_entries(
  snapshot: InputSnapshot,
) -> List(#(Date, String, NumericFact)) {
  case snapshot {
    input.PriceInputs(slots) ->
      list.map(slots, fn(slot) { #(slot.date, "value", slot.value) })
    input.BarInputs(slots) ->
      list.flat_map(slots, fn(slot) {
        [
          #(slot.date, "high", slot.high),
          #(slot.date, "low", slot.low),
          #(slot.date, "close", slot.close),
        ]
      })
  }
}

fn fact_kind(value: NumericFact) -> String {
  case value {
    input.Known(_, _) -> "known"
    input.ParseableWithFailedChecks(_, _, _) -> "mechanical_check"
    input.Unknown(_) | input.NotObtained(_) -> "unknown"
    input.Conflicting(_) -> "conflicting"
    input.DecodeFailure(_, _) -> "decode_failure"
  }
}

fn state_outputs_json(values: List(Output)) -> Json {
  case values {
    [] -> not_applicable_json("all outputs calculated")
    _ -> known_json(json.array(values, output_json))
  }
}

fn first_calculated_json(values: List(Output)) -> Json {
  case values {
    [calculation.Calculated(date, _, _, _), ..] ->
      known_json(json.string(date_text(date)))
    _ -> not_applicable_json("no output exists")
  }
}

fn receipt_string_slot_json(value: calculation.ReceiptSlot(String)) -> Json {
  case value {
    calculation.Known(value) -> known_json(json.string(value))
    calculation.NotApplicable(reason) -> not_applicable_json(reason)
    calculation.Unknown(reason) -> state_reason_json("unknown", reason)
    calculation.NotObtained(reason) -> state_reason_json("not_obtained", reason)
    calculation.Conflicting(values) ->
      json.object([
        #("state", json.string("conflicting")),
        #("alternatives", json.array(values, json.string)),
      ])
  }
}

fn receipt_strings_slot_json(
  value: calculation.ReceiptSlot(List(String)),
) -> Json {
  case value {
    calculation.Known(values) -> known_json(json.array(values, json.string))
    calculation.NotApplicable(reason) -> not_applicable_json(reason)
    calculation.Unknown(reason) -> state_reason_json("unknown", reason)
    calculation.NotObtained(reason) -> state_reason_json("not_obtained", reason)
    calculation.Conflicting(values) ->
      json.object([
        #("state", json.string("conflicting")),
        #(
          "alternatives",
          json.array(values, fn(value) { json.array(value, json.string) }),
        ),
      ])
  }
}

fn unit_json(value: model.UnitFact) -> Json {
  case value {
    model.KnownUnit(label) -> known_json(json.string(label))
    model.UnknownUnit(reason) -> state_reason_json("unknown", reason)
  }
}

fn basis_json(value: InputBasis) -> Json {
  case value {
    model.Raw -> json.object([#("kind", json.string("raw"))])
    model.SplitAdjusted(roots) -> basis_with_roots("split_adjusted", roots)
    model.DividendAdjusted(roots) ->
      basis_with_roots("dividend_adjusted", roots)
    model.TotalReturn(roots) -> basis_with_roots("total_return", roots)
    model.ProviderDefined(label, roots) ->
      json.object([
        #("kind", json.string("provider_defined")),
        #("label", json.string(label)),
        #("factor_evidence_roots", roots_json(roots)),
      ])
    model.LlmProjection(name, instruction, roots) ->
      json.object([
        #("kind", json.string("llm_projection")),
        #("name", json.string(name)),
        #(
          "instruction_ref",
          instruction |> identity.sha256_value |> json.string,
        ),
        #("evidence_roots", roots_json(roots)),
      ])
  }
}

fn factor_roots_json(value: InputBasis) -> Json {
  case value {
    model.Raw -> not_applicable_json("Raw input, no factors")
    model.SplitAdjusted(roots)
    | model.DividendAdjusted(roots)
    | model.TotalReturn(roots)
    | model.ProviderDefined(_, roots)
    | model.LlmProjection(_, _, roots) -> known_json(roots_json(roots))
  }
}

fn basis_with_roots(name: String, roots: List(EvidenceId)) -> Json {
  json.object([
    #("kind", json.string(name)),
    #("factor_evidence_roots", roots_json(roots)),
  ])
}

fn gap_policy_json(value: model.CalculationSpec) -> Json {
  case model.gap_policy(value) {
    None -> not_applicable_json("non-recursive formula")
    Some(policy) -> known_json(json.string(model.gap_policy_name(policy)))
  }
}

fn seed_variant_json(value: model.CalculationSpec) -> Json {
  case value {
    model.SmaV1(_, _) -> not_applicable_json("non-recursive formula")
    model.WilderRsiV1(_, _, _, _) ->
      known_json(json.string("seed_wilder_first_n"))
    model.WilderAtrV1(_, _, _) ->
      known_json(json.string("seed_wilder_tr_mean_v1"))
  }
}

fn zero_zero_json(value: model.RsiZeroZeroConvention) -> Json {
  case value {
    model.ZeroZeroUnperformedV1 ->
      json.object([#("kind", json.string("unperformed"))])
    model.ZeroZeroValueV1(value) ->
      json.object([
        #("kind", json.string("rsi_zero_zero_v1")),
        #("value", json.string(decimal.to_string(value))),
      ])
  }
}

fn summary_field_json(value: model.SummaryField) -> Json {
  case value {
    model.LatestValue -> json.string("latest_value")
    model.PriorValue(offset) ->
      json.object([
        #("kind", json.string("prior_value")),
        #("offset", json.int(offset)),
      ])
    model.AbsoluteChange -> json.string("absolute_change")
    model.PercentChange -> json.string("percent_change")
  }
}

fn roots_json(values: List(EvidenceId)) -> Json {
  json.array(values, fn(value) {
    value |> identity.evidence_id_value |> json.string
  })
}

fn state_list_json(values: List(String), empty_reason: String) -> Json {
  case values {
    [] -> not_applicable_json(empty_reason)
    _ -> known_json(json.array(values, json.string))
  }
}

fn instant_option_json(value: Option(Instant)) -> Json {
  case value {
    None -> state_reason_json("not_obtained", "caller did not supply cutoff")
    Some(value) -> known_json(json.int(time.unix_milliseconds(value)))
  }
}

fn known_json(value: Json) -> Json {
  json.object([
    #("state", json.string("known")),
    #("value", value),
  ])
}

fn not_applicable_json(reason: String) -> Json {
  state_reason_json("not_applicable", reason)
}

fn state_reason_json(state: String, reason: String) -> Json {
  json.object([
    #("state", json.string(state)),
    #("reason", json.string(reason)),
  ])
}

fn unavailable_fact_json(state: String, reason: String) -> Json {
  state_reason_json(state, reason)
}

fn rounding_mode_name(value: decimal.RoundingMode) -> String {
  case value {
    decimal.TowardZero -> "toward_zero"
    decimal.AwayFromZero -> "away_from_zero"
    decimal.HalfUp -> "half_up"
    decimal.HalfEven -> "half_even"
  }
}

fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int4(year) <> "-" <> int2(month) <> "-" <> int2(day)
}

fn int2(value: Int) -> String {
  value |> int.to_string |> string.pad_start(to: 2, with: "0")
}

fn int4(value: Int) -> String {
  value |> int.to_string |> string.pad_start(to: 4, with: "0")
}
