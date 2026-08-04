import finance_core/adjustment
import finance_core/decimal
import finance_core/market
import finance_core/observation
import finance_core/source
import finance_core/time
import finance_math/statistics
import finance_series
import finance_series/alignment
import finance_series/analytics
import finance_series/as_of
import finance_series/bar
import finance_series/exact_path
import finance_series/observed
import finance_series/path
import finance_series/portfolio
import finance_series/resample
import finance_series/returns
import finance_series/series
import finance_series/window
import gleam/float
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_series.status()
  |> should.equal(finance_series.Experimental)
}

pub fn series_requires_a_strict_timeline_but_allows_empty_test() {
  series.new([])
  |> should.be_ok
  series.new([
    series.Point(at(1), series.Present("one")),
    series.Point(at(1), series.Present("duplicate")),
  ])
  |> should.equal(Error(series.DuplicateTimestamp(at(1))))
  series.new([
    series.Point(at(2), series.Present("later")),
    series.Point(at(1), series.Present("earlier")),
  ])
  |> should.equal(Error(series.OutOfOrder(at(2), at(1))))
}

pub fn missing_policies_are_explicit_and_immutable_test() {
  let original =
    values([
      series.Point(at(1), series.Missing(observation.NotReported)),
      series.Point(at(2), series.Present(20)),
      series.Point(at(3), series.Missing(observation.Unavailable)),
    ])
  let assert Ok(filled) = series.resolve_missing(original, series.ForwardFill)
  let assert Ok(dropped) = series.resolve_missing(original, series.Drop)

  series.to_list(filled)
  |> should.equal([
    series.Point(at(1), series.Missing(observation.NotReported)),
    series.Point(at(2), series.Present(20)),
    series.Point(at(3), series.Present(20)),
  ])
  series.to_list(dropped)
  |> should.equal([series.Point(at(2), series.Present(20))])
  series.missing_count(original)
  |> should.equal(2)
  series.resolve_missing(original, series.Reject)
  |> should.equal(Error(series.MissingRejected(at(1), observation.NotReported)))
  let complete = present([#(1, 10), #(2, 20)])
  series.resolve_missing(complete, series.Reject)
  |> should.equal(Ok(complete))
}

pub fn alignment_supports_inner_left_right_and_full_without_reordering_test() {
  let left = present([#(1, "a"), #(3, "c")])
  let right = present([#(2, 20), #(3, 30)])

  alignment.align(left, right, join: alignment.Inner)
  |> should.equal([
    alignment.Aligned(
      at(3),
      Some(series.Present("c")),
      Some(series.Present(30)),
    ),
  ])
  alignment.align(left, right, join: alignment.Full)
  |> should.equal([
    alignment.Aligned(at(1), Some(series.Present("a")), None),
    alignment.Aligned(at(2), None, Some(series.Present(20))),
    alignment.Aligned(
      at(3),
      Some(series.Present("c")),
      Some(series.Present(30)),
    ),
  ])
}

pub fn rolling_windows_make_partial_history_a_policy_test() {
  let input = present([#(1, 10), #(2, 20), #(3, 30)])
  let assert Ok(full) = window.windows(input, size: 2, mode: window.FullOnly)
  let assert Ok(partial) =
    window.windows(input, size: 2, mode: window.IncludePartial)

  list.length(full) |> should.equal(2)
  list.length(partial) |> should.equal(3)
  let assert [first, ..] = partial
  first.starts_at |> should.equal(at(1))
  first.ends_at |> should.equal(at(1))
  window.windows(input, size: 0, mode: window.FullOnly)
  |> should.equal(Error(series.InvalidWindowSize))
}

pub fn resampling_injects_bucket_rules_and_pure_aggregation_test() {
  let input = present([#(0, 1), #(1000, 2), #(2000, 3), #(3000, 4)])
  let assert Ok(output) =
    resample.resample(
      input,
      bucket_start: fn(instant) {
        let milliseconds = time.unix_milliseconds(instant)
        at(milliseconds / 2000 * 2000)
      },
      with: fn(points) {
        points
        |> list.map(fn(point) {
          case point.datum {
            series.Present(value) -> value
            series.Missing(_) -> 0
          }
        })
        |> list.fold(0, fn(total, value) { total + value })
        |> series.Present
      },
    )

  series.to_list(output)
  |> should.equal([
    series.Point(at(0), series.Present(3)),
    series.Point(at(2000), series.Present(7)),
  ])
}

pub fn decimal_returns_preserve_precision_and_missing_adjacency_test() {
  let prices =
    values([
      series.Point(at(1), series.Present(decimal("100"))),
      series.Point(at(2), series.Present(decimal("110"))),
      series.Point(at(3), series.Missing(observation.NotReported)),
      series.Point(at(4), series.Present(decimal("121"))),
      series.Point(at(5), series.Present(decimal("133.1"))),
    ])
  let assert Ok(calculated) =
    returns.simple(prices, scale: 4, rounding: decimal.HalfEven)

  series.to_list(calculated)
  |> should.equal([
    series.Point(at(2), series.Present(decimal("0.1"))),
    series.Point(at(3), series.Missing(observation.NotReported)),
    series.Point(at(4), series.Missing(observation.NotReported)),
    series.Point(at(5), series.Present(decimal("0.1"))),
  ])
  returns.simple(
    decimal_present([#(1, "0"), #(2, "10")]),
    scale: 4,
    rounding: decimal.HalfEven,
  )
  |> should.equal(Error(returns.DivisionByZero(at(2))))
  returns.simple(decimal_present([]), scale: -1, rounding: decimal.HalfEven)
  |> should.equal(Error(returns.InvalidScale))
}

pub fn aligned_analytics_reject_accidental_timeline_mismatch_test() {
  let asset = float_present([#(1, 0.02), #(2, 0.04), #(3, 0.06)])
  let benchmark = float_present([#(1, 0.01), #(2, 0.02), #(3, 0.03)])
  expect_close(
    analytics.beta(
      asset,
      benchmark,
      timeline: analytics.ExactTimeline,
      missing: analytics.RejectMissing,
      estimator: statistics.Sample,
    ),
    2.0,
  )

  analytics.paired_values(
    asset,
    float_present([#(1, 0.01), #(3, 0.03)]),
    timeline: analytics.ExactTimeline,
    missing: analytics.RejectMissing,
  )
  |> should.equal(Error(analytics.TimelineMismatch(at(2))))
  analytics.paired_values(
    asset,
    float_present([#(1, 0.01), #(3, 0.03)]),
    timeline: analytics.Intersection,
    missing: analytics.RejectMissing,
  )
  |> should.equal(Ok(#([0.02, 0.06], [0.01, 0.03])))
}

pub fn portfolio_missing_constituent_policy_cannot_be_implicit_test() {
  let components = [
    portfolio.Component("a", 0.6, float_present([#(1, 0.1), #(2, 0.2)])),
    portfolio.Component("b", 0.4, float_present([#(1, 0.05)])),
  ]
  let assert Ok(strict) =
    portfolio.weighted_returns(
      components,
      missing: portfolio.RequireAll,
      weight_tolerance: 0.000_001,
    )
  let assert Ok(renormalized) =
    portfolio.weighted_returns(
      components,
      missing: portfolio.RenormalizeAvailable,
      weight_tolerance: 0.000_001,
    )

  series.to_list(strict)
  |> should.equal([
    series.Point(at(1), series.Present(0.08)),
    series.Point(at(2), series.Missing(observation.Unavailable)),
  ])
  let assert [_, series.Point(_, series.Present(second)), ..] =
    series.to_list(renormalized)
  { float.absolute_value(second -. 0.2) <=. 0.000_001 }
  |> should.be_true
}

pub fn portfolio_validates_identity_and_weight_contract_test() {
  portfolio.weighted_returns(
    [portfolio.Component("only", 0.9, float_present([#(1, 0.1)]))],
    missing: portfolio.RequireAll,
    weight_tolerance: 0.000_001,
  )
  |> should.equal(Error(portfolio.WeightsDoNotSum(0.9)))
  portfolio.weighted_returns(
    [
      portfolio.Component("same", 0.5, float_present([#(1, 0.1)])),
      portfolio.Component("same", 0.5, float_present([#(1, 0.2)])),
    ],
    missing: portfolio.RequireAll,
    weight_tolerance: 0.000_001,
  )
  |> should.equal(Error(portfolio.DuplicateComponent("same")))
}

pub fn cumulative_wealth_and_drawdown_make_gap_policy_explicit_test() {
  let returns =
    values([
      series.Point(at(1), series.Present(0.1)),
      series.Point(at(2), series.Missing(observation.Unavailable)),
      series.Point(at(3), series.Present(0.1)),
    ])
  let assert Ok(resumed) =
    path.wealth_index(
      returns,
      initial_value: 1.0,
      missing: path.SkipMissingReturn,
    )
  let assert Ok(invalidated) =
    path.wealth_index(
      returns,
      initial_value: 1.0,
      missing: path.InvalidateAfterMissing,
    )
  expect_series(resumed, [Some(1.1), None, Some(1.21)], tolerance: 0.000_001)
  expect_series(invalidated, [Some(1.1), None, None], tolerance: 0.000_001)

  let assert Ok(drawdowns) =
    path.drawdown(
      float_present([#(1, 100.0), #(2, 120.0), #(3, 90.0), #(4, 150.0)]),
      missing: path.SkipMissingReturn,
    )
  expect_series(
    drawdowns,
    [Some(0.0), Some(0.0), Some(-0.25), Some(0.0)],
    tolerance: 0.000_001,
  )
}

pub fn dynamic_weights_return_total_and_component_contribution_series_test() {
  let components = [
    portfolio.DynamicComponent(
      "a",
      float_present([#(1, 0.6), #(2, 0.5)]),
      float_present([#(1, 0.1), #(2, 0.2)]),
    ),
    portfolio.DynamicComponent(
      "b",
      float_present([#(1, 0.4), #(2, 0.5)]),
      float_present([#(1, 0.05), #(2, 0.1)]),
    ),
  ]
  let assert Ok(portfolio.Attribution(total, contributions)) =
    portfolio.dynamic_attribution(
      components,
      missing: portfolio.RequireAll,
      weight_tolerance: 0.000_001,
    )
  expect_series(total, [Some(0.08), Some(0.15)], tolerance: 0.000_001)
  let assert [
    portfolio.ComponentContribution("a", a),
    portfolio.ComponentContribution("b", b),
  ] = contributions
  expect_series(a, [Some(0.06), Some(0.1)], tolerance: 0.000_001)
  expect_series(b, [Some(0.02), Some(0.05)], tolerance: 0.000_001)
}

pub fn dynamic_attribution_rejects_bad_weights_at_the_observation_test() {
  portfolio.dynamic_attribution(
    [
      portfolio.DynamicComponent(
        "a",
        float_present([#(1, 0.7)]),
        float_present([#(1, 0.1)]),
      ),
      portfolio.DynamicComponent(
        "b",
        float_present([#(1, 0.4)]),
        float_present([#(1, 0.1)]),
      ),
    ],
    missing: portfolio.RequireAll,
    weight_tolerance: 0.000_001,
  )
  |> should.equal(Error(portfolio.WeightsDoNotSumAt(at(1), 1.1)))
}

pub fn dynamic_attribution_renormalization_is_explicit_and_attributed_test() {
  let components = [
    portfolio.DynamicComponent(
      "a",
      float_present([#(1, 0.6)]),
      float_present([#(1, 0.1)]),
    ),
    portfolio.DynamicComponent(
      "b",
      float_present([#(1, 0.4)]),
      float_present([]),
    ),
  ]
  let assert Ok(portfolio.Attribution(total, contributions)) =
    portfolio.dynamic_attribution(
      components,
      missing: portfolio.RenormalizeAvailable,
      weight_tolerance: 0.000_001,
    )
  expect_series(total, [Some(0.1)], tolerance: 0.000_001)
  let assert [
    portfolio.ComponentContribution("a", a),
    portfolio.ComponentContribution("b", b),
  ] = contributions
  expect_series(a, [Some(0.1)], tolerance: 0.000_001)
  expect_series(b, [None], tolerance: 0.000_001)
}

pub fn as_of_join_is_backward_looking_and_staleness_bounded_test() {
  let left = present([#(10, "a"), #(20, "b"), #(40, "c")])
  let right = present([#(5, 100), #(20, 200), #(30, 300)])

  as_of.join(left, right, maximum_staleness: duration(10))
  |> should.equal([
    as_of.Match(
      at(10),
      series.Present("a"),
      Some(series.Present(100)),
      Some(at(5)),
    ),
    as_of.Match(
      at(20),
      series.Present("b"),
      Some(series.Present(200)),
      Some(at(20)),
    ),
    as_of.Match(
      at(40),
      series.Present("c"),
      Some(series.Present(300)),
      Some(at(30)),
    ),
  ])
  as_of.join(left, right, maximum_staleness: duration(4))
  |> should.equal([
    as_of.Match(at(10), series.Present("a"), None, None),
    as_of.Match(
      at(20),
      series.Present("b"),
      Some(series.Present(200)),
      Some(at(20)),
    ),
    as_of.Match(at(40), series.Present("c"), None, None),
  ])
}

pub fn ohlcv_aggregation_preserves_exact_prices_and_missing_policy_test() {
  let trades = [
    series.Present(bar.Trade(decimal("10"), decimal("2"))),
    series.Present(bar.Trade(decimal("12"), decimal("3"))),
    series.Missing(observation.NotReported),
    series.Present(bar.Trade(decimal("11"), decimal("4"))),
  ]
  bar.aggregate(trades, missing: bar.SkipMissing)
  |> should.equal(
    Ok(
      series.Present(bar.Bar(
        decimal("10"),
        decimal("12"),
        decimal("10"),
        decimal("11"),
        decimal("9"),
        3,
      )),
    ),
  )
  bar.aggregate(trades, missing: bar.PropagateMissing)
  |> should.equal(Ok(series.Missing(observation.NotReported)))
  bar.aggregate(trades, missing: bar.RejectMissing)
  |> should.equal(Error(bar.MissingTrade(observation.NotReported)))
}

pub fn exact_chain_linking_never_uses_binary_float_test() {
  decimal.add(decimal("1"), decimal("-0.5"))
  |> should.equal(decimal("0.5"))
  let returns = decimal_present([#(1, "0.1"), #(2, "0.2"), #(3, "-0.5")])
  let assert Ok(wealth) =
    exact_path.wealth_index(
      returns,
      initial_value: decimal("1"),
      missing: path.SkipMissingReturn,
    )

  series.present_values(wealth)
  |> list.map(fn(pair) { decimal.to_string(pair.1) })
  |> should.equal(["1.1", "1.32", "0.66"])
}

pub fn observation_adapter_preserves_envelopes_and_explicit_missing_test() {
  let present_observation = observed_value(1, observation.Reported, "10")
  let missing_observation =
    observed_value(2, observation.Missing(observation.NotReported), "ignored")
  let assert Ok(timeline) =
    observed.from_observations([present_observation, missing_observation])

  series.to_list(timeline)
  |> should.equal([
    series.Point(at(1), series.Present(present_observation)),
    series.Point(at(2), series.Missing(observation.NotReported)),
  ])
}

fn at(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}

fn duration(milliseconds: Int) -> time.Duration {
  let assert Ok(value) = time.duration(milliseconds)
  value
}

fn observed_value(
  milliseconds: Int,
  quality: observation.Quality,
  value: String,
) -> observation.Observation(String) {
  let assert Ok(source_ref) =
    source.new(
      provider: "synthetic",
      reference: "series",
      kind: source.Synthetic,
    )
  observation.Observation(
    value: value,
    as_of: at(milliseconds),
    retrieved_at: at(milliseconds),
    source: source_ref,
    evidence_id: Some("evidence"),
    freshness: observation.UnknownFreshness,
    entitlement: observation.UnknownEntitlement,
    quality: quality,
    unit: Some(market.Scalar),
    adjustment: Some(adjustment.Raw),
    session: Some(market.Regular),
  )
}

fn values(points: List(series.Point(value))) -> series.Series(value) {
  let assert Ok(value) = series.new(points)
  value
}

fn present(points: List(#(Int, value))) -> series.Series(value) {
  let assert Ok(value) =
    points
    |> list.map(fn(pair) { #(at(pair.0), pair.1) })
    |> series.from_present
  value
}

fn float_present(points: List(#(Int, Float))) -> series.Series(Float) {
  present(points)
}

fn decimal_present(
  points: List(#(Int, String)),
) -> series.Series(decimal.Decimal) {
  points |> list.map(fn(pair) { #(pair.0, decimal(pair.1)) }) |> present
}

fn decimal(value: String) -> decimal.Decimal {
  let assert Ok(value) = decimal.parse(value)
  value
}

fn expect_close(
  result: Result(Float, analytics.AnalyticsError),
  expected: Float,
) -> Nil {
  let assert Ok(value) = result
  { float.absolute_value(value -. expected) <=. 0.000_001 }
  |> should.be_true
}

fn expect_series(
  values: series.Series(Float),
  expected: List(Option(Float)),
  tolerance tolerance: Float,
) -> Nil {
  let actual =
    values
    |> series.to_list
    |> list.map(fn(point) {
      case point.datum {
        series.Present(value) -> Some(value)
        series.Missing(_) -> None
      }
    })
  let paired = list.zip(actual, expected)
  {
    list.length(actual) == list.length(expected)
    && list.all(paired, fn(pair) {
      case pair.0, pair.1 {
        None, None -> True
        Some(left), Some(right) ->
          float.absolute_value(left -. right) <=. tolerance
        _, _ -> False
      }
    })
  }
  |> should.be_true
}
