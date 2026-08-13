import gleam/dynamic/decode as dynamic_decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_technicals/decode
import pi_sparkles_stock_technicals/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn sma_compact_returns_requested_latest_and_prior_facts_test() {
  let input =
    decode.SmaInput(
      context("cn", "CNE000000001", "XSHG", "Asia/Shanghai", "close", "CNY"),
      "sma_v1",
      3,
      "slot_window_v1",
      "exclude_parseable_with_checks",
      rounding(2, 6),
      decode.ProjectionInput("compact", 1),
      price_observations([
        #("2026-02-18", "10.85"),
        #("2026-02-19", "10.92"),
        #("2026-02-20", "10.95"),
        #("2026-02-24", "10.88"),
        #("2026-02-25", "10.91"),
      ]),
    )
  let assert Ok(response) = domain.run_sma(input)
  latest_value(response) |> should.equal("10.91")
  prior_value(response) |> should.equal("10.92")
  field_int(response, "calculatedOutputs") |> should.equal(3)
  field_int(response, "unperformedOutputs") |> should.equal(2)
  semantic_handle(response) |> string.length |> should.equal(64)
  let text = domain.details(response) |> json.to_string
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
  text |> string.contains("bullish") |> should.be_false
  text |> string.contains("bearish") |> should.be_false
  text |> string.contains("recommended") |> should.be_false
}

pub fn sma_intermediate_reuses_semantic_receipt_and_exposes_sums_test() {
  let compact =
    sma_input(decode.ProjectionInput("compact", 1))
    |> domain.run_sma
  let intermediate =
    sma_input(decode.ProjectionInput("intermediate", 1))
    |> domain.run_sma
  let assert Ok(compact) = compact
  let assert Ok(intermediate) = intermediate
  semantic_handle(compact) |> should.equal(semantic_handle(intermediate))
  let text = domain.details(intermediate) |> json.to_string
  text |> string.contains("\"orderedOutputs\"") |> should.be_true
  text
  |> string.contains("\"name\":\"sum\",\"value\":\"32.74\"")
  |> should.be_true
  text
  |> string.contains("\"kind\":\"insufficient_inputs\"")
  |> should.be_true
}

pub fn wilder_rsi_exposes_seeded_values_without_interpretation_test() {
  let input =
    decode.RsiInput(
      context("us", "US-A", "XNAS", "America/New_York", "close", "USD"),
      "rsi_wilder_v1",
      5,
      "slot_window_v1",
      "seed_wilder_first_n",
      "stop_at_gap_v1",
      "zero_zero_unperformed_v1",
      "exclude_parseable_with_checks",
      rounding(4, 8),
      decode.ProjectionInput("compact", 1),
      price_observations([
        #("2026-02-02", "44.34"),
        #("2026-02-03", "44.09"),
        #("2026-02-04", "44.15"),
        #("2026-02-05", "43.61"),
        #("2026-02-06", "44.33"),
        #("2026-02-09", "44.83"),
        #("2026-02-10", "45.10"),
      ]),
    )
  let assert Ok(response) = domain.run_rsi(input)
  latest_value(response) |> should.equal("67.1859")
  prior_value(response) |> should.equal("61.8357")
  let text = domain.details(response) |> json.to_string
  text |> string.contains("seed_wilder_first_n") |> should.be_true
  text |> string.contains("stop_at_gap_v1") |> should.be_true
  text |> string.contains("overbought") |> should.be_false
  text |> string.contains("oversold") |> should.be_false
}

pub fn wilder_atr_intermediate_exposes_true_range_components_test() {
  let input =
    decode.AtrInput(
      context("hk", "HK-700", "XHKG", "Asia/Hong_Kong", "ohlc", "HKD"),
      "atr_wilder_v1",
      3,
      "slot_window_v1",
      "seed_wilder_tr_mean_v1",
      "tr_first_hl_v1",
      "stop_at_gap_v1",
      "exclude_parseable_with_checks",
      rounding(4, 4),
      decode.ProjectionInput("intermediate", 1),
      [
        bar("2026-02-02", "10.50", "9.80", "10.20"),
        bar("2026-02-03", "10.80", "10.10", "10.60"),
        bar("2026-02-04", "11.00", "10.40", "10.80"),
        bar("2026-02-05", "10.90", "10.30", "10.50"),
      ],
    )
  let assert Ok(response) = domain.run_atr(input)
  latest_value(response) |> should.equal("0.6445")
  prior_value(response) |> should.equal("0.6667")
  let text = domain.details(response) |> json.to_string
  text |> string.contains("tr_first_hl_v1") |> should.be_true
  text
  |> string.contains("\"name\":\"true_range\",\"value\":\"0.6\"")
  |> should.be_true
  text |> string.contains("moderate") |> should.be_false
  text |> string.contains("stop distance") |> should.be_false
}

pub fn unavailable_and_conflicting_facts_remain_visible_test() {
  let facts = [
    decode.ObservationInput(
      "2026-02-02",
      decode.FactInput("known", Some("10.00"), None, [], []),
    ),
    decode.ObservationInput(
      "2026-02-03",
      decode.FactInput("unknown", None, Some("provider omission"), [], []),
    ),
    decode.ObservationInput(
      "2026-02-04",
      decode.FactInput("conflicting", None, None, [], [
        decode.AlternativeInput("10.20", "source-a"),
        decode.AlternativeInput("10.21", "source-b"),
      ]),
    ),
    decode.ObservationInput(
      "2026-02-05",
      decode.FactInput(
        "parseable_with_failed_checks",
        Some("-1.00"),
        None,
        ["negative_price"],
        [],
      ),
    ),
    decode.ObservationInput(
      "2026-02-06",
      decode.FactInput(
        "decode_failure",
        Some("bad"),
        Some("invalid_decimal"),
        [],
        [],
      ),
    ),
  ]
  let request =
    decode.SmaInput(
      context("cn", "CN-X", "XSHE", "Asia/Shanghai", "close", "CNY"),
      "sma_v1",
      1,
      "slot_window_v1",
      "exclude_parseable_with_checks",
      rounding(2, 4),
      decode.ProjectionInput("intermediate", 1),
      facts,
    )
  let assert Ok(response) = domain.run_sma(request)
  field_int(response, "knownFacts") |> should.equal(1)
  field_int(response, "unknownFacts") |> should.equal(1)
  field_int(response, "conflictingFacts") |> should.equal(1)
  field_int(response, "parseableWithFailedChecks") |> should.equal(1)
  field_int(response, "decodeFailures") |> should.equal(1)
  let text = domain.details(response) |> json.to_string
  text |> string.contains("provider omission") |> should.be_true
  text |> string.contains("negative_price") |> should.be_true
  text |> string.contains("source-a") |> should.be_true
  text |> string.contains("source-b") |> should.be_true
}

pub fn unsupported_variants_and_implicit_fact_fields_fail_test() {
  let unsupported =
    decode.SmaInput(
      context("cn", "CN-X", "XSHE", "Asia/Shanghai", "close", "CNY"),
      "sma_partial_v1",
      3,
      "slot_window_v1",
      "exclude_parseable_with_checks",
      rounding(2, 4),
      decode.ProjectionInput("compact", 1),
      price_observations([#("2026-02-02", "10.00")]),
    )
  domain.run_sma(unsupported)
  |> should.equal(
    Error(domain.InvalidField(
      "calculation.formulaVariant",
      "first slice requires sma_v1",
    )),
  )

  let malformed =
    decode.SmaInput(
      context("cn", "CN-X", "XSHE", "Asia/Shanghai", "close", "CNY"),
      "sma_v1",
      1,
      "slot_window_v1",
      "exclude_parseable_with_checks",
      rounding(2, 4),
      decode.ProjectionInput("compact", 1),
      [
        decode.ObservationInput(
          "2026-02-02",
          decode.FactInput("unknown", Some("10.00"), None, [], []),
        ),
      ],
    )
  case domain.run_sma(malformed) {
    Error(domain.InvalidField("observations[].value", _)) ->
      should.be_true(True)
    _ -> should.fail()
  }
}

fn sma_input(projection: decode.ProjectionInput) -> decode.SmaInput {
  decode.SmaInput(
    context("cn", "CNE000000001", "XSHG", "Asia/Shanghai", "close", "CNY"),
    "sma_v1",
    3,
    "slot_window_v1",
    "exclude_parseable_with_checks",
    rounding(2, 6),
    projection,
    price_observations([
      #("2026-02-18", "10.85"),
      #("2026-02-19", "10.92"),
      #("2026-02-20", "10.95"),
      #("2026-02-24", "10.88"),
      #("2026-02-25", "10.91"),
    ]),
  )
}

fn context(
  track: String,
  instrument: String,
  mic: String,
  timezone: String,
  field: String,
  unit: String,
) -> decode.ContextInput {
  decode.ContextInput(
    Some(hash("1")),
    track,
    instrument,
    mic,
    timezone,
    "2026-02-01",
    "2026-02-28",
    decode.SourceInput(
      "fixture-provider",
      "fixture://exact-bars",
      hash("2"),
      1_770_000_000_000,
      None,
    ),
    field,
    decode.UnitInput("known", Some(unit), None),
    decode.BasisInput("raw", None, None, []),
    [],
    [],
    [hash("3")],
  )
}

fn rounding(output: Int, intermediate: Int) -> decode.RoundingInput {
  decode.RoundingInput("half_up", "per_step", output, intermediate)
}

fn price_observations(
  values: List(#(String, String)),
) -> List(decode.ObservationInput) {
  values
  |> list.map(fn(value) {
    decode.ObservationInput(
      value.0,
      decode.FactInput("known", Some(value.1), None, [], []),
    )
  })
}

fn bar(
  date: String,
  high: String,
  low: String,
  close: String,
) -> decode.BarInput {
  decode.BarInput(date, known(high), known(low), known(close))
}

fn known(value: String) -> decode.FactInput {
  decode.FactInput("known", Some(value), None, [], [])
}

fn latest_value(value: domain.Response) -> String {
  nested_output_value(value, "latestValue")
}

fn prior_value(value: domain.Response) -> String {
  nested_output_value(value, "priorValue")
}

fn nested_output_value(value: domain.Response, name: String) -> String {
  let value_decoder = {
    use output <- dynamic_decode.field(name, {
      use output <- dynamic_decode.field("output", {
        use value <- dynamic_decode.field("value", dynamic_decode.string)
        dynamic_decode.success(value)
      })
      dynamic_decode.success(output)
    })
    dynamic_decode.success(output)
  }
  let assert Ok(value) =
    domain.details(value) |> json.to_string |> json.parse(value_decoder)
  value
}

fn semantic_handle(value: domain.Response) -> String {
  let value_decoder = {
    use value <- dynamic_decode.field(
      "semanticReceiptHandle",
      dynamic_decode.string,
    )
    dynamic_decode.success(value)
  }
  let assert Ok(value) =
    domain.details(value) |> json.to_string |> json.parse(value_decoder)
  value
}

fn field_int(value: domain.Response, name: String) -> Int {
  let value_decoder = {
    use counts <- dynamic_decode.field("counts", {
      use value <- dynamic_decode.field(name, dynamic_decode.int)
      dynamic_decode.success(value)
    })
    dynamic_decode.success(counts)
  }
  let assert Ok(value) =
    domain.details(value) |> json.to_string |> json.parse(value_decoder)
  value
}

fn hash(digit: String) -> String {
  string.repeat(digit, 64)
}
