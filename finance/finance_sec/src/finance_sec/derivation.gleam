import finance_core/decimal.{type Decimal}
import finance_sec/fundamentals.{type Candidate, type Metric}
import finance_sec/periods
import finance_sec/xbrl
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string

pub type DerivedQ4 {
  DerivedQ4(
    metric: Metric,
    value: Decimal,
    unit: String,
    start: String,
    end: String,
    annual: Candidate,
    nine_month_ytd: Candidate,
    method: String,
  )
}

pub type Q4Error {
  MetricMismatch
  UnsupportedMetric
  UnitMismatch
  ConceptMismatch
  AnnualPeriodInvalid(periods.PeriodError)
  NineMonthPeriodInvalid(periods.PeriodError)
  ExpectedAnnual
  ExpectedNineMonthToDate
  MissingStart
  StartMismatch
  InvalidQuarterBoundary(periods.PeriodError)
  ExpectedQuarter
}

pub type Trend {
  Trend(
    metric: Metric,
    unit: String,
    concept: xbrl.ConceptId,
    period_class: periods.Class,
    points: List(Candidate),
  )
}

pub type TrendError {
  TooFewPoints
  TrendMetricMismatch
  TrendUnitMismatch
  TrendConceptMismatch
  TrendPeriodInvalid(accession: String, error: periods.PeriodError)
  TrendPeriodMismatch(accession: String)
  DuplicatePeriodEnd(end: String)
}

pub fn q4(
  annual: Candidate,
  nine_month_ytd: Candidate,
) -> Result(DerivedQ4, Q4Error) {
  case
    annual.metric == nine_month_ytd.metric,
    additive_metric(annual.metric),
    annual.unit == nine_month_ytd.unit,
    same_concept(annual, nine_month_ytd)
  {
    False, _, _, _ -> Error(MetricMismatch)
    _, False, _, _ -> Error(UnsupportedMetric)
    _, _, False, _ -> Error(UnitMismatch)
    _, _, _, False -> Error(ConceptMismatch)
    True, True, True, True -> {
      use annual_period <- result.try(
        periods.classify(annual.fact) |> result.map_error(AnnualPeriodInvalid),
      )
      use ytd_period <- result.try(
        periods.classify(nine_month_ytd.fact)
        |> result.map_error(NineMonthPeriodInvalid),
      )
      case annual_period.class, ytd_period.class {
        periods.Annual, periods.NineMonthToDate ->
          case annual.fact.start, nine_month_ytd.fact.start {
            None, _ | _, None -> Error(MissingStart)
            Some(annual_start), Some(ytd_start) if annual_start != ytd_start ->
              Error(StartMismatch)
            Some(_), Some(_) -> {
              use quarter_start <- result.try(
                periods.day_after(nine_month_ytd.fact.end)
                |> result.map_error(InvalidQuarterBoundary),
              )
              use quarter_period <- result.try(
                periods.classify_range(quarter_start, annual.fact.end)
                |> result.map_error(InvalidQuarterBoundary),
              )
              case quarter_period.class {
                periods.Quarter ->
                  Ok(DerivedQ4(
                    annual.metric,
                    decimal.subtract(annual.value, nine_month_ytd.value),
                    annual.unit,
                    quarter_start,
                    annual.fact.end,
                    annual,
                    nine_month_ytd,
                    "annual direct fact minus nine-month year-to-date direct fact; identical metric, taxonomy tag, unit, fiscal start, and quarter-shaped residual required",
                  ))
                _ -> Error(ExpectedQuarter)
              }
            }
          }
        periods.Annual, _ -> Error(ExpectedNineMonthToDate)
        _, _ -> Error(ExpectedAnnual)
      }
    }
  }
}

pub fn trend(
  candidates: List(Candidate),
  expected_class: periods.Class,
) -> Result(Trend, TrendError) {
  case candidates {
    [] | [_] -> Error(TooFewPoints)
    [first, ..] -> {
      use _ <- result.try(validate_trend(candidates, first, expected_class))
      let points = list.sort(candidates, by: compare_period_end)
      use _ <- result.try(reject_duplicate_ends(points))
      Ok(Trend(first.metric, first.unit, first.concept, expected_class, points))
    }
  }
}

fn validate_trend(
  candidates: List(Candidate),
  first: Candidate,
  expected_class: periods.Class,
) -> Result(Nil, TrendError) {
  case candidates {
    [] -> Ok(Nil)
    [candidate, ..rest] ->
      case
        candidate.metric == first.metric,
        candidate.unit == first.unit,
        same_concept(candidate, first)
      {
        False, _, _ -> Error(TrendMetricMismatch)
        _, False, _ -> Error(TrendUnitMismatch)
        _, _, False -> Error(TrendConceptMismatch)
        True, True, True ->
          case periods.classify(candidate.fact) {
            Error(error) ->
              Error(TrendPeriodInvalid(candidate.fact.accession, error))
            Ok(classified) ->
              case same_period_class(expected_class, classified.class) {
                False -> Error(TrendPeriodMismatch(candidate.fact.accession))
                True -> validate_trend(rest, first, expected_class)
              }
          }
      }
  }
}

fn reject_duplicate_ends(
  candidates: List(Candidate),
) -> Result(Nil, TrendError) {
  case candidates {
    [] | [_] -> Ok(Nil)
    [first, second, ..rest] ->
      case first.fact.end == second.fact.end {
        True -> Error(DuplicatePeriodEnd(first.fact.end))
        False -> reject_duplicate_ends([second, ..rest])
      }
  }
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
  xbrl.taxonomy(left.concept) == xbrl.taxonomy(right.concept)
  && xbrl.tag(left.concept) == xbrl.tag(right.concept)
}

fn compare_period_end(left: Candidate, right: Candidate) -> order.Order {
  string.compare(left.fact.end, right.fact.end)
}

fn same_period_class(left: periods.Class, right: periods.Class) -> Bool {
  case left, right {
    periods.Instant, periods.Instant -> True
    periods.Quarter, periods.Quarter -> True
    periods.HalfYearToDate, periods.HalfYearToDate -> True
    periods.NineMonthToDate, periods.NineMonthToDate -> True
    periods.Annual, periods.Annual -> True
    periods.OtherDuration(left), periods.OtherDuration(right) -> left == right
    _, _ -> False
  }
}
