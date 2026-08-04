import finance_core/currency
import finance_core/decimal
import finance_math/error.{type MetricError}
import finance_math/formula.{type Formula}
import finance_math/metric as math_metric
import finance_math/metrics as formulas
import finance_sec/derivation
import finance_sec/fundamentals.{type Candidate, type Metric}
import finance_sec/periods
import finance_sec/xbrl
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string

pub type Kind {
  FreeCashFlow
  NetMargin
  DilutedEarningsPerShare
}

pub type NamedSource {
  NamedSource(name: String, candidate: Candidate)
}

pub type Derived {
  Derived(
    kind: Kind,
    calculation: math_metric.Metric,
    formula: Formula,
    output_unit: String,
    period_class: periods.Class,
    start: String,
    end: String,
    sources: List(NamedSource),
    method: String,
  )
}

pub type GrowthGap {
  QuarterOverQuarter
  YearOverYear
}

pub type GrowthPoint {
  GrowthPoint(
    calculation: math_metric.Metric,
    formula: Formula,
    previous: Candidate,
    current: Candidate,
    method: String,
  )
}

pub type GrowthSeries {
  GrowthSeries(
    metric: Metric,
    unit: String,
    period_class: periods.Class,
    gap: GrowthGap,
    points: List(GrowthPoint),
  )
}

pub type TrailingTwelveMonths {
  TrailingTwelveMonths(
    metric: Metric,
    calculation: math_metric.Metric,
    formula: Formula,
    output_unit: String,
    start: String,
    end: String,
    sources: List(NamedSource),
    method: String,
  )
}

pub type QuarterObservation {
  DirectQuarter(candidate: Candidate)
  DerivedQuarter(value: derivation.DerivedQ4)
}

pub type QuarterEvidence {
  QuarterEvidence(name: String, observation: QuarterObservation)
}

pub type ComposedTrailingTwelveMonths {
  ComposedTrailingTwelveMonths(
    metric: Metric,
    calculation: math_metric.Metric,
    formula: Formula,
    output_unit: String,
    start: String,
    end: String,
    quarters: List(QuarterEvidence),
    method: String,
  )
}

type QuarterData {
  QuarterData(
    observation: QuarterObservation,
    metric: Metric,
    value: decimal.Decimal,
    unit: String,
    concept: xbrl.ConceptId,
    start: String,
    end: String,
  )
}

type QuarterFormulaParts {
  QuarterFormulaParts(
    formulas: List(Formula),
    inputs: List(formula.Input),
    evidence: List(QuarterEvidence),
  )
}

pub type DeriveError {
  InvalidScale
  WrongInputCount
  InputMetricMismatch(name: String, expected: Metric, actual: Metric)
  InputUnitMismatch(left: String, right: String)
  InvalidCurrencyUnit(value: String)
  ExpectedSharesUnit(actual: String)
  InvalidPeriod(name: String, error: periods.PeriodError)
  PeriodClassMismatch(name: String)
  MissingDurationStart(name: String)
  SourcePeriodMismatch(name: String)
  SourceFilingMismatch(name: String)
  TooFewGrowthPoints
  GrowthGapInvalid(previous_end: String, current_end: String)
  GrowthGapMismatch(previous_end: String, current_end: String)
  ExpectedFourQuarters
  ExpectedQuarterTrend
  UnsupportedTrailingMetric
  NonContiguousQuarter(previous_end: String, current_start: String)
  TrailingWindowInvalid
  TrailingWindowMismatch
  BridgeMetricMismatch
  BridgeUnitMismatch
  BridgeConceptMismatch
  ExpectedAnnualSource
  ExpectedComparableYtd
  YtdClassMismatch
  PriorYtdFiscalStartMismatch
  CurrentFiscalStartMismatch
  InvalidDirectQuarter(accession: String, error: periods.PeriodError)
  ExpectedDirectQuarter(accession: String)
  InvalidDerivedQuarter(error: derivation.Q4Error)
  QuarterMetricMismatch
  QuarterUnitMismatch
  QuarterConceptMismatch
  CalculationFailed(MetricError)
}

pub fn growth_gap(name: String) -> Result(GrowthGap, Nil) {
  case string.lowercase(name) {
    "quarter_over_quarter" -> Ok(QuarterOverQuarter)
    "year_over_year" -> Ok(YearOverYear)
    _ -> Error(Nil)
  }
}

pub fn growth_gap_name(value: GrowthGap) -> String {
  case value {
    QuarterOverQuarter -> "quarter_over_quarter"
    YearOverYear -> "year_over_year"
  }
}

pub fn kind(name: String) -> Result(Kind, Nil) {
  case string.lowercase(name) {
    "free_cash_flow" -> Ok(FreeCashFlow)
    "net_margin" -> Ok(NetMargin)
    "diluted_eps" -> Ok(DilutedEarningsPerShare)
    _ -> Error(Nil)
  }
}

pub fn kind_name(value: Kind) -> String {
  case value {
    FreeCashFlow -> "free_cash_flow"
    NetMargin -> "net_margin"
    DilutedEarningsPerShare -> "diluted_eps"
  }
}

pub fn required_inputs(value: Kind) -> List(#(String, Metric)) {
  case value {
    FreeCashFlow -> [
      #("operating_cash_flow", fundamentals.OperatingCashFlow),
      #(
        "capital_expenditures_reported",
        fundamentals.CapitalExpendituresReported,
      ),
    ]
    NetMargin -> [
      #("net_income", fundamentals.NetIncome),
      #("revenue", fundamentals.Revenue),
    ]
    DilutedEarningsPerShare -> [
      #("net_income", fundamentals.NetIncome),
      #(
        "diluted_weighted_average_shares",
        fundamentals.DilutedWeightedAverageShares,
      ),
    ]
  }
}

pub fn calculate(
  kind kind: Kind,
  candidates candidates: List(Candidate),
  period_class period_class: periods.Class,
  scale scale: Int,
) -> Result(Derived, DeriveError) {
  case scale >= 0 && scale <= 18, candidates {
    False, _ -> Error(InvalidScale)
    _, [] -> Error(WrongInputCount)
    True, [first, ..] -> {
      use sources <- result.try(
        validate_inputs(required_inputs(kind), candidates, period_class, []),
      )
      use _ <- result.try(validate_source_context(sources, first))
      use #(expression, unit, output_unit, assumptions, method) <- result.try(
        definition(kind, candidates, scale),
      )
      use definition <- result.try(
        math_metric.define(
          name: kind_name(kind),
          unit: unit,
          formula: expression,
          assumptions: assumptions,
        )
        |> result.map_error(CalculationFailed),
      )
      let inputs =
        sources
        |> list.map(fn(source) {
          formula.Input(source.name, formula.Available(source.candidate.value))
        })
      use calculation <- result.try(
        math_metric.calculate(definition, inputs)
        |> result.map_error(CalculationFailed),
      )
      case first.fact.start {
        None -> Error(MissingDurationStart(sources_first_name(sources)))
        Some(start) ->
          Ok(Derived(
            kind,
            calculation,
            expression,
            output_unit,
            period_class,
            start,
            first.fact.end,
            sources,
            method,
          ))
      }
    }
  }
}

pub fn growth_series(
  trend: derivation.Trend,
  gap: GrowthGap,
  scale: Int,
) -> Result(GrowthSeries, DeriveError) {
  case scale >= 0 && scale <= 18, trend.points {
    False, _ -> Error(InvalidScale)
    _, [] | _, [_] -> Error(TooFewGrowthPoints)
    True, points -> {
      use growth_points <- result.try(
        build_growth_points(points, gap, scale, []),
      )
      Ok(GrowthSeries(
        trend.metric,
        trend.unit,
        trend.period_class,
        gap,
        growth_points,
      ))
    }
  }
}

pub fn trailing_twelve_months(
  trend: derivation.Trend,
) -> Result(TrailingTwelveMonths, DeriveError) {
  case trend.period_class, trend.points {
    periods.Quarter, [first, second, third, fourth] -> {
      case additive_metric(trend.metric) {
        False -> Error(UnsupportedTrailingMetric)
        True -> {
          use _ <- result.try(validate_contiguous(first, second))
          use _ <- result.try(validate_contiguous(second, third))
          use _ <- result.try(validate_contiguous(third, fourth))
          use start <- result.try(validate_trailing_window(first, fourth))
          use code <- result.try(valid_currency(trend.unit))
          let expression =
            formula.Sum([
              formula.Reference("quarter_1"),
              formula.Reference("quarter_2"),
              formula.Reference("quarter_3"),
              formula.Reference("quarter_4"),
            ])
          let assumptions = [
            math_metric.Assumption(
              "coverage",
              "four contiguous directly reported quarter facts",
            ),
          ]
          use definition <- result.try(
            math_metric.define(
              name: "trailing_twelve_months",
              unit: math_metric.Currency(code),
              formula: expression,
              assumptions: assumptions,
            )
            |> result.map_error(CalculationFailed),
          )
          let sources = [
            NamedSource("quarter_1", first),
            NamedSource("quarter_2", second),
            NamedSource("quarter_3", third),
            NamedSource("quarter_4", fourth),
          ]
          let inputs =
            sources
            |> list.map(fn(source) {
              formula.Input(
                source.name,
                formula.Available(source.candidate.value),
              )
            })
          use calculation <- result.try(
            math_metric.calculate(definition, inputs)
            |> result.map_error(CalculationFailed),
          )
          Ok(TrailingTwelveMonths(
            trend.metric,
            calculation,
            expression,
            currency.code(code),
            start,
            fourth.fact.end,
            sources,
            "sum of four contiguous directly reported quarter facts with identical metric, taxonomy tag, and unit; complete span must be annual-shaped",
          ))
        }
      }
    }
    periods.Quarter, _ -> Error(ExpectedFourQuarters)
    _, _ -> Error(ExpectedQuarterTrend)
  }
}

pub fn trailing_twelve_months_bridge(
  annual: Candidate,
  current_ytd: Candidate,
  prior_ytd: Candidate,
) -> Result(TrailingTwelveMonths, DeriveError) {
  case
    annual.metric == current_ytd.metric && annual.metric == prior_ytd.metric,
    additive_metric(annual.metric),
    annual.unit == current_ytd.unit && annual.unit == prior_ytd.unit,
    same_concept(annual, current_ytd) && same_concept(annual, prior_ytd)
  {
    False, _, _, _ -> Error(BridgeMetricMismatch)
    _, False, _, _ -> Error(UnsupportedTrailingMetric)
    _, _, False, _ -> Error(BridgeUnitMismatch)
    _, _, _, False -> Error(BridgeConceptMismatch)
    True, True, True, True -> {
      use annual_period <- result.try(
        periods.classify(annual.fact)
        |> result.map_error(fn(error) { InvalidPeriod("annual", error) }),
      )
      use current_period <- result.try(
        periods.classify(current_ytd.fact)
        |> result.map_error(fn(error) { InvalidPeriod("current_ytd", error) }),
      )
      use prior_period <- result.try(
        periods.classify(prior_ytd.fact)
        |> result.map_error(fn(error) { InvalidPeriod("prior_ytd", error) }),
      )
      case annual_period.class {
        periods.Annual ->
          case comparable_ytd(current_period.class, prior_period.class) {
            Error(error) -> Error(error)
            Ok(ytd_class) ->
              case annual.fact.start, prior_ytd.fact.start {
                None, _ -> Error(MissingDurationStart("annual"))
                _, None -> Error(MissingDurationStart("prior_ytd"))
                Some(annual_start), Some(prior_start)
                  if annual_start != prior_start
                -> Error(PriorYtdFiscalStartMismatch)
                Some(_), Some(_) ->
                  case
                    periods.day_after(annual.fact.end),
                    current_ytd.fact.start
                  {
                    Error(_), _ -> Error(TrailingWindowInvalid)
                    _, None -> Error(MissingDurationStart("current_ytd"))
                    Ok(expected), Some(actual) if expected != actual ->
                      Error(CurrentFiscalStartMismatch)
                    Ok(_), Some(_) -> {
                      use _ <- result.try(validate_growth_gap(
                        prior_ytd,
                        current_ytd,
                        YearOverYear,
                      ))
                      use window_start <- result.try(trailing_window_start(
                        prior_ytd,
                        current_ytd,
                      ))
                      use code <- result.try(valid_currency(annual.unit))
                      let expression =
                        formula.Subtract(
                          formula.Add(
                            formula.Reference("annual"),
                            formula.Reference("current_ytd"),
                          ),
                          formula.Reference("prior_ytd"),
                        )
                      let assumptions = [
                        math_metric.Assumption(
                          "method",
                          "annual plus current YTD minus prior comparable YTD",
                        ),
                        math_metric.Assumption(
                          "ytd_period_class",
                          periods.class_name(ytd_class),
                        ),
                      ]
                      use definition <- result.try(
                        math_metric.define(
                          name: "trailing_twelve_months_bridge",
                          unit: math_metric.Currency(code),
                          formula: expression,
                          assumptions: assumptions,
                        )
                        |> result.map_error(CalculationFailed),
                      )
                      let sources = [
                        NamedSource("annual", annual),
                        NamedSource("current_ytd", current_ytd),
                        NamedSource("prior_ytd", prior_ytd),
                      ]
                      let inputs =
                        sources
                        |> list.map(fn(source) {
                          formula.Input(
                            source.name,
                            formula.Available(source.candidate.value),
                          )
                        })
                      use calculation <- result.try(
                        math_metric.calculate(definition, inputs)
                        |> result.map_error(CalculationFailed),
                      )
                      Ok(TrailingTwelveMonths(
                        annual.metric,
                        calculation,
                        expression,
                        currency.code(code),
                        window_start,
                        current_ytd.fact.end,
                        sources,
                        "annual direct fact plus current YTD direct fact minus prior comparable YTD direct fact; fiscal boundaries, year-over-year gap, metric, taxonomy tag, and unit must match",
                      ))
                    }
                  }
              }
          }
        _ -> Error(ExpectedAnnualSource)
      }
    }
  }
}

pub fn composed_trailing_twelve_months(
  quarters: List(QuarterObservation),
) -> Result(ComposedTrailingTwelveMonths, DeriveError) {
  case quarters {
    [_, _, _, _] -> {
      use normalized <- result.try(list.try_map(quarters, canonical_quarter))
      let sorted = list.sort(normalized, by: compare_quarter_data)
      let assert [first, second, third, fourth] = sorted
      case additive_metric(first.metric) {
        False -> Error(UnsupportedTrailingMetric)
        True -> {
          use _ <- result.try(validate_quarter_compatibility(sorted, first))
          use _ <- result.try(validate_quarter_contiguous(first, second))
          use _ <- result.try(validate_quarter_contiguous(second, third))
          use _ <- result.try(validate_quarter_contiguous(third, fourth))
          use _ <- result.try(validate_composed_window(first, fourth))
          use code <- result.try(valid_currency(first.unit))
          let QuarterFormulaParts(expressions, inputs, evidence) =
            build_quarter_formula_parts(sorted, 1, [], [], [])
          let expression = formula.Sum(expressions)
          let assumptions = [
            math_metric.Assumption(
              "coverage",
              "four contiguous quarter observations; derived quarters expand to annual-minus-YTD leaves",
            ),
          ]
          use definition <- result.try(
            math_metric.define(
              name: "trailing_twelve_months_composed",
              unit: math_metric.Currency(code),
              formula: expression,
              assumptions: assumptions,
            )
            |> result.map_error(CalculationFailed),
          )
          use calculation <- result.try(
            math_metric.calculate(definition, inputs)
            |> result.map_error(CalculationFailed),
          )
          Ok(ComposedTrailingTwelveMonths(
            first.metric,
            calculation,
            expression,
            currency.code(code),
            first.start,
            fourth.end,
            evidence,
            "sum of four contiguous typed quarter observations; every derived Q4 is revalidated and expanded to retained annual and nine-month YTD source leaves",
          ))
        }
      }
    }
    _ -> Error(ExpectedFourQuarters)
  }
}

fn canonical_quarter(
  value: QuarterObservation,
) -> Result(QuarterData, DeriveError) {
  case value {
    DirectQuarter(candidate) ->
      case periods.classify(candidate.fact) {
        Error(error) ->
          Error(InvalidDirectQuarter(candidate.fact.accession, error))
        Ok(classified) ->
          case classified.class, candidate.fact.start {
            periods.Quarter, Some(start) ->
              Ok(QuarterData(
                DirectQuarter(candidate),
                candidate.metric,
                candidate.value,
                candidate.unit,
                candidate.concept,
                start,
                candidate.fact.end,
              ))
            _, _ -> Error(ExpectedDirectQuarter(candidate.fact.accession))
          }
      }
    DerivedQuarter(value) ->
      case derivation.q4(value.annual, value.nine_month_ytd) {
        Error(error) -> Error(InvalidDerivedQuarter(error))
        Ok(canonical) ->
          Ok(QuarterData(
            DerivedQuarter(canonical),
            canonical.metric,
            canonical.value,
            canonical.unit,
            canonical.annual.concept,
            canonical.start,
            canonical.end,
          ))
      }
  }
}

fn validate_quarter_compatibility(
  values: List(QuarterData),
  first: QuarterData,
) -> Result(Nil, DeriveError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case
        value.metric == first.metric,
        value.unit == first.unit,
        same_concept_id(value.concept, first.concept)
      {
        False, _, _ -> Error(QuarterMetricMismatch)
        _, False, _ -> Error(QuarterUnitMismatch)
        _, _, False -> Error(QuarterConceptMismatch)
        True, True, True -> validate_quarter_compatibility(rest, first)
      }
  }
}

fn validate_quarter_contiguous(
  previous: QuarterData,
  current: QuarterData,
) -> Result(Nil, DeriveError) {
  case periods.day_after(previous.end) {
    Ok(expected) if expected == current.start -> Ok(Nil)
    _ -> Error(NonContiguousQuarter(previous.end, current.start))
  }
}

fn validate_composed_window(
  first: QuarterData,
  fourth: QuarterData,
) -> Result(Nil, DeriveError) {
  case periods.classify_range(first.start, fourth.end) {
    Error(_) -> Error(TrailingWindowInvalid)
    Ok(classified) ->
      case classified.class {
        periods.Annual -> Ok(Nil)
        _ -> Error(TrailingWindowMismatch)
      }
  }
}

fn build_quarter_formula_parts(
  values: List(QuarterData),
  index: Int,
  expressions: List(Formula),
  inputs: List(formula.Input),
  evidence: List(QuarterEvidence),
) -> QuarterFormulaParts {
  case values {
    [] ->
      QuarterFormulaParts(
        list.reverse(expressions),
        list.reverse(inputs),
        list.reverse(evidence),
      )
    [value, ..rest] -> {
      let name = "quarter_" <> int.to_string(index)
      case value.observation {
        DirectQuarter(candidate) ->
          build_quarter_formula_parts(
            rest,
            index + 1,
            [formula.Reference(name), ..expressions],
            [formula.Input(name, formula.Available(candidate.value)), ..inputs],
            [QuarterEvidence(name, value.observation), ..evidence],
          )
        DerivedQuarter(derived) -> {
          let annual_name = name <> "_annual"
          let ytd_name = name <> "_nine_month_ytd"
          build_quarter_formula_parts(
            rest,
            index + 1,
            [
              formula.Subtract(
                formula.Reference(annual_name),
                formula.Reference(ytd_name),
              ),
              ..expressions
            ],
            [
              formula.Input(
                ytd_name,
                formula.Available(derived.nine_month_ytd.value),
              ),
              formula.Input(
                annual_name,
                formula.Available(derived.annual.value),
              ),
              ..inputs
            ],
            [QuarterEvidence(name, value.observation), ..evidence],
          )
        }
      }
    }
  }
}

fn compare_quarter_data(left: QuarterData, right: QuarterData) -> order.Order {
  string.compare(left.end, right.end)
}

fn comparable_ytd(
  current: periods.Class,
  prior: periods.Class,
) -> Result(periods.Class, DeriveError) {
  case current, prior {
    periods.Quarter, periods.Quarter -> Ok(periods.Quarter)
    periods.HalfYearToDate, periods.HalfYearToDate -> Ok(periods.HalfYearToDate)
    periods.NineMonthToDate, periods.NineMonthToDate ->
      Ok(periods.NineMonthToDate)
    periods.Quarter, _
    | periods.HalfYearToDate, _
    | periods.NineMonthToDate, _
    -> Error(YtdClassMismatch)
    _, _ -> Error(ExpectedComparableYtd)
  }
}

fn trailing_window_start(
  prior_ytd: Candidate,
  current_ytd: Candidate,
) -> Result(String, DeriveError) {
  case periods.day_after(prior_ytd.fact.end) {
    Error(_) -> Error(TrailingWindowInvalid)
    Ok(start) ->
      case periods.classify_range(start, current_ytd.fact.end) {
        Error(_) -> Error(TrailingWindowInvalid)
        Ok(classified) ->
          case classified.class {
            periods.Annual -> Ok(start)
            _ -> Error(TrailingWindowMismatch)
          }
      }
  }
}

fn build_growth_points(
  points: List(Candidate),
  gap: GrowthGap,
  scale: Int,
  out: List(GrowthPoint),
) -> Result(List(GrowthPoint), DeriveError) {
  case points {
    [] | [_] -> Ok(list.reverse(out))
    [previous, current, ..rest] -> {
      use _ <- result.try(validate_growth_gap(previous, current, gap))
      let expression =
        formulas.percentage(
          formula.Subtract(
            formula.Reference("current"),
            formula.Reference("previous"),
          ),
          formula.Reference("previous"),
          scale,
          decimal.HalfEven,
        )
      let assumptions = [
        math_metric.Assumption("comparison", growth_gap_name(gap)),
        math_metric.Assumption("rounding", "half_even"),
        math_metric.Assumption("scale", int_label(scale)),
      ]
      use definition <- result.try(
        math_metric.define(
          name: "growth",
          unit: math_metric.PercentagePoints,
          formula: expression,
          assumptions: assumptions,
        )
        |> result.map_error(CalculationFailed),
      )
      use calculation <- result.try(
        math_metric.calculate(definition, [
          formula.Input("current", formula.Available(current.value)),
          formula.Input("previous", formula.Available(previous.value)),
        ])
        |> result.map_error(CalculationFailed),
      )
      build_growth_points([current, ..rest], gap, scale, [
        GrowthPoint(
          calculation,
          expression,
          previous,
          current,
          "(current direct fact minus previous direct fact) divided by previous direct fact, multiplied by 100",
        ),
        ..out
      ])
    }
  }
}

fn validate_growth_gap(
  previous: Candidate,
  current: Candidate,
  gap: GrowthGap,
) -> Result(Nil, DeriveError) {
  case periods.day_after(previous.fact.end) {
    Error(_) -> Error(GrowthGapInvalid(previous.fact.end, current.fact.end))
    Ok(start) ->
      case periods.classify_range(start, current.fact.end) {
        Error(_) -> Error(GrowthGapInvalid(previous.fact.end, current.fact.end))
        Ok(classified) -> {
          let expected = case gap {
            QuarterOverQuarter -> periods.Quarter
            YearOverYear -> periods.Annual
          }
          case same_class(expected, classified.class) {
            True -> Ok(Nil)
            False ->
              Error(GrowthGapMismatch(previous.fact.end, current.fact.end))
          }
        }
      }
  }
}

fn validate_contiguous(
  previous: Candidate,
  current: Candidate,
) -> Result(Nil, DeriveError) {
  case periods.day_after(previous.fact.end), current.fact.start {
    Ok(expected), Some(actual) if expected == actual -> Ok(Nil)
    _, Some(actual) -> Error(NonContiguousQuarter(previous.fact.end, actual))
    _, None -> Error(MissingDurationStart("quarter"))
  }
}

fn validate_trailing_window(
  first: Candidate,
  fourth: Candidate,
) -> Result(String, DeriveError) {
  case first.fact.start {
    None -> Error(MissingDurationStart("quarter_1"))
    Some(start) ->
      case periods.classify_range(start, fourth.fact.end) {
        Error(_) -> Error(TrailingWindowInvalid)
        Ok(classified) ->
          case classified.class {
            periods.Annual -> Ok(start)
            _ -> Error(TrailingWindowMismatch)
          }
      }
  }
}

fn definition(
  kind: Kind,
  candidates: List(Candidate),
  scale: Int,
) -> Result(
  #(Formula, math_metric.Unit, String, List(math_metric.Assumption), String),
  DeriveError,
) {
  case kind, candidates {
    FreeCashFlow, [operating, capital_expenditures] -> {
      use code <- result.try(same_currency(operating, capital_expenditures))
      let expression =
        formulas.free_cash_flow(
          formula.Reference("operating_cash_flow"),
          formula.Reference("capital_expenditures_reported"),
        )
      Ok(#(
        expression,
        math_metric.Currency(code),
        currency.code(code),
        [
          math_metric.Assumption(
            "capital_expenditure_sign",
            "reported positive PP&E purchase outflow is subtracted",
          ),
        ],
        "operating cash flow minus reported payments to acquire property, plant, and equipment",
      ))
    }
    NetMargin, [net_income, revenue] -> {
      use _ <- result.try(same_currency(net_income, revenue))
      Ok(#(
        formulas.percentage(
          formula.Reference("net_income"),
          formula.Reference("revenue"),
          scale,
          decimal.HalfEven,
        ),
        math_metric.PercentagePoints,
        "percentage_points",
        [
          math_metric.Assumption("rounding", "half_even"),
          math_metric.Assumption("scale", int_label(scale)),
        ],
        "net income divided by revenue, multiplied by 100",
      ))
    }
    DilutedEarningsPerShare, [net_income, shares] -> {
      use code <- result.try(valid_currency(net_income.unit))
      case shares.unit {
        "shares" ->
          Ok(#(
            formulas.per_share(
              formula.Reference("net_income"),
              formula.Reference("diluted_weighted_average_shares"),
              scale,
              decimal.HalfEven,
            ),
            math_metric.CurrencyPerShare(code),
            currency.code(code) <> "/share",
            [
              math_metric.Assumption(
                "share_basis",
                "reported diluted weighted-average shares",
              ),
              math_metric.Assumption("rounding", "half_even"),
              math_metric.Assumption("scale", int_label(scale)),
            ],
            "net income divided by diluted weighted-average shares",
          ))
        actual -> Error(ExpectedSharesUnit(actual))
      }
    }
    _, _ -> Error(WrongInputCount)
  }
}

fn validate_inputs(
  required: List(#(String, Metric)),
  candidates: List(Candidate),
  expected_class: periods.Class,
  out: List(NamedSource),
) -> Result(List(NamedSource), DeriveError) {
  case required, candidates {
    [], [] -> Ok(list.reverse(out))
    [#(name, expected), ..required], [candidate, ..candidates] ->
      case candidate.metric == expected {
        False -> Error(InputMetricMismatch(name, expected, candidate.metric))
        True ->
          case periods.classify(candidate.fact) {
            Error(error) -> Error(InvalidPeriod(name, error))
            Ok(classified) ->
              case same_class(expected_class, classified.class) {
                False -> Error(PeriodClassMismatch(name))
                True ->
                  case candidate.fact.start {
                    None -> Error(MissingDurationStart(name))
                    Some(_) ->
                      validate_inputs(required, candidates, expected_class, [
                        NamedSource(name, candidate),
                        ..out
                      ])
                  }
              }
          }
      }
    _, _ -> Error(WrongInputCount)
  }
}

fn validate_source_context(
  sources: List(NamedSource),
  first: Candidate,
) -> Result(Nil, DeriveError) {
  case sources {
    [] -> Ok(Nil)
    [NamedSource(name, candidate), ..rest] ->
      case
        candidate.fact.start == first.fact.start
        && candidate.fact.end == first.fact.end,
        candidate.fact.accession == first.fact.accession
        && candidate.fact.form == first.fact.form
        && candidate.fact.filed == first.fact.filed
        && candidate.fact.fiscal_year == first.fact.fiscal_year
        && candidate.fact.fiscal_period == first.fact.fiscal_period
      {
        False, _ -> Error(SourcePeriodMismatch(name))
        _, False -> Error(SourceFilingMismatch(name))
        True, True -> validate_source_context(rest, first)
      }
  }
}

fn same_currency(
  left: Candidate,
  right: Candidate,
) -> Result(currency.Currency, DeriveError) {
  case left.unit == right.unit {
    False -> Error(InputUnitMismatch(left.unit, right.unit))
    True -> valid_currency(left.unit)
  }
}

fn valid_currency(value: String) -> Result(currency.Currency, DeriveError) {
  currency.from_code(value)
  |> result.map_error(fn(_) { InvalidCurrencyUnit(value) })
}

fn additive_metric(value: Metric) -> Bool {
  case value {
    fundamentals.Revenue
    | fundamentals.NetIncome
    | fundamentals.OperatingCashFlow
    | fundamentals.CapitalExpendituresReported -> True
    _ -> False
  }
}

fn same_concept(left: Candidate, right: Candidate) -> Bool {
  same_concept_id(left.concept, right.concept)
}

fn same_concept_id(left: xbrl.ConceptId, right: xbrl.ConceptId) -> Bool {
  xbrl.taxonomy(left) == xbrl.taxonomy(right)
  && xbrl.tag(left) == xbrl.tag(right)
}

fn same_class(left: periods.Class, right: periods.Class) -> Bool {
  case left, right {
    periods.Quarter, periods.Quarter -> True
    periods.HalfYearToDate, periods.HalfYearToDate -> True
    periods.NineMonthToDate, periods.NineMonthToDate -> True
    periods.Annual, periods.Annual -> True
    _, _ -> False
  }
}

fn sources_first_name(sources: List(NamedSource)) -> String {
  case sources {
    [first, ..] -> first.name
    [] -> "input"
  }
}

fn int_label(value: Int) -> String {
  int.to_string(value)
}
