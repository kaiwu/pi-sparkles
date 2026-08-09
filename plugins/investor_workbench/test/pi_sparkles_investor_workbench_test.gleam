import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_investor_workbench/decode
import pi_sparkles_investor_workbench/dossier
import pi_sparkles_investor_workbench/metric
import pi_sparkles_investor_workbench/valuation

const reviewed_at = 1_770_000_000_000

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn coherent_us_dossier_preserves_amendment_and_returns_no_verdict_test() {
  let input = us_dossier()
  let assert Ok(output) = dossier.inspect(input)
  let text = json.to_string(output.details)
  text |> string.contains("\"operation\":\"inspect_dossier\"") |> should.be_true
  text |> string.contains("\"track\":\"us\"") |> should.be_true
  text |> string.contains("\"statementCount\":3") |> should.be_true
  text |> string.contains("\"amendmentCount\":1") |> should.be_true
  text
  |> string.contains(
    "\"mechanicalEvidenceState\":\"no_session_19_insufficiency_condition_detected\"",
  )
  |> should.be_true
  text |> string.contains("\"reviewabilityVerdict\":null") |> should.be_true
  text |> string.contains("\"investmentVerdict\":null") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
}

pub fn incomplete_cn_dossier_returns_matrix_without_rejecting_absent_sections_test() {
  let base = us_dossier()
  let input =
    decode.InspectInput(
      ..base,
      dossier_id: "dossier_cn_000001_2026",
      identity: decode.IdentityInput(
        instrument_id: "CN000001",
        mic: "XSHE",
        track: "cn",
        symbol: Some("000001"),
        share_class: Some("a_share"),
        reporting_entity: "平安银行股份有限公司",
        entity_type: Some("bank"),
        currency: "CNY",
        fiscal_year_end: "12-31",
        isin: None,
        local_id: Some("000001"),
        listing_start: "1991-04-03",
        listing_end: None,
        status: "trading",
      ),
      sections: sections(
        partial("b", ["interim_h1_2026:not_yet_filed"]),
        not_obtained("in_filing_not_extracted"),
        not_obtained("proxy_not_retrieved"),
      ),
      reporting_basis: Some(decode.ReportingBasisInput(
        accounting_standard: "China GAAP",
        fiscal_year_end: "12-31",
        auditor_name: Some("Caller supplied auditor"),
        audit_opinion: "unqualified",
        consolidation: "consolidated",
      )),
      statements: [
        statement(
          "annual_2025",
          "annual",
          "平安银行股份有限公司",
          "CNY",
          "original",
          None,
          "b",
        ),
      ],
    )
  let assert Ok(output) = dossier.inspect(input)
  let text = json.to_string(output.details)
  text |> string.contains("\"state\":\"partially_provided\"") |> should.be_true
  text |> string.contains("in_filing_not_extracted") |> should.be_true
  text |> string.contains("proxy_not_retrieved") |> should.be_true
  text |> string.contains("reviewabilityVerdict\":null") |> should.be_true
}

pub fn identity_section_cannot_be_not_obtained_test() {
  let input = us_dossier()
  let sections =
    decode.SectionsInput(
      ..input.sections,
      identity: not_obtained("identity_missing"),
    )
  let assert Error(dossier.InvalidField("sections.identity.state", _)) =
    dossier.inspect(decode.InspectInput(..input, sections: sections))
}

pub fn unclear_amendment_chain_is_a_mechanical_insufficiency_fact_test() {
  let input = us_dossier()
  let broken =
    statement(
      "10ka_2025",
      "annual",
      "Apple Inc.",
      "USD",
      "amendment",
      Some("missing_original"),
      "d",
    )
  let assert Ok(output) =
    dossier.inspect(decode.InspectInput(..input, statements: [broken]))
  let text = json.to_string(output.details)
  text |> string.contains("amendment_original_not_found") |> should.be_true
  text |> string.contains("amendment_chain_unclear") |> should.be_true
  text
  |> string.contains("\"mechanicalEvidenceState\":\"insufficient_evidence\"")
  |> should.be_true
}

pub fn review_history_must_link_to_the_immediately_prior_review_test() {
  let input = us_dossier()
  let first = review("review_001", None, reviewed_at - 10_000, "2026-01-01")
  let second =
    review("review_002", Some("wrong_prior"), reviewed_at, "2026-02-01")
  let assert Error(dossier.InvalidReviewChain(_)) =
    dossier.inspect(decode.InspectInput(..input, reviews: [first, second]))
}

pub fn gross_margin_calculates_exact_session_19_formula_with_proofs_test() {
  let input =
    decode.MetricInput(
      request_id: "metric_001",
      metric_id: "gross_margin",
      operands: [
        operand("revenue", "383000", "currency", "a"),
        operand("cogs", "210000", "currency", "b"),
      ],
      output_scale: 4,
      rounding: "half_up",
    )
  let assert Ok(output) = metric.calculate(input)
  let text = json.to_string(output.details)
  text |> string.contains("\"state\":\"calculated\"") |> should.be_true
  text |> string.contains("\"value\":\"0.4517\"") |> should.be_true
  text
  |> string.contains("\"formulaVersion\":\"session_19_metric_v1\"")
  |> should.be_true
  text |> string.contains("\"economicInterpretation\":null") |> should.be_true
}

pub fn missing_bank_generic_operand_is_unperformed_without_metric_switch_test() {
  let input =
    decode.MetricInput(
      request_id: "metric_bank_generic",
      metric_id: "gross_margin",
      operands: [operand("revenue", "180000", "currency", "a")],
      output_scale: 4,
      rounding: "half_up",
    )
  let assert Ok(output) = metric.calculate(input)
  let text = json.to_string(output.details)
  text |> string.contains("\"state\":\"unperformed\"") |> should.be_true
  text |> string.contains("\"missingOperands\":[\"cogs\"]") |> should.be_true
  text
  |> string.contains("\"substituteMetricSelected\":false")
  |> should.be_true
}

pub fn bank_net_interest_margin_calculates_only_when_explicitly_selected_test() {
  let input =
    decode.MetricInput(
      request_id: "metric_bank_nim",
      metric_id: "net_interest_margin",
      operands: [
        operand("interest_income", "100000", "currency", "a"),
        operand("interest_expense", "15000", "currency", "b"),
        operand("average_earning_assets", "3800000", "currency", "c"),
      ],
      output_scale: 4,
      rounding: "half_up",
    )
  let assert Ok(output) = metric.calculate(input)
  json.to_string(output.details)
  |> string.contains("\"value\":\"0.0224\"")
  |> should.be_true
}

pub fn non_positive_metric_denominator_is_unperformed_test() {
  let input =
    decode.MetricInput(
      request_id: "metric_zero",
      metric_id: "current_ratio",
      operands: [
        operand("current_assets", "100", "currency", "a"),
        operand("current_liabilities", "0", "currency", "b"),
      ],
      output_scale: 2,
      rounding: "half_even",
    )
  let assert Ok(output) = metric.calculate(input)
  json.to_string(output.details)
  |> string.contains("non_positive_denominator")
  |> should.be_true
}

pub fn valuation_grid_calculates_coherent_enterprise_value_bridge_test() {
  let input = valuation_input("2025-09-30", "2025-09-30")
  let assert Ok(output) = valuation.project(input)
  let text = json.to_string(output.details)
  text |> string.contains("\"state\":\"calculated\"") |> should.be_true
  text |> string.contains("\"equityValue\":\"17500\"") |> should.be_true
  text |> string.contains("\"perShareValue\":\"17.5\"") |> should.be_true
  text |> string.contains("\"authoritativeTargetPrice\":null") |> should.be_true
  text |> string.contains("\"valuationVerdict\":null") |> should.be_true
}

pub fn valuation_grid_keeps_incompatible_period_row_unperformed_test() {
  let input = valuation_input("2025-09-30", "2025-12-31")
  let assert Ok(output) = valuation.project(input)
  let text = json.to_string(output.details)
  text |> string.contains("\"state\":\"unperformed\"") |> should.be_true
  text |> string.contains("incompatible_periods") |> should.be_true
  text |> string.contains("\"calculatedScenarioCount\":0") |> should.be_true
}

fn us_dossier() -> decode.InspectInput {
  decode.InspectInput(
    dossier_id: "dossier_AAPL_2026",
    dossier_as_of: "2026-02-01",
    reviewed_at_unix_ms: reviewed_at,
    identity: decode.IdentityInput(
      instrument_id: "US0378331005",
      mic: "XNAS",
      track: "us",
      symbol: Some("AAPL"),
      share_class: Some("common"),
      reporting_entity: "Apple Inc.",
      entity_type: Some("operating_company"),
      currency: "USD",
      fiscal_year_end: "09-30",
      isin: Some("US0378331005"),
      local_id: None,
      listing_start: "1980-12-12",
      listing_end: None,
      status: "trading",
    ),
    related_listings: [],
    sections: sections(
      provided("b"),
      not_obtained("no_segment_adapter"),
      not_obtained("proxy_not_retrieved"),
    ),
    reporting_basis: Some(decode.ReportingBasisInput(
      accounting_standard: "US-GAAP",
      fiscal_year_end: "09-30",
      auditor_name: Some("Ernst & Young"),
      audit_opinion: "unqualified",
      consolidation: "consolidated",
    )),
    statements: [
      statement(
        "10k_2025",
        "annual",
        "Apple Inc.",
        "USD",
        "original",
        None,
        "b",
      ),
      statement(
        "10ka_2025",
        "annual",
        "Apple Inc.",
        "USD",
        "amendment",
        Some("10k_2025"),
        "c",
      ),
      interim_statement(),
    ],
    reviews: [review("review_001", None, reviewed_at, "2026-02-01")],
  )
}

fn sections(
  statement_set: decode.EvidenceStateInput,
  segment_data: decode.EvidenceStateInput,
  governance: decode.EvidenceStateInput,
) -> decode.SectionsInput {
  decode.SectionsInput(
    identity: provided("a"),
    business_description: caller_declared("LLM thesis v2"),
    reporting_basis: provided("b"),
    statement_set: statement_set,
    segment_data: segment_data,
    debt_liquidity: provided("d"),
    cash_flow_earnings_quality: provided("e"),
    capital_allocation: provided("f"),
    governance_management: governance,
    industry_peers: not_obtained("peer_set_not_selected"),
    macro_context: not_obtained("no_macro_leg_attached"),
    corporate_actions: provided("1"),
    valuation: not_obtained("no_method_selected"),
    thesis_risks: caller_declared("user thesis v1"),
    portfolio_fit: not_obtained("portfolio_not_supplied"),
    review_history: provided("2"),
  )
}

fn provided(marker: String) -> decode.EvidenceStateInput {
  decode.EvidenceStateInput(
    state: "provided",
    receipts: [hash(marker)],
    missing_parts: [],
    reason: None,
    evidence_as_of: None,
    cutoff: None,
    alternatives: [],
    declaration_source: None,
  )
}

fn partial(marker: String, missing: List(String)) -> decode.EvidenceStateInput {
  decode.EvidenceStateInput(
    ..provided(marker),
    state: "partially_provided",
    missing_parts: missing,
  )
}

fn not_obtained(reason: String) -> decode.EvidenceStateInput {
  decode.EvidenceStateInput(
    state: "not_obtained",
    receipts: [],
    missing_parts: [],
    reason: Some(reason),
    evidence_as_of: None,
    cutoff: None,
    alternatives: [],
    declaration_source: None,
  )
}

fn caller_declared(source: String) -> decode.EvidenceStateInput {
  decode.EvidenceStateInput(
    ..not_obtained("caller declaration"),
    state: "caller_declared",
    reason: None,
    declaration_source: Some(source),
  )
}

fn statement(
  id: String,
  kind: String,
  entity: String,
  currency: String,
  amendment: String,
  original_id: Option(String),
  marker: String,
) -> decode.StatementInput {
  decode.StatementInput(
    statement_id: id,
    form_type: case amendment {
      "amendment" -> "10-K/A"
      _ -> "10-K"
    },
    filing_entity: entity,
    period_start: "2024-10-01",
    period_end: "2025-09-30",
    period_kind: kind,
    inclusive_duration_days: 365,
    audit_opinion: "unqualified",
    amendment: amendment,
    original_statement_id: original_id,
    restatement: "not_restated",
    restatement_reason: None,
    consolidation: "consolidated",
    filing_date: Some("2025-11-15"),
    acceptance_date: Some("2025-11-15"),
    source_receipt: hash(marker),
    taxonomy: Some("US-GAAP"),
    currency: currency,
    unit: "millions",
    scale: 6,
  )
}

fn interim_statement() -> decode.StatementInput {
  decode.StatementInput(
    ..statement(
      "10q_q1_2026",
      "quarter",
      "Apple Inc.",
      "USD",
      "original",
      None,
      "d",
    ),
    form_type: "10-Q",
    period_start: "2025-10-01",
    period_end: "2025-12-31",
    inclusive_duration_days: 92,
    filing_date: Some("2026-01-28"),
    acceptance_date: Some("2026-01-28"),
  )
}

fn review(
  id: String,
  prior: Option(String),
  timestamp: Int,
  as_of: String,
) -> decode.ReviewInput {
  decode.ReviewInput(
    review_id: id,
    reviewed_at_unix_ms: timestamp,
    reviewer_kind: "llm_declared",
    reviewer_ref: "course-session-19-fixture",
    dossier_as_of: as_of,
    prior_review_id: prior,
    changes: [
      decode.ReviewChangeInput(
        section: "statement_set",
        kind: "added",
        added_receipts: [hash("b")],
        removed_receipts: [],
      ),
    ],
    conclusion_ref: None,
  )
}

fn operand(
  name: String,
  exact: String,
  unit: String,
  marker: String,
) -> decode.OperandInput {
  decode.OperandInput(
    name: name,
    exact_lexeme: exact,
    entity_id: "Apple Inc.",
    period_start: Some("2024-10-01"),
    period_end: "2025-09-30",
    period_kind: "annual",
    inclusive_duration_days: Some(365),
    currency: "USD",
    unit: unit,
    reported_scale: 6,
    source_receipt: hash(marker),
    basis: "statement_fact",
  )
}

fn valuation_input(
  shares_period: String,
  debt_period: String,
) -> decode.ValuationInput {
  decode.ValuationInput(
    request_id: "valuation_001",
    method: "dcf",
    valuation_currency: "USD",
    scenarios: [
      decode.ValuationScenarioInput(
        label: "caller_case_1",
        method_result: decode.OperandInput(
          ..operand("enterprise_value", "22500", "currency", "a"),
          period_end: "2025-09-30",
          basis: "caller_declared",
        ),
        net_debt: decode.OperandInput(
          ..operand("net_debt", "5000", "currency", "b"),
          period_end: debt_period,
        ),
        diluted_shares: decode.OperandInput(
          ..operand("diluted_shares", "1000", "shares", "c"),
          period_end: shares_period,
        ),
        assumptions: [
          decode.AssumptionInput(
            name: "terminal_growth",
            exact_value: "0.025",
            basis: "caller_declared",
            source_reference: Some("LLM instruction ref-001"),
          ),
        ],
      ),
    ],
    output_scale: 2,
    rounding: "half_even",
  )
}

fn hash(marker: String) -> String {
  string.repeat(marker, times: 64)
}
