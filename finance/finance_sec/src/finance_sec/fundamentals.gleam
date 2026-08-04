import finance_core/decimal.{type Decimal}
import finance_core/identifier
import finance_core/time
import finance_sec/periods
import finance_sec/xbrl.{type CompanyFacts, type Concept, type Fact}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

pub type Metric {
  Revenue
  NetIncome
  Assets
  CashAndEquivalents
  OperatingCashFlow
  CapitalExpendituresReported
  DilutedWeightedAverageShares
}

pub type PeriodKind {
  Instant
  Duration
}

pub type UnitKind {
  Monetary
  Shares
}

pub type Definition {
  Definition(
    metric: Metric,
    tags: List(String),
    period_kind: PeriodKind,
    unit_kind: UnitKind,
    method: String,
  )
}

pub opaque type Query {
  Query(
    definition: Definition,
    unit: String,
    period: PeriodSelector,
    form: Option(String),
  )
}

type PeriodSelector {
  Exact(start: Option(String), end: String)
  Classified(target: periods.Target)
}

pub opaque type FilingPolicy {
  PreserveAll
  OriginalOnly
  AmendmentsOnly
  LatestFiled
  ExactAccession(value: String)
}

pub type FilingPolicyError {
  UnknownFilingPolicy
  AccessionRequired
  InvalidAccession
}

pub type QueryError {
  InvalidUnit
  InvalidStart
  InvalidEnd
  InvalidForm
  PeriodKindMismatch
}

pub type Candidate {
  Candidate(
    metric: Metric,
    value: Decimal,
    raw_value: String,
    unit: String,
    concept: xbrl.ConceptId,
    fact: Fact,
  )
}

pub type ResolveError {
  NonNumericFact(concept: xbrl.ConceptId, accession: String)
  InvalidDecimal(concept: xbrl.ConceptId, accession: String, raw: String)
  InvalidFactPeriod(
    concept: xbrl.ConceptId,
    accession: String,
    error: periods.PeriodError,
  )
  InvalidFiledDate(accession: String, filed: String)
}

pub fn metric(name: String) -> Result(Metric, Nil) {
  case string.lowercase(name) {
    "revenue" -> Ok(Revenue)
    "net_income" -> Ok(NetIncome)
    "assets" -> Ok(Assets)
    "cash_and_equivalents" -> Ok(CashAndEquivalents)
    "operating_cash_flow" -> Ok(OperatingCashFlow)
    "capital_expenditures_reported" -> Ok(CapitalExpendituresReported)
    "diluted_weighted_average_shares" -> Ok(DilutedWeightedAverageShares)
    _ -> Error(Nil)
  }
}

pub fn metric_name(value: Metric) -> String {
  case value {
    Revenue -> "revenue"
    NetIncome -> "net_income"
    Assets -> "assets"
    CashAndEquivalents -> "cash_and_equivalents"
    OperatingCashFlow -> "operating_cash_flow"
    CapitalExpendituresReported -> "capital_expenditures_reported"
    DilutedWeightedAverageShares -> "diluted_weighted_average_shares"
  }
}

pub fn definition(metric: Metric) -> Definition {
  case metric {
    Revenue ->
      Definition(
        metric,
        [
          "RevenueFromContractWithCustomerExcludingAssessedTax",
          "RevenueFromContractWithCustomerIncludingAssessedTax",
          "Revenues",
          "SalesRevenueNet",
        ],
        Duration,
        Monetary,
        "direct reported consolidated duration fact; accepted revenue tags are alternatives and never silently preferred",
      )
    NetIncome ->
      Definition(
        metric,
        ["NetIncomeLoss", "ProfitLoss"],
        Duration,
        Monetary,
        "direct reported consolidated duration fact attributable according to the selected SEC tag",
      )
    Assets ->
      Definition(
        metric,
        ["Assets"],
        Instant,
        Monetary,
        "direct reported consolidated instant fact",
      )
    CashAndEquivalents ->
      Definition(
        metric,
        ["CashAndCashEquivalentsAtCarryingValue"],
        Instant,
        Monetary,
        "cash and cash equivalents at carrying value; restricted cash is not added",
      )
    OperatingCashFlow ->
      Definition(
        metric,
        ["NetCashProvidedByUsedInOperatingActivities"],
        Duration,
        Monetary,
        "direct reported operating cash flow; reported sign is preserved",
      )
    CapitalExpendituresReported ->
      Definition(
        metric,
        ["PaymentsToAcquirePropertyPlantAndEquipment"],
        Duration,
        Monetary,
        "direct reported PP&E purchase outflow; no sign inversion and no broader capex reconstruction",
      )
    DilutedWeightedAverageShares ->
      Definition(
        metric,
        ["WeightedAverageNumberOfDilutedSharesOutstanding"],
        Duration,
        Shares,
        "direct reported diluted weighted-average shares for the exact duration",
      )
  }
}

pub fn query(
  metric: Metric,
  unit: String,
  start: Option(String),
  end: String,
  form: Option(String),
) -> Result(Query, QueryError) {
  let definition = definition(metric)
  case
    valid_unit(unit),
    valid_optional_date(start),
    valid_date(end),
    normalize_form(form),
    period_matches(definition.period_kind, start)
  {
    False, _, _, _, _ -> Error(InvalidUnit)
    _, False, _, _, _ -> Error(InvalidStart)
    _, _, False, _, _ -> Error(InvalidEnd)
    _, _, _, Error(_), _ -> Error(InvalidForm)
    _, _, _, _, False -> Error(PeriodKindMismatch)
    True, True, True, Ok(form), True ->
      Ok(Query(definition, unit, Exact(start, end), form))
  }
}

pub fn period_query(
  metric: Metric,
  unit: String,
  target: periods.Target,
  form: Option(String),
) -> Result(Query, QueryError) {
  let definition = definition(metric)
  case
    valid_unit(unit),
    normalize_form(form),
    target_matches(definition.period_kind, periods.target_class(target))
  {
    False, _, _ -> Error(InvalidUnit)
    _, Error(_), _ -> Error(InvalidForm)
    _, _, False -> Error(PeriodKindMismatch)
    True, Ok(form), True ->
      Ok(Query(definition, unit, Classified(target), form))
  }
}

pub fn filing_policy(
  name: String,
  accession: Option(String),
) -> Result(FilingPolicy, FilingPolicyError) {
  case string.lowercase(name), accession {
    "preserve_all", _ -> Ok(PreserveAll)
    "original_only", _ -> Ok(OriginalOnly)
    "amendments_only", _ -> Ok(AmendmentsOnly)
    "latest_filed", _ -> Ok(LatestFiled)
    "exact_accession", None -> Error(AccessionRequired)
    "exact_accession", Some(value) ->
      case valid_accession(value) {
        True -> Ok(ExactAccession(value))
        False -> Error(InvalidAccession)
      }
    _, _ -> Error(UnknownFilingPolicy)
  }
}

pub fn filing_policy_name(value: FilingPolicy) -> String {
  case value {
    PreserveAll -> "preserve_all"
    OriginalOnly -> "original_only"
    AmendmentsOnly -> "amendments_only"
    LatestFiled -> "latest_filed"
    ExactAccession(_) -> "exact_accession"
  }
}

pub fn resolve(
  company: CompanyFacts,
  query: Query,
) -> Result(identifier.Resolution(Candidate), ResolveError) {
  let assert Ok(policy) = filing_policy("preserve_all", None)
  resolve_with_policy(company, query, policy)
}

pub fn resolve_with_policy(
  company: CompanyFacts,
  query: Query,
  policy: FilingPolicy,
) -> Result(identifier.Resolution(Candidate), ResolveError) {
  let Query(definition, unit, period, form) = query
  let concepts =
    company.concepts
    |> list.filter(fn(concept) {
      xbrl.taxonomy(concept.id) == "us-gaap"
      && list.contains(definition.tags, xbrl.tag(concept.id))
    })
  use candidates <- result.try(
    collect_candidates(concepts, definition.metric, unit, period, form, []),
  )
  use _ <- result.try(validate_filed_dates(candidates))
  Ok(
    candidates
    |> list.sort(by: compare_candidate)
    |> apply_filing_policy(policy)
    |> identifier.resolve,
  )
}

pub fn query_definition(query: Query) -> Definition {
  let Query(definition, ..) = query
  definition
}

pub fn query_period_class(query: Query) -> Option(periods.Class) {
  let Query(_, _, period, _) = query
  case period {
    Exact(None, _) -> Some(periods.Instant)
    Exact(Some(_), _) -> None
    Classified(target) -> Some(periods.target_class(target))
  }
}

fn collect_candidates(
  concepts: List(Concept),
  metric: Metric,
  unit: String,
  period: PeriodSelector,
  form: Option(String),
  out: List(Candidate),
) -> Result(List(Candidate), ResolveError) {
  case concepts {
    [] -> Ok(out)
    [concept, ..rest] ->
      case matching_facts(concept, unit, period, form) {
        Error(error) -> Error(error)
        Ok([]) -> collect_candidates(rest, metric, unit, period, form, out)
        Ok(facts) -> {
          use candidates <- result.try(
            parse_candidates(metric, concept, unit, facts, []),
          )
          collect_candidates(
            rest,
            metric,
            unit,
            period,
            form,
            list.append(candidates, out),
          )
        }
      }
  }
}

fn matching_facts(
  concept: Concept,
  unit: String,
  period: PeriodSelector,
  form: Option(String),
) -> Result(List(Fact), ResolveError) {
  let facts =
    concept.units
    |> list.filter(fn(unit_facts) { unit_facts.unit == unit })
    |> list.flat_map(fn(unit_facts) { unit_facts.facts })
    |> list.filter(fn(fact) {
      case form {
        None -> True
        Some(expected) -> string.uppercase(fact.form) == expected
      }
    })
  match_periods(facts, concept.id, period, [])
}

fn match_periods(
  facts: List(Fact),
  concept: xbrl.ConceptId,
  period: PeriodSelector,
  out: List(Fact),
) -> Result(List(Fact), ResolveError) {
  case facts {
    [] -> Ok(list.reverse(out))
    [fact, ..rest] ->
      case period {
        Exact(start, end) ->
          match_periods(
            rest,
            concept,
            period,
            case fact.start == start && fact.end == end {
              True -> [fact, ..out]
              False -> out
            },
          )
        Classified(target) ->
          case periods.matches(target, fact) {
            Error(error) ->
              Error(InvalidFactPeriod(concept, fact.accession, error))
            Ok(True) -> match_periods(rest, concept, period, [fact, ..out])
            Ok(False) -> match_periods(rest, concept, period, out)
          }
      }
  }
}

fn parse_candidates(
  metric: Metric,
  concept: Concept,
  unit: String,
  facts: List(Fact),
  out: List(Candidate),
) -> Result(List(Candidate), ResolveError) {
  case facts {
    [] -> Ok(out)
    [fact, ..rest] ->
      case fact.value {
        xbrl.Text(_) | xbrl.Boolean(_) ->
          Error(NonNumericFact(concept.id, fact.accession))
        xbrl.Numeric(raw) ->
          case decimal.parse(raw) {
            Error(_) -> Error(InvalidDecimal(concept.id, fact.accession, raw))
            Ok(value) ->
              parse_candidates(metric, concept, unit, rest, [
                Candidate(metric, value, raw, unit, concept.id, fact),
                ..out
              ])
          }
      }
  }
}

fn compare_candidate(left: Candidate, right: Candidate) -> order.Order {
  case string.compare(right.fact.filed, left.fact.filed) {
    order.Eq ->
      case string.compare(right.fact.accession, left.fact.accession) {
        order.Eq ->
          string.compare(xbrl.tag(left.concept), xbrl.tag(right.concept))
        other -> other
      }
    other -> other
  }
}

fn apply_filing_policy(
  candidates: List(Candidate),
  policy: FilingPolicy,
) -> List(Candidate) {
  case policy {
    PreserveAll -> candidates
    OriginalOnly ->
      list.filter(candidates, fn(candidate) {
        !string.ends_with(candidate.fact.form, "/A")
      })
    AmendmentsOnly ->
      list.filter(candidates, fn(candidate) {
        string.ends_with(candidate.fact.form, "/A")
      })
    ExactAccession(accession) ->
      list.filter(candidates, fn(candidate) {
        candidate.fact.accession == accession
      })
    LatestFiled ->
      case candidates {
        [] -> []
        [latest, ..] ->
          list.filter(candidates, fn(candidate) {
            candidate.fact.filed == latest.fact.filed
          })
      }
  }
}

fn validate_filed_dates(
  candidates: List(Candidate),
) -> Result(Nil, ResolveError) {
  case candidates {
    [] -> Ok(Nil)
    [candidate, ..rest] ->
      case valid_date(candidate.fact.filed) {
        True -> validate_filed_dates(rest)
        False ->
          Error(InvalidFiledDate(candidate.fact.accession, candidate.fact.filed))
      }
  }
}

fn period_matches(kind: PeriodKind, start: Option(String)) -> Bool {
  case kind, start {
    Instant, None -> True
    Duration, Some(_) -> True
    _, _ -> False
  }
}

fn target_matches(kind: PeriodKind, class: periods.Class) -> Bool {
  case kind, class {
    Instant, periods.Instant -> True
    Duration, periods.Quarter
    | Duration, periods.HalfYearToDate
    | Duration, periods.NineMonthToDate
    | Duration, periods.Annual
    -> True
    _, _ -> False
  }
}

fn normalize_form(value: Option(String)) -> Result(Option(String), Nil) {
  case value {
    None -> Ok(None)
    Some(value) -> {
      let normalized = value |> string.trim |> string.uppercase
      case normalized == "" || string.length(normalized) > 20 {
        True -> Error(Nil)
        False -> Ok(Some(normalized))
      }
    }
  }
}

fn valid_unit(value: String) -> Bool {
  value != "" && string.trim(value) == value && string.length(value) <= 100
}

fn valid_accession(value: String) -> Bool {
  value != "" && string.trim(value) == value && string.length(value) <= 100
}

fn valid_optional_date(value: Option(String)) -> Bool {
  case value {
    None -> True
    Some(value) -> valid_date(value)
  }
}

fn valid_date(value: String) -> Bool {
  case string.split(value, "-") {
    [year, month, day] ->
      case int.parse(year), int.parse(month), int.parse(day) {
        Ok(year), Ok(month), Ok(day) ->
          string.length(year |> int.to_string) == 4
          && time.date(year, month, day) |> result.is_ok
        _, _, _ -> False
      }
    _ -> False
  }
}
