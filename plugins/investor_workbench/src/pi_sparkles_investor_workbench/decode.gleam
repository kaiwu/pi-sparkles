import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type EvidenceStateInput {
  EvidenceStateInput(
    state: String,
    receipts: List(String),
    missing_parts: List(String),
    reason: Option(String),
    evidence_as_of: Option(String),
    cutoff: Option(String),
    alternatives: List(String),
    declaration_source: Option(String),
  )
}

pub type SectionsInput {
  SectionsInput(
    identity: EvidenceStateInput,
    business_description: EvidenceStateInput,
    reporting_basis: EvidenceStateInput,
    statement_set: EvidenceStateInput,
    segment_data: EvidenceStateInput,
    debt_liquidity: EvidenceStateInput,
    cash_flow_earnings_quality: EvidenceStateInput,
    capital_allocation: EvidenceStateInput,
    governance_management: EvidenceStateInput,
    industry_peers: EvidenceStateInput,
    macro_context: EvidenceStateInput,
    corporate_actions: EvidenceStateInput,
    valuation: EvidenceStateInput,
    thesis_risks: EvidenceStateInput,
    portfolio_fit: EvidenceStateInput,
    review_history: EvidenceStateInput,
  )
}

pub type IdentityInput {
  IdentityInput(
    instrument_id: String,
    mic: String,
    track: String,
    symbol: Option(String),
    share_class: Option(String),
    reporting_entity: String,
    entity_type: Option(String),
    currency: String,
    fiscal_year_end: String,
    isin: Option(String),
    local_id: Option(String),
    listing_start: String,
    listing_end: Option(String),
    status: String,
  )
}

pub type RelatedListingInput {
  RelatedListingInput(
    instrument_id: String,
    mic: String,
    track: String,
    currency: String,
    relationship: String,
  )
}

pub type ReportingBasisInput {
  ReportingBasisInput(
    accounting_standard: String,
    fiscal_year_end: String,
    auditor_name: Option(String),
    audit_opinion: String,
    consolidation: String,
  )
}

pub type StatementInput {
  StatementInput(
    statement_id: String,
    form_type: String,
    filing_entity: String,
    period_start: String,
    period_end: String,
    period_kind: String,
    inclusive_duration_days: Int,
    audit_opinion: String,
    amendment: String,
    original_statement_id: Option(String),
    restatement: String,
    restatement_reason: Option(String),
    consolidation: String,
    filing_date: Option(String),
    acceptance_date: Option(String),
    source_receipt: String,
    taxonomy: Option(String),
    currency: String,
    unit: String,
    scale: Int,
  )
}

pub type ReviewChangeInput {
  ReviewChangeInput(
    section: String,
    kind: String,
    added_receipts: List(String),
    removed_receipts: List(String),
  )
}

pub type ReviewInput {
  ReviewInput(
    review_id: String,
    reviewed_at_unix_ms: Int,
    reviewer_kind: String,
    reviewer_ref: String,
    dossier_as_of: String,
    prior_review_id: Option(String),
    changes: List(ReviewChangeInput),
    conclusion_ref: Option(String),
  )
}

pub type InspectInput {
  InspectInput(
    dossier_id: String,
    dossier_as_of: String,
    reviewed_at_unix_ms: Int,
    identity: IdentityInput,
    related_listings: List(RelatedListingInput),
    sections: SectionsInput,
    reporting_basis: Option(ReportingBasisInput),
    statements: List(StatementInput),
    reviews: List(ReviewInput),
  )
}

pub type OperandInput {
  OperandInput(
    name: String,
    exact_lexeme: String,
    entity_id: String,
    period_start: Option(String),
    period_end: String,
    period_kind: String,
    inclusive_duration_days: Option(Int),
    currency: String,
    unit: String,
    reported_scale: Int,
    source_receipt: String,
    basis: String,
  )
}

pub type MetricInput {
  MetricInput(
    request_id: String,
    metric_id: String,
    operands: List(OperandInput),
    output_scale: Int,
    rounding: String,
  )
}

pub type AssumptionInput {
  AssumptionInput(
    name: String,
    exact_value: String,
    basis: String,
    source_reference: Option(String),
  )
}

pub type ValuationScenarioInput {
  ValuationScenarioInput(
    label: String,
    method_result: OperandInput,
    net_debt: OperandInput,
    diluted_shares: OperandInput,
    assumptions: List(AssumptionInput),
  )
}

pub type ValuationInput {
  ValuationInput(
    request_id: String,
    method: String,
    valuation_currency: String,
    scenarios: List(ValuationScenarioInput),
    output_scale: Int,
    rounding: String,
  )
}

pub fn inspect_dossier() -> decoder.Decoder(InspectInput) {
  use dossier_id <- decoder.field("dossierId", decoder.string)
  use dossier_as_of <- decoder.field("dossierAsOf", decoder.string)
  use reviewed_at <- decoder.field("reviewedAtUnixMilliseconds", decoder.int)
  use identity <- decoder.field("identity", identity_decoder())
  use related <- decoder.field(
    "relatedListings",
    decoder.list(of: related_listing_decoder()),
  )
  use sections <- decoder.field("sections", sections_decoder())
  use reporting_basis <- decoder.optional_field(
    "reportingBasis",
    None,
    decoder.optional(reporting_basis_decoder()),
  )
  use statements <- decoder.field(
    "statements",
    decoder.list(of: statement_decoder()),
  )
  use reviews <- decoder.field("reviews", decoder.list(of: review_decoder()))
  decoder.success(InspectInput(
    dossier_id,
    dossier_as_of,
    reviewed_at,
    identity,
    related,
    sections,
    reporting_basis,
    statements,
    reviews,
  ))
}

pub fn dossier_metric() -> decoder.Decoder(MetricInput) {
  use request_id <- decoder.field("requestId", decoder.string)
  use metric_id <- decoder.field("metricId", decoder.string)
  use operands <- decoder.field("operands", decoder.list(of: operand_decoder()))
  use output_scale <- decoder.field("outputScale", decoder.int)
  use rounding <- decoder.field("rounding", decoder.string)
  decoder.success(MetricInput(
    request_id,
    metric_id,
    operands,
    output_scale,
    rounding,
  ))
}

pub fn dossier_valuation() -> decoder.Decoder(ValuationInput) {
  use request_id <- decoder.field("requestId", decoder.string)
  use method <- decoder.field("method", decoder.string)
  use currency <- decoder.field("valuationCurrency", decoder.string)
  use scenarios <- decoder.field(
    "scenarios",
    decoder.list(of: valuation_scenario_decoder()),
  )
  use output_scale <- decoder.field("outputScale", decoder.int)
  use rounding <- decoder.field("rounding", decoder.string)
  decoder.success(ValuationInput(
    request_id,
    method,
    currency,
    scenarios,
    output_scale,
    rounding,
  ))
}

fn evidence_state_decoder() -> decoder.Decoder(EvidenceStateInput) {
  use state <- decoder.field("state", decoder.string)
  use receipts <- decoder.optional_field(
    "receipts",
    [],
    decoder.list(of: decoder.string),
  )
  use missing_parts <- decoder.optional_field(
    "missingParts",
    [],
    decoder.list(of: decoder.string),
  )
  use reason <- decoder.optional_field(
    "reason",
    None,
    decoder.optional(decoder.string),
  )
  use evidence_as_of <- decoder.optional_field(
    "evidenceAsOf",
    None,
    decoder.optional(decoder.string),
  )
  use cutoff <- decoder.optional_field(
    "cutoff",
    None,
    decoder.optional(decoder.string),
  )
  use alternatives <- decoder.optional_field(
    "alternatives",
    [],
    decoder.list(of: decoder.string),
  )
  use declaration_source <- decoder.optional_field(
    "declarationSource",
    None,
    decoder.optional(decoder.string),
  )
  decoder.success(EvidenceStateInput(
    state,
    receipts,
    missing_parts,
    reason,
    evidence_as_of,
    cutoff,
    alternatives,
    declaration_source,
  ))
}

fn sections_decoder() -> decoder.Decoder(SectionsInput) {
  use identity <- decoder.field("identity", evidence_state_decoder())
  use business <- decoder.field("businessDescription", evidence_state_decoder())
  use basis <- decoder.field("reportingBasis", evidence_state_decoder())
  use statements <- decoder.field("statementSet", evidence_state_decoder())
  use segments <- decoder.field("segmentData", evidence_state_decoder())
  use debt <- decoder.field("debtLiquidity", evidence_state_decoder())
  use cash_flow <- decoder.field(
    "cashFlowEarningsQuality",
    evidence_state_decoder(),
  )
  use allocation <- decoder.field("capitalAllocation", evidence_state_decoder())
  use governance <- decoder.field(
    "governanceManagement",
    evidence_state_decoder(),
  )
  use industry <- decoder.field("industryPeers", evidence_state_decoder())
  use macro_context <- decoder.field("macroContext", evidence_state_decoder())
  use actions <- decoder.field("corporateActions", evidence_state_decoder())
  use valuation <- decoder.field("valuation", evidence_state_decoder())
  use thesis <- decoder.field("thesisRisks", evidence_state_decoder())
  use portfolio <- decoder.field("portfolioFit", evidence_state_decoder())
  use reviews <- decoder.field("reviewHistory", evidence_state_decoder())
  decoder.success(SectionsInput(
    identity,
    business,
    basis,
    statements,
    segments,
    debt,
    cash_flow,
    allocation,
    governance,
    industry,
    macro_context,
    actions,
    valuation,
    thesis,
    portfolio,
    reviews,
  ))
}

fn identity_decoder() -> decoder.Decoder(IdentityInput) {
  use instrument_id <- decoder.field("instrumentId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use symbol <- decoder.optional_field(
    "symbol",
    None,
    decoder.optional(decoder.string),
  )
  use share_class <- decoder.optional_field(
    "shareClass",
    None,
    decoder.optional(decoder.string),
  )
  use reporting_entity <- decoder.field("reportingEntity", decoder.string)
  use entity_type <- decoder.optional_field(
    "entityType",
    None,
    decoder.optional(decoder.string),
  )
  use currency <- decoder.field("currency", decoder.string)
  use fiscal_year_end <- decoder.field("fiscalYearEnd", decoder.string)
  use isin <- decoder.optional_field(
    "isin",
    None,
    decoder.optional(decoder.string),
  )
  use local_id <- decoder.optional_field(
    "localId",
    None,
    decoder.optional(decoder.string),
  )
  use listing_start <- decoder.field("listingStart", decoder.string)
  use listing_end <- decoder.optional_field(
    "listingEnd",
    None,
    decoder.optional(decoder.string),
  )
  use status <- decoder.field("status", decoder.string)
  decoder.success(IdentityInput(
    instrument_id,
    mic,
    track,
    symbol,
    share_class,
    reporting_entity,
    entity_type,
    currency,
    fiscal_year_end,
    isin,
    local_id,
    listing_start,
    listing_end,
    status,
  ))
}

fn related_listing_decoder() -> decoder.Decoder(RelatedListingInput) {
  use instrument_id <- decoder.field("instrumentId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use currency <- decoder.field("currency", decoder.string)
  use relationship <- decoder.field("relationship", decoder.string)
  decoder.success(RelatedListingInput(
    instrument_id,
    mic,
    track,
    currency,
    relationship,
  ))
}

fn reporting_basis_decoder() -> decoder.Decoder(ReportingBasisInput) {
  use standard <- decoder.field("accountingStandard", decoder.string)
  use fiscal_year_end <- decoder.field("fiscalYearEnd", decoder.string)
  use auditor <- decoder.optional_field(
    "auditorName",
    None,
    decoder.optional(decoder.string),
  )
  use opinion <- decoder.field("auditOpinion", decoder.string)
  use consolidation <- decoder.field("consolidation", decoder.string)
  decoder.success(ReportingBasisInput(
    standard,
    fiscal_year_end,
    auditor,
    opinion,
    consolidation,
  ))
}

fn statement_decoder() -> decoder.Decoder(StatementInput) {
  use statement_id <- decoder.field("statementId", decoder.string)
  use form_type <- decoder.field("formType", decoder.string)
  use filing_entity <- decoder.field("filingEntity", decoder.string)
  use period_start <- decoder.field("periodStart", decoder.string)
  use period_end <- decoder.field("periodEnd", decoder.string)
  use period_kind <- decoder.field("periodKind", decoder.string)
  use duration <- decoder.field("inclusiveDurationDays", decoder.int)
  use audit_opinion <- decoder.field("auditOpinion", decoder.string)
  use amendment <- decoder.field("amendment", decoder.string)
  use original_id <- decoder.optional_field(
    "originalStatementId",
    None,
    decoder.optional(decoder.string),
  )
  use restatement <- decoder.field("restatement", decoder.string)
  use restatement_reason <- decoder.optional_field(
    "restatementReason",
    None,
    decoder.optional(decoder.string),
  )
  use consolidation <- decoder.field("consolidation", decoder.string)
  use filing_date <- decoder.optional_field(
    "filingDate",
    None,
    decoder.optional(decoder.string),
  )
  use acceptance_date <- decoder.optional_field(
    "acceptanceDate",
    None,
    decoder.optional(decoder.string),
  )
  use source_receipt <- decoder.field("sourceReceipt", decoder.string)
  use taxonomy <- decoder.optional_field(
    "taxonomy",
    None,
    decoder.optional(decoder.string),
  )
  use currency <- decoder.field("currency", decoder.string)
  use unit <- decoder.field("unit", decoder.string)
  use scale <- decoder.field("scale", decoder.int)
  decoder.success(StatementInput(
    statement_id,
    form_type,
    filing_entity,
    period_start,
    period_end,
    period_kind,
    duration,
    audit_opinion,
    amendment,
    original_id,
    restatement,
    restatement_reason,
    consolidation,
    filing_date,
    acceptance_date,
    source_receipt,
    taxonomy,
    currency,
    unit,
    scale,
  ))
}

fn review_decoder() -> decoder.Decoder(ReviewInput) {
  use review_id <- decoder.field("reviewId", decoder.string)
  use reviewed_at <- decoder.field("reviewedAtUnixMilliseconds", decoder.int)
  use reviewer_kind <- decoder.field("reviewerKind", decoder.string)
  use reviewer_ref <- decoder.field("reviewerRef", decoder.string)
  use dossier_as_of <- decoder.field("dossierAsOf", decoder.string)
  use prior_id <- decoder.optional_field(
    "priorReviewId",
    None,
    decoder.optional(decoder.string),
  )
  use changes <- decoder.field(
    "changes",
    decoder.list(of: review_change_decoder()),
  )
  use conclusion_ref <- decoder.optional_field(
    "conclusionRef",
    None,
    decoder.optional(decoder.string),
  )
  decoder.success(ReviewInput(
    review_id,
    reviewed_at,
    reviewer_kind,
    reviewer_ref,
    dossier_as_of,
    prior_id,
    changes,
    conclusion_ref,
  ))
}

fn review_change_decoder() -> decoder.Decoder(ReviewChangeInput) {
  use section <- decoder.field("section", decoder.string)
  use kind <- decoder.field("kind", decoder.string)
  use added <- decoder.field("addedReceipts", decoder.list(of: decoder.string))
  use removed <- decoder.field(
    "removedReceipts",
    decoder.list(of: decoder.string),
  )
  decoder.success(ReviewChangeInput(section, kind, added, removed))
}

fn operand_decoder() -> decoder.Decoder(OperandInput) {
  use name <- decoder.field("name", decoder.string)
  use exact_lexeme <- decoder.field("exactLexeme", decoder.string)
  use entity_id <- decoder.field("entityId", decoder.string)
  use period_start <- decoder.optional_field(
    "periodStart",
    None,
    decoder.optional(decoder.string),
  )
  use period_end <- decoder.field("periodEnd", decoder.string)
  use period_kind <- decoder.field("periodKind", decoder.string)
  use duration <- decoder.optional_field(
    "inclusiveDurationDays",
    None,
    decoder.optional(decoder.int),
  )
  use currency <- decoder.field("currency", decoder.string)
  use unit <- decoder.field("unit", decoder.string)
  use scale <- decoder.field("reportedScale", decoder.int)
  use receipt <- decoder.field("sourceReceipt", decoder.string)
  use basis <- decoder.field("basis", decoder.string)
  decoder.success(OperandInput(
    name,
    exact_lexeme,
    entity_id,
    period_start,
    period_end,
    period_kind,
    duration,
    currency,
    unit,
    scale,
    receipt,
    basis,
  ))
}

fn valuation_scenario_decoder() -> decoder.Decoder(ValuationScenarioInput) {
  use label <- decoder.field("label", decoder.string)
  use method_result <- decoder.field("methodResult", operand_decoder())
  use net_debt <- decoder.field("netDebt", operand_decoder())
  use shares <- decoder.field("dilutedShares", operand_decoder())
  use assumptions <- decoder.field(
    "assumptions",
    decoder.list(of: assumption_decoder()),
  )
  decoder.success(ValuationScenarioInput(
    label,
    method_result,
    net_debt,
    shares,
    assumptions,
  ))
}

fn assumption_decoder() -> decoder.Decoder(AssumptionInput) {
  use name <- decoder.field("name", decoder.string)
  use value <- decoder.field("exactValue", decoder.string)
  use basis <- decoder.field("basis", decoder.string)
  use source <- decoder.optional_field(
    "sourceReference",
    None,
    decoder.optional(decoder.string),
  )
  decoder.success(AssumptionInput(name, value, basis, source))
}
