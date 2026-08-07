import finance_core/decimal
import finance_core/time.{type Date}
import finance_indicators
import finance_indicators/atr
import finance_indicators/calculation
import finance_indicators/input
import finance_indicators/model
import finance_indicators/receipt
import finance_indicators/rsi
import finance_indicators/sma
import finance_ohlcv/fact
import finance_provenance/identity
import finance_track
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_indicators.status()
  |> should.equal(finance_indicators.Experimental)
}

pub fn requests_require_positive_period_and_supported_rounding_test() {
  model.request(
    instruction_ref(),
    base_context(model.Raw, model.KnownUnit("CNY"), "close"),
    model.SmaV1(0, model.SlotWindowV1),
    model.ExcludeParseableWithChecks,
    rounding4(),
    [],
  )
  |> should.equal(Error(model.InvalidPeriod))

  model.request(
    instruction_ref(),
    base_context(model.Raw, model.KnownUnit("CNY"), "close"),
    model.SmaV1(3, model.SlotWindowV1),
    model.ExcludeParseableWithChecks,
    model.RoundingSpec(2, decimal.HalfUp, model.FinalOnly, 8),
    [],
  )
  |> should.equal(Error(model.UnsupportedRoundingPolicy))
}

pub fn reversed_context_range_is_rejected_test() {
  let assert Ok(source) =
    model.source_leg("fixture", "fixture://daily", hash("a"), instant(100))
  model.context(
    finance_track.Cn,
    "CNE000000001",
    "XSHG",
    timezone(),
    date(28),
    date(1),
    source,
    Some(instant(200)),
    "close",
    model.KnownUnit("CNY"),
    model.Raw,
    [],
    [],
    [root("b")],
  )
  |> should.equal(Error(model.InvalidDateRange))
}

pub fn shared_market_fact_states_are_preserved_test() {
  let value = decimal_value("10.25")
  input.from_market_fact("10.25", fact.Known(value))
  |> should.equal(input.Known("10.25", value))
  input.from_market_fact("", fact.Unknown("provider omission"))
  |> should.equal(input.Unknown("provider omission"))
  input.from_market_fact("bad", fact.DecodeFailure("bad", "invalid_decimal"))
  |> should.equal(input.DecodeFailure("bad", "invalid_decimal"))
}

pub fn sma_fixture_returns_exact_values_without_a_verdict_test() {
  let request = sma_request(3, model.ExcludeParseableWithChecks, model.Raw, [])
  let slots =
    price_slots([
      known("10.85"),
      known("10.92"),
      known("10.95"),
      known("10.88"),
      known("10.91"),
    ])
  let assert Ok(result) = sma.calculate(request, slots)
  calculated_values(result)
  |> should.equal(["10.91", "10.92", "10.91"])
  calculation.unperformed_outputs(result) |> list.length |> should.equal(2)

  let assert Ok(receipt) = receipt.semantic_result_receipt(request, result)
  let encoded = receipt.encode(receipt)
  encoded |> string.contains("bullish") |> should.be_false
  encoded |> string.contains("ready") |> should.be_false
  encoded |> string.contains("recommendation") |> should.be_false
  encoded |> string.contains("next_action") |> should.be_false
}

pub fn slot_window_recovers_after_missing_slot_leaves_window_test() {
  let request = sma_request(3, model.ExcludeParseableWithChecks, model.Raw, [])
  let slots =
    price_slots([
      known("10.00"),
      input.Unknown("provider omission"),
      known("11.00"),
      known("10.80"),
      known("11.20"),
    ])
  let assert Ok(result) = sma.calculate(request, slots)
  calculated_values(result) |> should.equal(["11.00"])
  calculation.unperformed_outputs(result) |> list.length |> should.equal(4)
}

pub fn mechanical_check_policy_controls_use_without_judging_value_test() {
  let assert Ok(flagged) =
    input.parseable_with_failed_checks("-1.00", ["close_non_negative=false"])
  let slots = price_slots([flagged])
  let exclude = sma_request(1, model.ExcludeParseableWithChecks, model.Raw, [])
  let include = sma_request(1, model.IncludeParseableWithChecks, model.Raw, [])
  let assert Ok(excluded) = sma.calculate(exclude, slots)
  calculation.calculated_outputs(excluded) |> should.equal([])
  let assert Ok(included) = sma.calculate(include, slots)
  calculated_values(included) |> should.equal(["-1.00"])
}

pub fn wilder_rsi_fixture_is_deterministic_under_explicit_per_step_policy_test() {
  let request = rsi_request(5, model.StopAtGapV1, model.ZeroZeroUnperformedV1)
  let slots =
    price_slots(list.map(
      [
        "44.34",
        "44.09",
        "44.15",
        "43.61",
        "44.33",
        "44.83",
        "45.10",
        "45.42",
        "45.84",
        "46.08",
        "45.89",
      ],
      known,
    ))
  let assert Ok(result) = rsi.calculate(request, slots)
  calculated_values(result)
  |> should.equal([
    "61.8357",
    "67.1859",
    "72.8289",
    "78.8079",
    "81.6865",
    "72.0076",
  ])
  calculation.unperformed_outputs(result) |> list.length |> should.equal(5)
}

pub fn rsi_zero_zero_requires_an_explicit_convention_test() {
  let slots = price_slots(list.repeat(known("10.00"), times: 6))
  let unperformed_request =
    rsi_request(5, model.StopAtGapV1, model.ZeroZeroUnperformedV1)
  let assert Ok(unperformed) = rsi.calculate(unperformed_request, slots)
  calculation.calculated_outputs(unperformed) |> should.equal([])

  let selected_request =
    rsi_request(
      5,
      model.StopAtGapV1,
      model.ZeroZeroValueV1(decimal_value("50.0000")),
    )
  let assert Ok(selected) = rsi.calculate(selected_request, slots)
  calculated_values(selected) |> should.equal(["50.0000"])
}

pub fn rsi_stop_gap_does_not_resume_silently_test() {
  let request = rsi_request(2, model.StopAtGapV1, model.ZeroZeroUnperformedV1)
  let slots =
    price_slots([
      known("1"),
      known("2"),
      known("3"),
      input.Unknown("provider omission"),
      known("4"),
      known("5"),
      known("6"),
    ])
  let assert Ok(result) = rsi.calculate(request, slots)
  calculated_values(result) |> should.equal(["100.0000"])
  calculation.unperformed_outputs(result) |> list.length |> should.equal(6)
}

pub fn rsi_restart_gap_reseeds_from_post_gap_closes_test() {
  let request =
    rsi_request(2, model.RestartSeedAfterGapV1, model.ZeroZeroUnperformedV1)
  let slots =
    price_slots([
      known("1"),
      known("2"),
      known("3"),
      input.Unknown("provider omission"),
      known("4"),
      known("5"),
      known("6"),
    ])
  let assert Ok(result) = rsi.calculate(request, slots)
  calculated_values(result) |> should.equal(["100.0000", "100.0000"])
}

pub fn wilder_atr_fixture_exposes_true_range_components_test() {
  let request = atr_request(3, model.StopAtGapV1)
  let slots = [
    bar(1, "10.50", "9.80", "10.20"),
    bar(2, "10.80", "10.10", "10.60"),
    bar(3, "11.00", "10.40", "10.80"),
    bar(4, "10.90", "10.30", "10.50"),
  ]
  let assert Ok(result) = atr.calculate(request, slots)
  calculated_values(result) |> should.equal(["0.6667", "0.6444"])
  let assert [calculation.Calculated(_, _, _, values), ..] =
    calculation.calculated_outputs(result)
  values
  |> list.any(fn(value) { value.name == "true_range" })
  |> should.be_true
}

pub fn unknown_unit_is_retained_on_requested_raw_arithmetic_test() {
  let context =
    base_context(
      model.Raw,
      model.UnknownUnit("provider did not state shares or lots"),
      "volume",
    )
  let request =
    make_request(
      context,
      model.SmaV1(2, model.SlotWindowV1),
      model.ExcludeParseableWithChecks,
      rounding2(),
      [],
    )
  let assert Ok(result) =
    sma.calculate(request, price_slots([known("100"), known("120")]))
  let assert [calculation.Calculated(_, "110.00", "unknown", _)] =
    calculation.calculated_outputs(result)
}

pub fn receipts_are_non_self_referential_and_deterministic_test() {
  let request = sma_request(3, model.ExcludeParseableWithChecks, model.Raw, [])
  let slots = price_slots([known("10"), known("11"), known("12")])
  let assert Ok(first_result) = sma.calculate(request, slots)
  let assert Ok(second_result) = sma.calculate(request, slots)
  let assert Ok(first) = receipt.semantic_result_receipt(request, first_result)
  let assert Ok(second) =
    receipt.semantic_result_receipt(request, second_result)
  receipt.verify(first) |> should.be_true
  receipt.canonical_content_hash(first)
  |> should.equal(receipt.canonical_content_hash(second))
  receipt.payload_text(first)
  |> string.contains("canonical_content_hash")
  |> should.be_false
}

pub fn source_correction_changes_semantic_receipt_without_overwriting_old_test() {
  let request = sma_request(3, model.ExcludeParseableWithChecks, model.Raw, [])
  let assert Ok(original_result) =
    sma.calculate(
      request,
      price_slots([known("10.85"), known("10.92"), known("10.95")]),
    )
  let assert Ok(corrected_result) =
    sma.calculate(
      request,
      price_slots([known("10.85"), known("10.92"), known("10.93")]),
    )
  let assert Ok(original) =
    receipt.semantic_result_receipt(request, original_result)
  let assert Ok(corrected) =
    receipt.semantic_result_receipt(request, corrected_result)
  {
    receipt.canonical_content_hash(original)
    == receipt.canonical_content_hash(corrected)
  }
  |> should.be_false
  calculated_values(original_result) |> should.equal(["10.91"])
  calculated_values(corrected_result) |> should.equal(["10.90"])
}

pub fn selected_input_basis_is_bound_into_request_receipt_test() {
  let raw = sma_request(3, model.ExcludeParseableWithChecks, model.Raw, [])
  let adjusted =
    sma_request(
      3,
      model.ExcludeParseableWithChecks,
      model.SplitAdjusted([root("c")]),
      [],
    )
  let assert Ok(raw_receipt) = receipt.request_receipt(raw)
  let assert Ok(adjusted_receipt) = receipt.request_receipt(adjusted)
  {
    receipt.canonical_content_hash(raw_receipt)
    == receipt.canonical_content_hash(adjusted_receipt)
  }
  |> should.be_false
}

pub fn summaries_are_bound_only_when_explicitly_requested_test() {
  let compact =
    sma_request(3, model.ExcludeParseableWithChecks, model.Raw, [
      model.LatestValue,
      model.PriorValue(1),
    ])
  let minimal = sma_request(3, model.ExcludeParseableWithChecks, model.Raw, [])
  let assert Ok(compact_receipt) = receipt.request_receipt(compact)
  let assert Ok(minimal_receipt) = receipt.request_receipt(minimal)
  receipt.payload_text(compact_receipt)
  |> string.contains("latest_value")
  |> should.be_true
  receipt.payload_text(minimal_receipt)
  |> string.contains("latest_value")
  |> should.be_false
}

pub fn nonascending_observations_are_a_mechanical_error_test() {
  let request = sma_request(2, model.ExcludeParseableWithChecks, model.Raw, [])
  sma.calculate(request, [
    input.PriceSlot(date(2), known("10")),
    input.PriceSlot(date(1), known("11")),
  ])
  |> should.equal(Error(calculation.InvalidInputOrder))
}

fn sma_request(
  period: Int,
  policy: model.ParseablePolicy,
  basis: model.InputBasis,
  summary: List(model.SummaryField),
) -> model.Request {
  make_request(
    base_context(basis, model.KnownUnit("CNY"), "close"),
    model.SmaV1(period, model.SlotWindowV1),
    policy,
    rounding2(),
    summary,
  )
}

fn rsi_request(
  period: Int,
  gap: model.GapPolicy,
  zero_zero: model.RsiZeroZeroConvention,
) -> model.Request {
  make_request(
    base_context(model.Raw, model.KnownUnit("CNY"), "close"),
    model.WilderRsiV1(period, model.SlotWindowV1, gap, zero_zero),
    model.ExcludeParseableWithChecks,
    rounding4(),
    [],
  )
}

fn atr_request(period: Int, gap: model.GapPolicy) -> model.Request {
  make_request(
    base_context(model.Raw, model.KnownUnit("CNY"), "ohlc"),
    model.WilderAtrV1(period, model.SlotWindowV1, gap),
    model.ExcludeParseableWithChecks,
    rounding4(),
    [],
  )
}

fn make_request(
  context: model.Context,
  calculation: model.CalculationSpec,
  policy: model.ParseablePolicy,
  rounding: model.RoundingSpec,
  summary: List(model.SummaryField),
) -> model.Request {
  let assert Ok(value) =
    model.request(
      instruction_ref(),
      context,
      calculation,
      policy,
      rounding,
      summary,
    )
  value
}

fn base_context(
  basis: model.InputBasis,
  unit: model.UnitFact,
  field: String,
) -> model.Context {
  let assert Ok(source) =
    model.source_leg("fixture", "fixture://daily", hash("a"), instant(100))
  let assert Ok(context) =
    model.context(
      finance_track.Cn,
      "CNE000000001",
      "XSHG",
      timezone(),
      date(1),
      date(28),
      source,
      Some(instant(200)),
      field,
      unit,
      basis,
      [],
      [],
      [root("b")],
    )
  context
}

fn rounding4() -> model.RoundingSpec {
  model.RoundingSpec(4, decimal.HalfUp, model.PerStep, 8)
}

fn rounding2() -> model.RoundingSpec {
  model.RoundingSpec(2, decimal.HalfUp, model.PerStep, 8)
}

fn price_slots(values: List(input.NumericFact)) -> List(input.PriceSlot) {
  list.index_map(values, fn(value, index) {
    input.PriceSlot(date(index + 1), value)
  })
}

fn bar(day: Int, high: String, low: String, close: String) -> input.BarSlot {
  input.BarSlot(date(day), known(high), known(low), known(close))
}

fn calculated_values(value: calculation.ResultData) -> List(String) {
  value
  |> calculation.calculated_outputs
  |> list.flat_map(fn(output) {
    case output {
      calculation.Calculated(_, value, _, _) -> [value]
      calculation.Unperformed(_, _, _) -> []
    }
  })
}

fn known(value: String) -> input.NumericFact {
  let assert Ok(value) = input.known(value)
  value
}

fn decimal_value(value: String) -> decimal.Decimal {
  let assert Ok(value) = decimal.parse(value)
  value
}

fn date(day: Int) -> Date {
  let assert Ok(value) = time.date(2026, 2, day)
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}

fn timezone() -> time.Timezone {
  let assert Ok(value) = time.timezone("Asia/Shanghai")
  value
}

fn hash(character: String) -> identity.Sha256 {
  let assert Ok(value) = identity.sha256(string.repeat(character, times: 64))
  value
}

fn instruction_ref() -> identity.Sha256 {
  hash("d")
}

fn root(character: String) -> identity.EvidenceId {
  identity.evidence_id(hash(character))
}
