import finance_core/decimal
import finance_math/error
import finance_sec/derivation
import finance_sec/fundamentals
import finance_sec/periods
import finance_sec/xbrl
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_fundamentals/guide
import pi_sparkles_stock_fundamentals/metrics

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn guide_is_small_and_exposes_the_safe_default_test() {
  let text = guide.text()
  text |> string.contains("stock_fundamental_period") |> should.be_true
  text |> string.contains("exact accession") |> should.be_true
  text |> string.contains("stock_fundamental_metric") |> should.be_true
}

pub fn initial_registry_is_small_and_auditable_test() {
  let metrics = [
    fundamentals.Revenue,
    fundamentals.NetIncome,
    fundamentals.Assets,
    fundamentals.CashAndEquivalents,
    fundamentals.OperatingCashFlow,
    fundamentals.CapitalExpendituresReported,
    fundamentals.DilutedWeightedAverageShares,
  ]
  metrics |> list.length |> should.equal(7)
  metrics
  |> list.map(fn(metric) { fundamentals.definition(metric).method })
  |> list.all(fn(method) { method != "" })
  |> should.be_true
}

pub fn exact_multi_input_metrics_retain_named_sources_test() {
  let operating =
    candidate(
      fundamentals.OperatingCashFlow,
      "120",
      "USD",
      "NetCashProvidedByUsedInOperatingActivities",
      "annual",
    )
  let capex =
    candidate(
      fundamentals.CapitalExpendituresReported,
      "20",
      "USD",
      "PaymentsToAcquirePropertyPlantAndEquipment",
      "annual",
    )
  let assert Ok(free_cash_flow) =
    metrics.calculate(
      metrics.FreeCashFlow,
      [operating, capex],
      periods.Annual,
      4,
    )
  decimal.to_string(free_cash_flow.calculation.value)
  |> should.equal("100")
  free_cash_flow.output_unit |> should.equal("USD")
  free_cash_flow.sources
  |> list.map(fn(source) { source.name })
  |> should.equal([
    "operating_cash_flow",
    "capital_expenditures_reported",
  ])

  let net_income =
    candidate(fundamentals.NetIncome, "25", "USD", "NetIncomeLoss", "annual")
  let revenue =
    candidate(
      fundamentals.Revenue,
      "100",
      "USD",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "annual",
    )
  let assert Ok(net_margin) =
    metrics.calculate(
      metrics.NetMargin,
      [net_income, revenue],
      periods.Annual,
      4,
    )
  decimal.to_string(net_margin.calculation.value) |> should.equal("25")
  net_margin.output_unit |> should.equal("percentage_points")

  let diluted_shares =
    candidate(
      fundamentals.DilutedWeightedAverageShares,
      "4",
      "shares",
      "WeightedAverageNumberOfDilutedSharesOutstanding",
      "annual",
    )
  let assert Ok(eps) =
    metrics.calculate(
      metrics.DilutedEarningsPerShare,
      [net_income, diluted_shares],
      periods.Annual,
      4,
    )
  decimal.to_string(eps.calculation.value) |> should.equal("6.25")
  eps.output_unit |> should.equal("USD/share")
}

pub fn metric_derivation_rejects_incoherent_sources_and_zero_bases_test() {
  let income =
    candidate(fundamentals.NetIncome, "10", "USD", "NetIncomeLoss", "annual")
  let other_filing_revenue =
    candidate(
      fundamentals.Revenue,
      "100",
      "USD",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "other-accession",
    )
  metrics.calculate(
    metrics.NetMargin,
    [income, other_filing_revenue],
    periods.Annual,
    4,
  )
  |> should.equal(Error(metrics.SourceFilingMismatch("revenue")))

  let zero_revenue =
    candidate(
      fundamentals.Revenue,
      "0",
      "USD",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "annual",
    )
  metrics.calculate(
    metrics.NetMargin,
    [income, zero_revenue],
    periods.Annual,
    4,
  )
  |> should.equal(Error(metrics.CalculationFailed(error.DivisionByZero)))
}

pub fn growth_series_requires_the_explicit_calendar_gap_test() {
  let first = quarter_candidate("100", "2024-01-01", "2024-03-31", "q1")
  let second = quarter_candidate("110", "2024-04-01", "2024-06-30", "q2")
  let third = quarter_candidate("121", "2024-07-01", "2024-09-30", "q3")
  let assert Ok(trend) =
    derivation.trend([third, first, second], periods.Quarter)
  let assert Ok(growth) =
    metrics.growth_series(trend, metrics.QuarterOverQuarter, 4)
  growth.points
  |> list.map(fn(point) { decimal.to_string(point.calculation.value) })
  |> should.equal(["10", "10"])
  growth.points
  |> list.map(fn(point) { point.previous.fact.accession })
  |> should.equal(["q1", "q2"])

  let prior_year =
    quarter_candidate("80", "2023-01-01", "2023-03-31", "prior-year")
  let assert Ok(yearly_trend) =
    derivation.trend([first, prior_year], periods.Quarter)
  let assert Ok(yearly_growth) =
    metrics.growth_series(yearly_trend, metrics.YearOverYear, 4)
  let assert [point] = yearly_growth.points
  decimal.to_string(point.calculation.value) |> should.equal("25")
  metrics.growth_series(yearly_trend, metrics.QuarterOverQuarter, 4)
  |> should.equal(Error(metrics.GrowthGapMismatch("2023-03-31", "2024-03-31")))
}

pub fn trailing_twelve_months_requires_four_contiguous_additive_quarters_test() {
  let q1 = quarter_candidate("10", "2024-01-01", "2024-03-31", "q1")
  let q2 = quarter_candidate("20", "2024-04-01", "2024-06-30", "q2")
  let q3 = quarter_candidate("30", "2024-07-01", "2024-09-30", "q3")
  let q4 = quarter_candidate("40", "2024-10-01", "2024-12-31", "q4")
  let assert Ok(trend) = derivation.trend([q4, q2, q1, q3], periods.Quarter)
  let assert Ok(trailing) = metrics.trailing_twelve_months(trend)
  decimal.to_string(trailing.calculation.value) |> should.equal("100")
  trailing.start |> should.equal("2024-01-01")
  trailing.end |> should.equal("2024-12-31")
  trailing.sources
  |> list.map(fn(source) { source.candidate.fact.accession })
  |> should.equal(["q1", "q2", "q3", "q4"])

  let broken_q2 = quarter_candidate("20", "2024-04-02", "2024-06-30", "q2")
  let assert Ok(broken_trend) =
    derivation.trend([q1, broken_q2, q3, q4], periods.Quarter)
  metrics.trailing_twelve_months(broken_trend)
  |> should.equal(
    Error(metrics.NonContiguousQuarter("2024-03-31", "2024-04-02")),
  )

  let short_1 = quarter_candidate("10", "2024-01-01", "2024-03-01", "s1")
  let short_2 = quarter_candidate("20", "2024-03-02", "2024-05-01", "s2")
  let short_3 = quarter_candidate("30", "2024-05-02", "2024-07-01", "s3")
  let short_4 = quarter_candidate("40", "2024-07-02", "2024-08-31", "s4")
  let assert Ok(short_trend) =
    derivation.trend([short_1, short_2, short_3, short_4], periods.Quarter)
  metrics.trailing_twelve_months(short_trend)
  |> should.equal(Error(metrics.TrailingWindowMismatch))
}

pub fn annual_ytd_bridge_proves_fiscal_and_comparable_windows_test() {
  let annual =
    period_candidate(
      fundamentals.Revenue,
      "1000",
      "USD",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "annual-2024",
      "2024-01-01",
      "2024-12-31",
    )
  let prior_ytd =
    period_candidate(
      fundamentals.Revenue,
      "700",
      "USD",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "ytd-2024",
      "2024-01-01",
      "2024-09-30",
    )
  let current_ytd =
    period_candidate(
      fundamentals.Revenue,
      "800",
      "USD",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "ytd-2025",
      "2025-01-01",
      "2025-09-30",
    )
  let assert Ok(trailing) =
    metrics.trailing_twelve_months_bridge(annual, current_ytd, prior_ytd)
  decimal.to_string(trailing.calculation.value) |> should.equal("1100")
  trailing.start |> should.equal("2024-10-01")
  trailing.end |> should.equal("2025-09-30")
  trailing.sources
  |> list.map(fn(source) { source.name })
  |> should.equal(["annual", "current_ytd", "prior_ytd"])

  let wrong_current_start =
    period_candidate(
      fundamentals.Revenue,
      "800",
      "USD",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "ytd-2025",
      "2025-01-02",
      "2025-09-30",
    )
  metrics.trailing_twelve_months_bridge(annual, wrong_current_start, prior_ytd)
  |> should.equal(Error(metrics.CurrentFiscalStartMismatch))
}

pub fn composed_ttm_expands_derived_q4_into_source_formula_leaves_test() {
  let annual =
    period_candidate(
      fundamentals.Revenue,
      "100",
      "USD",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "annual",
      "2024-01-01",
      "2024-12-31",
    )
  let nine_month =
    period_candidate(
      fundamentals.Revenue,
      "70",
      "USD",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "nine-month",
      "2024-01-01",
      "2024-09-30",
    )
  let assert Ok(q4) = derivation.q4(annual, nine_month)
  let q1 = quarter_candidate("40", "2025-01-01", "2025-03-31", "q1")
  let q2 = quarter_candidate("50", "2025-04-01", "2025-06-30", "q2")
  let q3 = quarter_candidate("60", "2025-07-01", "2025-09-30", "q3")
  let assert Ok(trailing) =
    metrics.composed_trailing_twelve_months([
      metrics.DirectQuarter(q2),
      metrics.DerivedQuarter(q4),
      metrics.DirectQuarter(q3),
      metrics.DirectQuarter(q1),
    ])
  decimal.to_string(trailing.calculation.value) |> should.equal("180")
  trailing.start |> should.equal("2024-10-01")
  trailing.end |> should.equal("2025-09-30")
  trailing.calculation.input_names
  |> should.equal([
    "quarter_1_annual",
    "quarter_1_nine_month_ytd",
    "quarter_2",
    "quarter_3",
    "quarter_4",
  ])
  let assert [first, _, _, _] = trailing.quarters
  case first.observation {
    metrics.DerivedQuarter(value) ->
      value.annual.fact.accession |> should.equal("annual")
    _ -> should.fail()
  }

  let broken_q1 =
    quarter_candidate("40", "2025-01-02", "2025-03-31", "broken-q1")
  metrics.composed_trailing_twelve_months([
    metrics.DerivedQuarter(q4),
    metrics.DirectQuarter(broken_q1),
    metrics.DirectQuarter(q2),
    metrics.DirectQuarter(q3),
  ])
  |> should.equal(
    Error(metrics.NonContiguousQuarter("2024-12-31", "2025-01-02")),
  )
}

fn candidate(
  metric: fundamentals.Metric,
  raw: String,
  unit: String,
  tag: String,
  accession: String,
) -> fundamentals.Candidate {
  period_candidate(
    metric,
    raw,
    unit,
    tag,
    accession,
    "2024-01-01",
    "2024-12-31",
  )
}

fn quarter_candidate(
  raw: String,
  start: String,
  end: String,
  accession: String,
) -> fundamentals.Candidate {
  period_candidate(
    fundamentals.Revenue,
    raw,
    "USD",
    "RevenueFromContractWithCustomerExcludingAssessedTax",
    accession,
    start,
    end,
  )
}

fn period_candidate(
  metric: fundamentals.Metric,
  raw: String,
  unit: String,
  tag: String,
  accession: String,
  start: String,
  end: String,
) -> fundamentals.Candidate {
  let assert Ok(value) = decimal.parse(raw)
  let assert Ok(concept) = xbrl.concept_id("us-gaap", tag)
  fundamentals.Candidate(
    metric,
    value,
    raw,
    unit,
    concept,
    xbrl.Fact(
      Some(start),
      end,
      xbrl.Numeric(raw),
      accession,
      Some("2024"),
      Some("FY"),
      "10-K",
      end,
      None,
    ),
  )
}
