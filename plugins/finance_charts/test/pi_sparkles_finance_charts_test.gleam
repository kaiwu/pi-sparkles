import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_finance_charts/decode
import pi_sparkles_finance_charts/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_view_has_responsive_policy_and_mandatory_structured_fallback_test() {
  let assert Ok(response) = domain.run(fixture())
  let details = json.to_string(response.details)

  response.fallback
  |> string.contains("| Date | Session | Open | High | Low | Close | Volume |")
  |> should.be_true
  response.fallback
  |> string.contains("The active host renders this result inline")
  |> should.be_true
  details
  |> string.contains("\"allExactRowsRetainedInDetails\":true")
  |> should.be_true
  details
  |> string.contains("\"omittedRows\":1")
  |> should.be_true
  details
  |> string.contains("\"kind\":\"responsive_ohlcv_view\"")
  |> should.be_true
  details
  |> string.contains("\"selection\":\"latest_contiguous_suffix\"")
  |> should.be_true
}

pub fn unperformed_points_gaps_and_unmatched_trades_remain_explicit_test() {
  let assert Ok(response) = domain.run(fixture())
  let details = json.to_string(response.details)

  details
  |> string.contains(
    "\"state\":\"unperformed\",\"date\":\"2026-02-02\",\"reason\":\"warmup\",\"rendered\":false",
  )
  |> should.be_true
  details
  |> string.contains(
    "\"tradeId\":\"outside\",\"date\":\"2026-02-06\",\"side\":\"sell\"",
  )
  |> should.be_true
  details
  |> string.contains("\"renderOmission\":\"no_matching_bar_date\"")
  |> should.be_true
  details
  |> string.contains(
    "\"state\":\"market_closure\",\"reason\":\"published closure\"",
  )
  |> should.be_true
  details
  |> string.contains("\"inputOmissions\":[\"trade costs not supplied\"]")
  |> should.be_true
}

pub fn equal_input_produces_equal_details_test() {
  let assert Ok(first) = domain.run(fixture())
  let assert Ok(second) = domain.run(fixture())

  json.to_string(first.details) |> should.equal(json.to_string(second.details))
}

pub fn wrong_track_mic_timezone_combination_fails_without_fallback_test() {
  let input = fixture()
  let context = decode.ContextInput(..input.context, mic: "XHKG")

  case domain.run(decode.Input(..input, context: context)) {
    Error(domain.InvalidField("context.track/mic/timezone", reason)) ->
      reason |> string.contains("no fallback") |> should.be_true
    _ -> should.fail()
  }
}

pub fn bars_must_be_strictly_increasing_and_unique_test() {
  let input = fixture()
  let assert [first, second, third] = input.series
  let duplicate = decode.BarInput(..second, date: first.date)

  case domain.run(decode.Input(..input, series: [first, duplicate, third])) {
    Error(domain.InvalidSeries(1, reason)) ->
      reason |> string.contains("strictly increasing") |> should.be_true
    _ -> should.fail()
  }
}

pub fn invalid_ohlc_or_negative_volume_fails_test() {
  let input = fixture()
  let assert [first, second, third] = input.series
  let invalid = decode.BarInput(..second, high: "9", volume: "-1")

  case domain.run(decode.Input(..input, series: [first, invalid, third])) {
    Error(domain.InvalidSeries(1, reason)) ->
      reason |> string.contains("invariant failed") |> should.be_true
    _ -> should.fail()
  }
}

pub fn price_overlay_unit_must_match_price_unit_test() {
  let input = fixture()
  let assert [overlay, lower] = input.indicators
  let invalid = decode.IndicatorInput(..overlay, unit: "percent")

  case domain.run(decode.Input(..input, indicators: [invalid, lower])) {
    Error(domain.InvalidIndicator("sma_2", reason)) ->
      reason |> string.contains("priceUnit") |> should.be_true
    _ -> should.fail()
  }
}

pub fn lower_panel_units_cannot_be_mixed_test() {
  let input = fixture()
  let assert [overlay, lower] = input.indicators
  let second_lower =
    decode.IndicatorInput("atr_2", "ATR 2", "lower_panel", "USD", 1, hash("8"), [
      decode.Unperformed("2026-02-02", "warmup"),
      decode.Calculated("2026-02-03", "0.5"),
      decode.Calculated("2026-02-04", "0.6"),
    ])

  case
    domain.run(
      decode.Input(..input, indicators: [overlay, lower, second_lower]),
    )
  {
    Error(domain.InvalidIndicator("atr_2", reason)) ->
      reason |> string.contains("share one exact unit") |> should.be_true
    _ -> should.fail()
  }
}

pub fn indicator_point_dates_must_be_ordered_test() {
  let input = fixture()
  let assert [overlay, lower] = input.indicators
  let invalid =
    decode.IndicatorInput(..overlay, points: [
      decode.Calculated("2026-02-04", "10.8"),
      decode.Calculated("2026-02-03", "10.5"),
    ])

  case domain.run(decode.Input(..input, indicators: [invalid, lower])) {
    Error(domain.InvalidIndicator("sma_2", reason)) ->
      reason |> string.contains("strictly increasing") |> should.be_true
    _ -> should.fail()
  }
}

pub fn flat_price_and_zero_volume_still_produce_exact_bounds_test() {
  let input = fixture()
  let flat =
    input.series
    |> list.map(fn(bar) {
      decode.BarInput(
        ..bar,
        open: "10",
        high: "10",
        low: "10",
        close: "10",
        volume: "0",
      )
    })

  let assert Ok(response) =
    domain.run(decode.Input(..input, series: flat, indicators: [], trades: []))
  json.to_string(response.details)
  |> string.contains("\"minimum\":\"10\",\"maximum\":\"10\"")
  |> should.be_true
}

pub fn source_cutoff_cannot_follow_retrieval_test() {
  let input = fixture()
  let source =
    decode.SourceInput(
      ..input.context.source,
      source_cutoff_unix_milliseconds: Some(1_800_000_000_001),
    )
  let context = decode.ContextInput(..input.context, source: source)

  case domain.run(decode.Input(..input, context: context)) {
    Error(domain.InvalidField(
      "context.source.sourceCutoffUnixMilliseconds",
      reason,
    )) -> reason |> string.contains("later") |> should.be_true
    _ -> should.fail()
  }
}

fn fixture() -> decode.Input {
  decode.Input(
    context: decode.ContextInput(
      instruction_ref: hash("1"),
      track: "us",
      instrument_id: "US-AAPL",
      mic: "XNAS",
      timezone: "America/New_York",
      source_language: "en-US",
      price_unit: "USD",
      volume_unit: "shares",
      adjustment: decode.AdjustmentInput("raw", None),
      source: decode.SourceInput(
        provider: "fixture-provider",
        source_reference: "fixture://daily-bars",
        acquisition_receipt: hash("2"),
        retrieved_at_unix_milliseconds: 1_800_000_000_000,
        source_cutoff_unix_milliseconds: Some(1_799_999_000_000),
        entitlement: "fixture_local_analysis",
      ),
      limitations: ["fixture_only"],
    ),
    series: [
      decode.BarInput("2026-02-02", "regular", "10", "11", "9", "10.5", "100"),
      decode.BarInput(
        "2026-02-03",
        "regular",
        "10.5",
        "12",
        "10",
        "11.5",
        "150",
      ),
      decode.BarInput(
        "2026-02-04",
        "half_day",
        "11.5",
        "12",
        "10.5",
        "10.75",
        "80",
      ),
    ],
    indicators: [
      decode.IndicatorInput(
        "sma_2",
        "SMA 2",
        "price_overlay",
        "USD",
        1,
        hash("3"),
        [
          decode.Unperformed("2026-02-02", "warmup"),
          decode.Calculated("2026-02-03", "11"),
          decode.Calculated("2026-02-04", "11.125"),
        ],
      ),
      decode.IndicatorInput(
        "rsi_2",
        "RSI 2",
        "lower_panel",
        "ratio_0_100",
        1,
        hash("4"),
        [
          decode.Unperformed("2026-02-02", "warmup"),
          decode.Calculated("2026-02-03", "75"),
          decode.Calculated("2026-02-04", "40"),
        ],
      ),
    ],
    trades: [
      decode.TradeInput(
        "matched",
        "2026-02-03",
        "buy",
        "10.75",
        "5",
        "simulated",
        hash("5"),
      ),
      decode.TradeInput(
        "outside",
        "2026-02-06",
        "sell",
        "11.25",
        "5",
        "proposed",
        hash("6"),
      ),
    ],
    gaps: [
      decode.GapInput("2026-02-05", "market_closure", "published closure", [
        hash("7"),
      ]),
    ],
    input_omissions: ["trade costs not supplied"],
    fallback_maximum_rows: 2,
  )
}

fn hash(character: String) -> String {
  string.repeat(character, times: 64)
}
