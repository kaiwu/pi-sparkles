import finance_core/decimal
import finance_core/identifier
import finance_core/time
import finance_http/request as http_request
import finance_http/response as http_response
import finance_http/transport
import finance_sec
import finance_sec/derivation
import finance_sec/fundamentals
import finance_sec/periods
import finance_sec/request
import finance_sec/response
import finance_sec/runtime
import finance_sec/xbrl
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn access_and_cik_are_validated_test() {
  finance_sec.access("", "research@example.com")
  |> should.equal(Error(finance_sec.InvalidProduct))
  let assert Ok(cik) = finance_sec.cik("320193")
  finance_sec.cik_value(cik) |> should.equal("0000320193")
  finance_sec.cik("not-a-cik") |> should.equal(Error(finance_sec.InvalidCik))
}

pub fn requests_require_identity_and_are_bounded_test() {
  let assert Ok(access) =
    finance_sec.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(cik) = finance_sec.cik("320193")
  let assert Ok(value) = request.submissions(access, cik)
  http_request.path(value) |> should.equal("/submissions/CIK0000320193.json")
  http_request.timeout(value)
  |> time.duration_milliseconds
  |> should.equal(15_000)
  http_request.headers(value)
  |> should.equal([
    http_request.Header(
      "user-agent",
      "pi-sparkles/0.1 research@example.com",
      http_request.Public,
    ),
  ])
}

pub fn ticker_and_submission_fixtures_decode_test() {
  let tickers =
    "{\"0\":{\"cik_str\":320193,\"ticker\":\"AAPL\",\"title\":\"Apple Inc.\"}}"
  let assert Ok(companies) = response.decode_companies(tickers)
  let assert Ok(company) = list.first(companies)
  company.ticker |> should.equal("AAPL")
  finance_sec.cik_value(company.cik) |> should.equal("0000320193")
  let submissions =
    "{\"cik\":\"0000320193\",\"name\":\"Apple Inc.\",\"tickers\":[\"AAPL\"],\"exchanges\":[\"Nasdaq\"],\"filings\":{\"recent\":{\"accessionNumber\":[\"0000320193-25-000079\"],\"filingDate\":[\"2025-08-01\"],\"reportDate\":[\"2025-06-28\"],\"form\":[\"10-Q\"],\"primaryDocument\":[\"aapl-20250628.htm\"],\"core_type\":[\"10-Q\"],\"isXBRLNumeric\":[1]}}}"
  let assert Ok(value) = response.decode_submissions(submissions)
  value.name |> should.equal("Apple Inc.")
  finance_sec.cik_value(value.cik) |> should.equal("0000320193")
  value.recent |> list.length |> should.equal(1)
}

pub fn xbrl_company_facts_preserve_exact_values_and_duplicates_test() {
  let fixture =
    "{\"cik\":320193,\"entityName\":\"Apple Inc.\",\"facts\":{\"us-gaap\":{\"Revenue\":{\"label\":\"Revenue\",\"description\":\"Reported revenue\",\"units\":{\"USD\":[{\"start\":\"2024-01-01\",\"end\":\"2024-12-31\",\"val\":9007199254740993.100,\"accn\":\"a\",\"fy\":2024,\"fp\":\"FY\",\"form\":\"10-K\",\"filed\":\"2025-02-01\",\"frame\":\"CY2024\"},{\"start\":\"2024-01-01\",\"end\":\"2024-12-31\",\"val\":9007199254740993.100,\"accn\":\"b\",\"fy\":2024,\"fp\":\"FY\",\"form\":\"10-K/A\",\"filed\":\"2025-02-02\"}]}}}}}"
  let assert Ok(value) = xbrl.decode_company_facts(fixture)
  finance_sec.cik_value(value.cik) |> should.equal("0000320193")
  let assert [concept] = value.concepts
  xbrl.taxonomy(concept.id) |> should.equal("us-gaap")
  xbrl.tag(concept.id) |> should.equal("Revenue")
  let assert [unit] = concept.units
  unit.unit |> should.equal("USD")
  unit.facts |> list.length |> should.equal(2)
  let assert [first, _] = unit.facts
  first.value |> should.equal(xbrl.Numeric("9007199254740993.100"))
  first.fiscal_year |> should.equal(Some("2024"))
}

pub fn company_facts_preserve_concepts_with_provider_null_labels_test() {
  let fixture =
    "{\"cik\":320193,\"entityName\":\"Apple Inc.\",\"facts\":{\"us-gaap\":{\"EffectiveIncomeTaxRateReconciliationFdiiAmount\":{\"label\":null,\"description\":null,\"units\":{\"USD\":[]}}}}}"
  let assert Ok(value) = xbrl.decode_company_facts(fixture)
  let assert [concept] = value.concepts
  concept.label |> should.equal("")
  concept.description |> should.equal("")
}

pub fn company_concept_request_and_fixture_are_typed_test() {
  let assert Ok(access) =
    finance_sec.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(cik) = finance_sec.cik("320193")
  let assert Ok(id) = xbrl.concept_id("us-gaap", "Assets")
  let assert Ok(value) = request.company_concept(access, cik, id)
  http_request.path(value)
  |> should.equal("/api/xbrl/companyconcept/CIK0000320193/us-gaap/Assets.json")
  let fixture =
    "{\"cik\":320193,\"taxonomy\":\"us-gaap\",\"tag\":\"Assets\",\"label\":\"Assets\",\"description\":\"Total assets\",\"entityName\":\"Apple Inc.\",\"units\":{\"USD\":[{\"end\":\"2025-06-28\",\"val\":100.00,\"accn\":\"a\",\"fy\":2025,\"fp\":\"Q3\",\"form\":\"10-Q\",\"filed\":\"2025-08-01\",\"frame\":\"CY2025Q2I\"}]}}"
  let assert Ok(decoded) = xbrl.decode_company_concept(fixture)
  decoded.concept.label |> should.equal("Assets")
}

pub fn fundamentals_resolve_exact_periods_without_hidden_precedence_test() {
  let fixture =
    "{\"cik\":320193,\"entityName\":\"Apple Inc.\",\"facts\":{\"us-gaap\":{\"RevenueFromContractWithCustomerExcludingAssessedTax\":{\"label\":\"Revenue\",\"units\":{\"USD\":[{\"start\":\"2024-01-01\",\"end\":\"2024-12-31\",\"val\":100.00,\"accn\":\"original\",\"fy\":2024,\"fp\":\"FY\",\"form\":\"10-K\",\"filed\":\"2025-02-01\"},{\"start\":\"2024-01-01\",\"end\":\"2024-12-31\",\"val\":101.00,\"accn\":\"amended\",\"fy\":2024,\"fp\":\"FY\",\"form\":\"10-K/A\",\"filed\":\"2025-02-02\"}]}}}}}"
  let assert Ok(company) = xbrl.decode_company_facts(fixture)
  let assert Ok(query) =
    fundamentals.query(
      fundamentals.Revenue,
      "USD",
      Some("2024-01-01"),
      "2024-12-31",
      None,
    )
  let assert Ok(identifier.Ambiguous(first, second, [])) =
    fundamentals.resolve(company, query)
  first.fact.accession |> should.equal("amended")
  first.raw_value |> should.equal("101.00")
  second.fact.accession |> should.equal("original")
}

pub fn fundamentals_period_kind_and_exact_form_are_explicit_test() {
  fundamentals.query(
    fundamentals.Assets,
    "USD",
    Some("2024-01-01"),
    "2024-12-31",
    None,
  )
  |> should.equal(Error(fundamentals.PeriodKindMismatch))
  let fixture =
    "{\"cik\":320193,\"entityName\":\"Apple Inc.\",\"facts\":{\"us-gaap\":{\"Assets\":{\"label\":\"Assets\",\"units\":{\"USD\":[{\"end\":\"2024-12-31\",\"val\":9007199254740993.100,\"accn\":\"a\",\"fy\":2024,\"fp\":\"FY\",\"form\":\"10-K\",\"filed\":\"2025-02-01\"}]}}}}}"
  let assert Ok(company) = xbrl.decode_company_facts(fixture)
  let assert Ok(query) =
    fundamentals.query(
      fundamentals.Assets,
      "USD",
      None,
      "2024-12-31",
      Some("10-k"),
    )
  let assert Ok(identifier.Unique(candidate)) =
    fundamentals.resolve(company, query)
  candidate.raw_value |> should.equal("9007199254740993.100")
  decimal.to_string(candidate.value) |> should.equal("9007199254740993.1")
}

pub fn statement_periods_classify_calendar_shapes_without_using_fiscal_labels_test() {
  let quarter =
    xbrl.Fact(
      Some("2025-01-01"),
      "2025-03-31",
      xbrl.Numeric("1"),
      "q",
      Some("2025"),
      Some("Q1"),
      "10-Q",
      "2025-05-01",
      None,
    )
  let annual =
    xbrl.Fact(
      Some("2024-01-01"),
      "2024-12-31",
      xbrl.Numeric("1"),
      "y",
      Some("2024"),
      Some("FY"),
      "10-K",
      "2025-02-01",
      None,
    )
  let assert Ok(quarter_period) = periods.classify(quarter)
  quarter_period.class |> should.equal(periods.Quarter)
  quarter_period.days |> should.equal(Some(90))
  let assert Ok(annual_period) = periods.classify(annual)
  annual_period.class |> should.equal(periods.Annual)
  annual_period.days |> should.equal(Some(366))
}

pub fn classified_period_and_filing_precedence_are_explicit_test() {
  let fixture =
    "{\"cik\":320193,\"entityName\":\"Apple Inc.\",\"facts\":{\"us-gaap\":{\"RevenueFromContractWithCustomerExcludingAssessedTax\":{\"label\":\"Revenue\",\"units\":{\"USD\":[{\"start\":\"2025-01-01\",\"end\":\"2025-03-31\",\"val\":25,\"accn\":\"quarter-original\",\"form\":\"10-Q\",\"filed\":\"2025-05-01\"},{\"start\":\"2025-01-01\",\"end\":\"2025-03-31\",\"val\":26,\"accn\":\"quarter-amended\",\"form\":\"10-Q/A\",\"filed\":\"2025-05-02\"},{\"start\":\"2024-10-01\",\"end\":\"2025-03-31\",\"val\":50,\"accn\":\"half-ytd\",\"form\":\"10-Q\",\"filed\":\"2025-05-01\"}]}}}}}"
  let assert Ok(company) = xbrl.decode_company_facts(fixture)
  let assert Ok(target) = periods.target(periods.Quarter, "2025-03-31")
  let assert Ok(query) =
    fundamentals.period_query(fundamentals.Revenue, "USD", target, None)
  let assert Ok(preserve) = fundamentals.filing_policy("preserve_all", None)
  let assert Ok(identifier.Ambiguous(_, _, [])) =
    fundamentals.resolve_with_policy(company, query, preserve)
  let assert Ok(latest) = fundamentals.filing_policy("latest_filed", None)
  let assert Ok(identifier.Unique(amended)) =
    fundamentals.resolve_with_policy(company, query, latest)
  amended.fact.accession |> should.equal("quarter-amended")
  let assert Ok(originals) = fundamentals.filing_policy("original_only", None)
  let assert Ok(identifier.Unique(original)) =
    fundamentals.resolve_with_policy(company, query, originals)
  original.fact.accession |> should.equal("quarter-original")
  let assert Ok(exact) =
    fundamentals.filing_policy("exact_accession", Some("quarter-original"))
  let assert Ok(identifier.Unique(selected)) =
    fundamentals.resolve_with_policy(company, query, exact)
  selected.raw_value |> should.equal("25")
}

pub fn q4_derivation_requires_compatible_additive_source_facts_test() {
  let annual =
    fundamental_candidate("120.00", "2024-01-01", "2024-12-31", "annual")
  let nine_months =
    fundamental_candidate("90.00", "2024-01-01", "2024-09-30", "nine-month")
  let assert Ok(derived) = derivation.q4(annual, nine_months)
  decimal.to_string(derived.value) |> should.equal("30")
  derived.start |> should.equal("2024-10-01")
  derived.end |> should.equal("2024-12-31")
  derived.annual.fact.accession |> should.equal("annual")
  derived.nine_month_ytd.fact.accession |> should.equal("nine-month")

  let incompatible =
    fundamentals.Candidate(
      fundamentals.DilutedWeightedAverageShares,
      decimal_value("100"),
      "100",
      "shares",
      concept_id("WeightedAverageNumberOfDilutedSharesOutstanding"),
      annual.fact,
    )
  derivation.q4(incompatible, incompatible)
  |> should.equal(Error(derivation.UnsupportedMetric))

  let short_residual_annual =
    fundamental_candidate("120", "2024-01-01", "2024-12-01", "short-annual")
  let long_nine_months =
    fundamental_candidate("90", "2024-01-01", "2024-10-29", "long-ytd")
  derivation.q4(short_residual_annual, long_nine_months)
  |> should.equal(Error(derivation.ExpectedQuarter))
}

pub fn comparable_trend_requires_same_concept_unit_class_and_unique_ends_test() {
  let later = fundamental_candidate("30", "2025-01-01", "2025-03-31", "later")
  let earlier =
    fundamental_candidate("25", "2024-01-01", "2024-03-31", "earlier")
  let assert Ok(trend) = derivation.trend([later, earlier], periods.Quarter)
  let assert [first, second] = trend.points
  first.fact.accession |> should.equal("earlier")
  second.fact.accession |> should.equal("later")
  derivation.trend([earlier, earlier], periods.Quarter)
  |> should.equal(Error(derivation.DuplicatePeriodEnd("2024-03-31")))
}

pub fn runtime_constructs_without_network_test() {
  let assert Ok(access) =
    finance_sec.access("pi-sparkles/0.1", "research@example.com")
  runtime.new(access) |> should.be_ok
}

pub fn runtime_conservatively_paces_with_injected_effects_test() {
  let assert Ok(access) =
    finance_sec.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(request_value) = request.company_tickers(access)
  let assert Ok(now) = time.instant(1000)
  let assert Ok(provider_runtime) =
    runtime.new_with(
      access,
      fn(_, _) { promise.resolve(Ok(http_ok())) },
      fn(duration, _) {
        time.duration_milliseconds(duration) |> should.equal(1000)
        promise.resolve(False)
      },
      fn() { now },
    )

  use one <- promise.await(send(provider_runtime, "sec-1", request_value))
  use two <- promise.await(send(provider_runtime, "sec-2", request_value))
  use three <- promise.await(send(provider_runtime, "sec-3", request_value))
  use four <- promise.await(send(provider_runtime, "sec-4", request_value))
  use five <- promise.await(send(provider_runtime, "sec-5", request_value))
  use six <- promise.await(send(provider_runtime, "sec-6", request_value))
  use seven <- promise.await(send(provider_runtime, "sec-7", request_value))
  use eight <- promise.await(send(provider_runtime, "sec-8", request_value))
  use ninth <- promise.await(send(provider_runtime, "sec-9", request_value))
  [one, two, three, four, five, six, seven, eight]
  |> list.all(result.is_ok)
  |> should.be_true
  ninth |> should.be_error
  promise.resolve(Nil)
}

fn send(
  runtime_value: runtime.Runtime,
  id: String,
  request_value: http_request.Request,
) {
  runtime.send(
    runtime_value,
    id: id,
    request: request_value,
    cancellation: transport.new_cancellation(),
  )
}

fn http_ok() -> http_response.Response {
  let assert Ok(value) =
    http_response.new(
      status: 200,
      headers: [],
      body: "{}",
      byte_length: 2,
      elapsed: duration(1),
    )
  value
}

fn duration(milliseconds: Int) -> time.Duration {
  let assert Ok(value) = time.duration(milliseconds)
  value
}

fn fundamental_candidate(
  raw: String,
  start: String,
  end: String,
  accession: String,
) -> fundamentals.Candidate {
  fundamentals.Candidate(
    fundamentals.Revenue,
    decimal_value(raw),
    raw,
    "USD",
    concept_id("RevenueFromContractWithCustomerExcludingAssessedTax"),
    xbrl.Fact(
      Some(start),
      end,
      xbrl.Numeric(raw),
      accession,
      None,
      None,
      "10-Q",
      end,
      None,
    ),
  )
}

fn concept_id(tag: String) -> xbrl.ConceptId {
  let assert Ok(value) = xbrl.concept_id("us-gaap", tag)
  value
}

fn decimal_value(raw: String) -> decimal.Decimal {
  let assert Ok(value) = decimal.parse(raw)
  value
}
