import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_investor_workbench/decode
import pi_sparkles_investor_workbench/dossier
import pi_sparkles_investor_workbench/metric
import pi_sparkles_investor_workbench/valuation

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "inspect_dossier",
    "Inspect an investor dossier",
    "Validate one caller-supplied 16-section investor dossier, exact listing identity, statement coverage, evidence states, and append-only review chain, then return a compact completeness matrix without a reviewability or investment verdict",
    "Supply the exact dossier container and receipts; use the matrix and mechanical insufficiency facts as evidence for LLM-owned review",
    tool.parameters(inspect_schema(), decode.inspect_dossier()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case dossier.inspect(input) {
        Ok(output) ->
          tool.text_result(output.summary, output.details)
          |> promise.resolve
        Error(error) -> tool.reject(dossier.error_message(error))
      }
    },
  )
  tool.register(
    api,
    "dossier_metric",
    "Calculate a dossier metric",
    "Calculate one explicitly selected Session 19 mechanical metric over caller-supplied exact operands with entity, period, unit, scale, basis, and receipt proof; missing or incompatible inputs remain unperformed",
    "Select the metric and supply only its named operands; the result is arithmetic evidence, never an economic interpretation or substitute metric",
    tool.parameters(metric_schema(), decode.dossier_metric()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case metric.calculate(input) {
        Ok(output) ->
          tool.text_result(output.summary, output.details)
          |> promise.resolve
        Error(error) -> tool.reject(metric.error_message(error))
      }
    },
  )
  tool.register(
    api,
    "dossier_valuation",
    "Project a dossier valuation grid",
    "Convert caller-supplied method results into bounded enterprise-to-equity per-share scenario rows using exact same-entity, same-period net debt and diluted shares with explicit assumptions and no target-price or valuation verdict",
    "Select the valuation method and supply labelled scenarios; labels and assumptions stay caller-owned, and incompatible rows remain unperformed",
    tool.parameters(valuation_schema(), decode.dossier_valuation()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case valuation.project(input) {
        Ok(output) ->
          tool.text_result(output.summary, output.details)
          |> promise.resolve
        Error(error) -> tool.reject(valuation.error_message(error))
      }
    },
  )
  promise.resolve(Nil)
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Required("dossierId", bounded_string(1, 500)),
    schema.Required("dossierAsOf", date_schema()),
    schema.Required("reviewedAtUnixMilliseconds", safe_integer()),
    schema.Required("identity", identity_schema()),
    schema.Required(
      "relatedListings",
      schema.array(related_listing_schema()) |> schema.with_array_length(0, 100),
    ),
    schema.Required("sections", sections_schema()),
    schema.Optional("reportingBasis", schema.nullable(reporting_basis_schema())),
    schema.Required(
      "statements",
      schema.array(statement_schema()) |> schema.with_array_length(0, 100),
    ),
    schema.Required(
      "reviews",
      schema.array(review_schema()) |> schema.with_array_length(1, 100),
    ),
  ])
}

fn sections_schema() -> schema.Schema {
  schema.object([
    schema.Required("identity", evidence_state_schema()),
    schema.Required("businessDescription", evidence_state_schema()),
    schema.Required("reportingBasis", evidence_state_schema()),
    schema.Required("statementSet", evidence_state_schema()),
    schema.Required("segmentData", evidence_state_schema()),
    schema.Required("debtLiquidity", evidence_state_schema()),
    schema.Required("cashFlowEarningsQuality", evidence_state_schema()),
    schema.Required("capitalAllocation", evidence_state_schema()),
    schema.Required("governanceManagement", evidence_state_schema()),
    schema.Required("industryPeers", evidence_state_schema()),
    schema.Required("macroContext", evidence_state_schema()),
    schema.Required("corporateActions", evidence_state_schema()),
    schema.Required("valuation", evidence_state_schema()),
    schema.Required("thesisRisks", evidence_state_schema()),
    schema.Required("portfolioFit", evidence_state_schema()),
    schema.Required("reviewHistory", evidence_state_schema()),
  ])
}

fn evidence_state_schema() -> schema.Schema {
  schema.one_of([
    schema.object([
      schema.Required("state", schema.literal_string("provided")),
      schema.Required(
        "receipts",
        schema.array(hash_schema()) |> schema.with_array_length(1, 100),
      ),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("partially_provided")),
      schema.Required(
        "receipts",
        schema.array(hash_schema()) |> schema.with_array_length(1, 100),
      ),
      schema.Required(
        "missingParts",
        schema.array(bounded_string(1, 1000))
          |> schema.with_array_length(1, 100),
      ),
    ]),
    reason_state_schema("not_obtained"),
    reason_state_schema("not_available"),
    schema.object([
      schema.Required("state", schema.literal_string("stale")),
      schema.Required(
        "receipts",
        schema.array(hash_schema()) |> schema.with_array_length(1, 100),
      ),
      schema.Required("evidenceAsOf", date_schema()),
      schema.Required("cutoff", date_schema()),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("conflicting")),
      schema.Required(
        "alternatives",
        schema.array(hash_schema()) |> schema.with_array_length(2, 100),
      ),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("caller_declared")),
      schema.Required("declarationSource", bounded_string(1, 4096)),
    ]),
    reason_state_schema("incompatible"),
  ])
}

fn reason_state_schema(state: String) -> schema.Schema {
  schema.object([
    schema.Required("state", schema.literal_string(state)),
    schema.Required("reason", bounded_string(1, 4096)),
  ])
}

fn identity_schema() -> schema.Schema {
  schema.object([
    schema.Required("instrumentId", bounded_string(1, 500)),
    schema.Required(
      "mic",
      schema.string_enum(["XSHG", "XSHE", "XBSE", "XHKG", "XNYS", "XNAS"]),
    ),
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Optional("symbol", schema.nullable(bounded_string(1, 100))),
    schema.Optional("shareClass", schema.nullable(bounded_string(1, 200))),
    schema.Required("reportingEntity", bounded_string(1, 500)),
    schema.Optional("entityType", schema.nullable(bounded_string(1, 200))),
    schema.Required("currency", bounded_string(1, 20)),
    schema.Required("fiscalYearEnd", month_day_schema()),
    schema.Optional("isin", schema.nullable(bounded_string(1, 20))),
    schema.Optional("localId", schema.nullable(bounded_string(1, 100))),
    schema.Required("listingStart", date_schema()),
    schema.Optional("listingEnd", schema.nullable(date_schema())),
    schema.Required(
      "status",
      schema.string_enum(["trading", "suspended", "delisted"]),
    ),
  ])
}

fn related_listing_schema() -> schema.Schema {
  schema.object([
    schema.Required("instrumentId", bounded_string(1, 500)),
    schema.Required(
      "mic",
      schema.string_enum(["XSHG", "XSHE", "XBSE", "XHKG", "XNYS", "XNAS"]),
    ),
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("currency", bounded_string(1, 20)),
    schema.Required(
      "relationship",
      schema.string_enum([
        "a_share",
        "h_share",
        "adr",
        "ordinary",
        "preferred",
        "other_declared",
      ]),
    ),
  ])
}

fn reporting_basis_schema() -> schema.Schema {
  schema.object([
    schema.Required("accountingStandard", bounded_string(1, 100)),
    schema.Required("fiscalYearEnd", month_day_schema()),
    schema.Optional("auditorName", schema.nullable(bounded_string(1, 500))),
    schema.Required("auditOpinion", audit_opinion_schema()),
    schema.Required("consolidation", consolidation_schema()),
  ])
}

fn statement_schema() -> schema.Schema {
  schema.object([
    schema.Required("statementId", bounded_string(1, 500)),
    schema.Required("formType", bounded_string(1, 100)),
    schema.Required("filingEntity", bounded_string(1, 500)),
    schema.Required("periodStart", date_schema()),
    schema.Required("periodEnd", date_schema()),
    schema.Required(
      "periodKind",
      schema.string_enum(["annual", "interim", "quarter", "semi_annual"]),
    ),
    schema.Required("inclusiveDurationDays", bounded_integer(1.0, 1000.0)),
    schema.Required("auditOpinion", audit_opinion_schema()),
    schema.Required("amendment", schema.string_enum(["original", "amendment"])),
    schema.Optional(
      "originalStatementId",
      schema.nullable(bounded_string(1, 500)),
    ),
    schema.Required(
      "restatement",
      schema.string_enum(["not_restated", "restated"]),
    ),
    schema.Optional(
      "restatementReason",
      schema.nullable(bounded_string(1, 4096)),
    ),
    schema.Required("consolidation", consolidation_schema()),
    schema.Optional("filingDate", schema.nullable(date_schema())),
    schema.Optional("acceptanceDate", schema.nullable(date_schema())),
    schema.Required("sourceReceipt", hash_schema()),
    schema.Optional("taxonomy", schema.nullable(bounded_string(1, 100))),
    schema.Required("currency", bounded_string(1, 20)),
    schema.Required("unit", bounded_string(1, 100)),
    schema.Required("scale", bounded_integer(-18.0, 18.0)),
  ])
}

fn review_schema() -> schema.Schema {
  schema.object([
    schema.Required("reviewId", bounded_string(1, 500)),
    schema.Required("reviewedAtUnixMilliseconds", safe_integer()),
    schema.Required(
      "reviewerKind",
      schema.string_enum(["user_declared", "llm_declared"]),
    ),
    schema.Required("reviewerRef", bounded_string(1, 1000)),
    schema.Required("dossierAsOf", date_schema()),
    schema.Optional("priorReviewId", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "changes",
      schema.array(review_change_schema()) |> schema.with_array_length(0, 16),
    ),
    schema.Optional("conclusionRef", schema.nullable(bounded_string(1, 1000))),
  ])
}

fn review_change_schema() -> schema.Schema {
  schema.object([
    schema.Required("section", section_name_schema()),
    schema.Required("kind", schema.string_enum(["added", "changed", "removed"])),
    schema.Required(
      "addedReceipts",
      schema.array(hash_schema()) |> schema.with_array_length(0, 100),
    ),
    schema.Required(
      "removedReceipts",
      schema.array(hash_schema()) |> schema.with_array_length(0, 100),
    ),
  ])
}

fn metric_schema() -> schema.Schema {
  schema.object([
    schema.Required("requestId", bounded_string(1, 500)),
    schema.Required(
      "metricId",
      schema.string_enum([
        "current_ratio", "debt_to_equity", "gross_margin", "operating_margin",
        "net_margin", "revenue_growth", "fcf_conversion", "interest_coverage",
        "bvps", "eps", "dividend_yield", "payout_ratio", "net_interest_margin",
        "combined_ratio", "reit_ffo", "reit_affo", "reserve_life", "cash_runway",
      ]),
    ),
    schema.Required(
      "operands",
      schema.array(operand_schema()) |> schema.with_array_length(0, 10),
    ),
    schema.Required("outputScale", bounded_integer(0.0, 18.0)),
    schema.Required("rounding", rounding_schema()),
  ])
}

fn operand_schema() -> schema.Schema {
  schema.object([
    schema.Required("name", bounded_string(1, 100)),
    schema.Required("exactLexeme", bounded_string(1, 500)),
    schema.Required("entityId", bounded_string(1, 500)),
    schema.Optional("periodStart", schema.nullable(date_schema())),
    schema.Required("periodEnd", date_schema()),
    schema.Required(
      "periodKind",
      schema.string_enum([
        "instant",
        "annual",
        "interim",
        "quarter",
        "semi_annual",
      ]),
    ),
    schema.Optional(
      "inclusiveDurationDays",
      schema.nullable(bounded_integer(1.0, 1000.0)),
    ),
    schema.Required("currency", bounded_string(1, 20)),
    schema.Required("unit", bounded_string(1, 100)),
    schema.Required("reportedScale", bounded_integer(-18.0, 18.0)),
    schema.Required("sourceReceipt", hash_schema()),
    schema.Required(
      "basis",
      schema.string_enum([
        "statement_fact",
        "consensus_estimate",
        "caller_declared",
        "historical_average",
      ]),
    ),
  ])
}

fn valuation_schema() -> schema.Schema {
  schema.object([
    schema.Required("requestId", bounded_string(1, 500)),
    schema.Required(
      "method",
      schema.string_enum([
        "comparable_multiples",
        "historical_multiples",
        "dcf",
        "dividend_discount",
        "asset_nav",
        "sector_specific",
      ]),
    ),
    schema.Required("valuationCurrency", bounded_string(1, 20)),
    schema.Required(
      "scenarios",
      schema.array(valuation_scenario_schema())
        |> schema.with_array_length(1, 25),
    ),
    schema.Required("outputScale", bounded_integer(0.0, 18.0)),
    schema.Required("rounding", rounding_schema()),
  ])
}

fn valuation_scenario_schema() -> schema.Schema {
  schema.object([
    schema.Required("label", bounded_string(1, 200)),
    schema.Required("methodResult", operand_schema()),
    schema.Required("netDebt", operand_schema()),
    schema.Required("dilutedShares", operand_schema()),
    schema.Required(
      "assumptions",
      schema.array(assumption_schema()) |> schema.with_array_length(1, 100),
    ),
  ])
}

fn assumption_schema() -> schema.Schema {
  schema.object([
    schema.Required("name", bounded_string(1, 200)),
    schema.Required("exactValue", bounded_string(1, 1000)),
    schema.Required(
      "basis",
      schema.string_enum([
        "statement_fact",
        "consensus_estimate",
        "caller_declared",
        "historical_average",
      ]),
    ),
    schema.Optional("sourceReference", schema.nullable(bounded_string(1, 4096))),
  ])
}

fn section_name_schema() -> schema.Schema {
  schema.string_enum([
    "identity", "business_description", "reporting_basis", "statement_set",
    "segment_data", "debt_liquidity", "cash_flow_earnings_quality",
    "capital_allocation", "governance_management", "industry_peers",
    "macro_context", "corporate_actions", "valuation", "thesis_risks",
    "portfolio_fit", "review_history",
  ])
}

fn audit_opinion_schema() -> schema.Schema {
  schema.string_enum([
    "unqualified",
    "qualified",
    "adverse",
    "disclaimer",
    "unknown",
  ])
}

fn consolidation_schema() -> schema.Schema {
  schema.string_enum(["consolidated", "parent_only", "segment"])
}

fn rounding_schema() -> schema.Schema {
  schema.string_enum(["toward_zero", "away_from_zero", "half_up", "half_even"])
}

fn date_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(10, 10)
}

fn month_day_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(5, 5)
}

fn hash_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(64, 64)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Float, maximum: Float) -> schema.Schema {
  schema.integer() |> schema.with_number_range(minimum, maximum)
}

fn safe_integer() -> schema.Schema {
  bounded_integer(0.0, 9_007_199_254_740_991.0)
}
