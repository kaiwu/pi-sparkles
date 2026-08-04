import finance_core/currency
import finance_core/decimal
import finance_core/observation
import finance_core/time
import finance_math
import finance_math/cashflow
import finance_math/error
import finance_math/exact
import finance_math/fixed_income
import finance_math/formula
import finance_math/metric
import finance_math/metrics
import finance_math/regression
import finance_math/risk
import finance_math/root
import finance_math/statistics
import finance_math/weighted
import gleam/float
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_implementing_test() {
  finance_math.status()
  |> should.equal(finance_math.Implementing)
}

pub fn exact_ratios_never_hide_zero_or_rounding_policy_test() {
  exact.growth(decimal("125"), decimal("100"), 4, decimal.HalfEven)
  |> should.equal(Ok(decimal("0.25")))
  exact.percentage(decimal("1"), decimal("8"), 2, decimal.HalfUp)
  |> should.equal(Ok(decimal("12.5")))
  exact.ratio(decimal("1"), decimal("0"), 2, decimal.HalfEven)
  |> should.equal(Error(error.DivisionByZero))
  exact.mean([], 2, decimal.HalfEven)
  |> should.equal(Error(error.EmptyInput))
}

pub fn formulas_compose_arbitrary_exact_finance_metrics_test() {
  let invested_capital =
    formula.Subtract(
      formula.Add(formula.Reference("debt"), formula.Reference("equity")),
      formula.Reference("cash"),
    )
  let roic =
    metrics.ratio(
      formula.Reference("nopat"),
      invested_capital,
      4,
      decimal.HalfEven,
    )
  let inputs = [
    available("nopat", "24"),
    available("debt", "40"),
    available("equity", "100"),
    available("cash", "20"),
  ]

  formula.evaluate(roic, with: inputs)
  |> should.equal(Ok(decimal("0.2")))
  formula.references(roic)
  |> should.equal(["nopat", "debt", "equity", "cash"])
}

pub fn formulas_propagate_missing_unknown_and_duplicate_inputs_test() {
  let ratio =
    metrics.ratio(
      formula.Reference("income"),
      formula.Reference("assets"),
      4,
      decimal.HalfEven,
    )

  formula.evaluate(ratio, with: [
    formula.Input("income", formula.Missing(observation.NotReported)),
    available("assets", "10"),
  ])
  |> should.equal(Error(error.MissingInput("income", observation.NotReported)))
  formula.evaluate(ratio, with: [available("income", "2")])
  |> should.equal(Error(error.UnknownInput("assets")))
  formula.evaluate(ratio, with: [
    available("income", "2"),
    available("income", "3"),
  ])
  |> should.equal(Error(error.DuplicateInput("income")))
}

pub fn metric_results_retain_units_inputs_and_assumptions_test() {
  let expression =
    metrics.per_share(
      formula.Reference("earnings"),
      formula.Reference("diluted_shares"),
      2,
      decimal.HalfEven,
    )
  let assumptions = [metric.Assumption("share_basis", "weighted diluted")]
  let assert Ok(usd) = currency.from_code("USD")
  let assert Ok(definition) =
    metric.define(
      name: "diluted_eps",
      unit: metric.CurrencyPerShare(usd),
      formula: expression,
      assumptions: assumptions,
    )

  metric.calculate(definition, [
    available("earnings", "150"),
    available("diluted_shares", "60"),
  ])
  |> should.equal(
    Ok(metric.Metric(
      "diluted_eps",
      decimal("2.5"),
      metric.CurrencyPerShare(usd),
      ["earnings", "diluted_shares"],
      assumptions,
    )),
  )
}

pub fn descriptive_risk_and_relative_statistics_are_explicit_test() {
  expect_close(statistics.mean([1.0, 2.0, 3.0]), 2.0, 0.000_001)
  expect_close(
    statistics.variance([1.0, 2.0, 3.0], statistics.Population),
    2.0 /. 3.0,
    0.000_001,
  )
  expect_close(
    statistics.beta([0.02, 0.04, 0.06], [0.01, 0.02, 0.03], statistics.Sample),
    2.0,
    0.000_001,
  )
  statistics.correlation([1.0, 1.0, 1.0], [1.0, 2.0, 3.0], statistics.Sample)
  |> should.equal(Error(error.ZeroVariance))
}

pub fn returns_drawdown_var_and_growth_have_declared_domains_test() {
  statistics.simple_returns([100.0, 110.0, 99.0])
  |> expect_float_list([0.1, -0.1], 0.000_001)
  expect_close(
    statistics.maximum_drawdown([100.0, 120.0, 90.0, 150.0]),
    0.25,
    0.000_001,
  )
  expect_close(
    statistics.historical_value_at_risk([-0.1, -0.02, 0.01, 0.03], 0.75),
    0.02,
    0.000_001,
  )
  expect_close(
    statistics.compound_growth_rate(100.0, 121.0, 2.0),
    0.1,
    0.000_001,
  )
}

pub fn root_and_cash_flow_metrics_are_bounded_and_deterministic_test() {
  expect_close(
    root.bisection(
      fn(value) { Ok(value *. value -. 2.0) },
      lower: 0.0,
      upper: 2.0,
      tolerance: 0.000_000_1,
      maximum_iterations: 100,
    ),
    1.414_213_56,
    0.000_001,
  )
  expect_close(
    cashflow.internal_rate_of_return(
      [-100.0, 110.0],
      lower: 0.0,
      upper: 1.0,
      tolerance: 0.000_000_1,
      maximum_iterations: 100,
    ),
    0.1,
    0.000_001,
  )
  root.bisection(
    fn(value) { Ok(value *. value +. 1.0) },
    lower: -1.0,
    upper: 1.0,
    tolerance: 0.000_1,
    maximum_iterations: 20,
  )
  |> should.equal(Error(error.RootNotBracketed))
}

pub fn dated_cash_flow_metrics_make_day_count_explicit_test() {
  let assert Ok(start) = time.instant(0)
  let assert Ok(one_year) = time.instant(31_536_000_000)
  let flows = [
    cashflow.TimedCashFlow(-100.0, start),
    cashflow.TimedCashFlow(110.0, one_year),
  ]

  expect_close(
    cashflow.dated_internal_rate_of_return(
      flows,
      365.0,
      lower: 0.0,
      upper: 1.0,
      tolerance: 0.000_000_1,
      maximum_iterations: 100,
    ),
    0.1,
    0.000_001,
  )
}

pub fn weighted_estimators_validate_and_normalize_reliability_weights_test() {
  expect_close(weighted.mean([1.0, 3.0], [1.0, 3.0]), 2.5, 0.000_001)
  expect_close(
    weighted.variance([1.0, 3.0], [1.0, 3.0], statistics.Population),
    0.75,
    0.000_001,
  )
  weighted.mean([1.0], [-1.0])
  |> should.equal(Error(error.InvalidWeight))
  weighted.mean([1.0, 2.0], [0.0, 0.0])
  |> should.equal(Error(error.ZeroWeight))
}

pub fn tail_and_downside_risk_policies_are_deterministic_test() {
  expect_close(
    risk.historical_expected_shortfall([-0.1, -0.05, 0.02, 0.03], 0.5),
    0.075,
    0.000_001,
  )
  expect_close(
    risk.downside_deviation(
      [-0.1, -0.05, 0.02, 0.03],
      0.0,
      statistics.Population,
    ),
    0.055_901_699,
    0.000_001,
  )
  expect_close(
    risk.sharpe_ratio([0.01, 0.02, 0.03], 0.0, 1, statistics.Sample),
    2.0,
    0.000_001,
  )
  expect_close(risk.omega_ratio([-0.1, 0.2, 0.3], 0.0), 5.0, 0.000_001)
}

pub fn multi_factor_regression_returns_coefficients_and_diagnostics_test() {
  let assert Ok(model) =
    regression.ordinary_least_squares(
      [1.0, 3.0, 4.0, 6.0, 8.0],
      [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0], [2.0, 1.0]],
      include_intercept: True,
      singular_tolerance: 0.000_000_001,
    )

  { float.absolute_value(model.intercept -. 1.0) <=. 0.000_001 }
  |> should.be_true
  expect_plain_list(model.coefficients, [2.0, 3.0], 0.000_001)
  { float.absolute_value(model.r_squared -. 1.0) <=. 0.000_001 }
  |> should.be_true
  expect_close(regression.predict(model, [3.0, 2.0]), 13.0, 0.000_001)

  regression.ordinary_least_squares(
    [1.0, 2.0, 3.0, 4.0],
    [[1.0, 1.0], [2.0, 2.0], [3.0, 3.0], [4.0, 4.0]],
    include_intercept: False,
    singular_tolerance: 0.000_000_001,
  )
  |> should.equal(Error(error.SingularSystem))
}

pub fn fixed_income_sensitivity_declares_compounding_test() {
  let cash_flows = [fixed_income.CashFlow(100.0, 2.0)]
  expect_close(
    fixed_income.present_value(cash_flows, 0.0, fixed_income.Periodic(1)),
    100.0,
    0.000_001,
  )
  let assert Ok(sensitivity) =
    fixed_income.sensitivity(cash_flows, 0.0, fixed_income.Periodic(1))
  { float.absolute_value(sensitivity.macaulay_duration -. 2.0) <=. 0.000_001 }
  |> should.be_true
  { float.absolute_value(sensitivity.modified_duration -. 2.0) <=. 0.000_001 }
  |> should.be_true
  { float.absolute_value(sensitivity.convexity -. 6.0) <=. 0.000_001 }
  |> should.be_true
  { float.absolute_value(sensitivity.dv01 -. 0.02) <=. 0.000_001 }
  |> should.be_true
  fixed_income.present_value(cash_flows, 0.05, fixed_income.Periodic(0))
  |> should.equal(Error(error.InvalidCompounding))
}

fn available(name: String, value: String) -> formula.Input {
  formula.Input(name, formula.Available(decimal(value)))
}

fn decimal(value: String) -> decimal.Decimal {
  let assert Ok(value) = decimal.parse(value)
  value
}

fn expect_close(
  result: Result(Float, error.MetricError),
  expected: Float,
  tolerance: Float,
) -> Nil {
  let assert Ok(value) = result
  { float.absolute_value(value -. expected) <=. tolerance }
  |> should.be_true
}

fn expect_float_list(
  result: Result(List(Float), error.MetricError),
  expected: List(Float),
  tolerance: Float,
) -> Nil {
  let assert Ok(values) = result
  let paired = list.zip(values, expected)
  {
    list.length(values) == list.length(expected)
    && list.all(paired, fn(pair) {
      float.absolute_value(pair.0 -. pair.1) <=. tolerance
    })
  }
  |> should.be_true
}

fn expect_plain_list(
  values: List(Float),
  expected: List(Float),
  tolerance: Float,
) -> Nil {
  expect_float_list(Ok(values), expected, tolerance)
}
