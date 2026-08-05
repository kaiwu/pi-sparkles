import finance_provider_strategy/coverage
import finance_provider_strategy/credibility
import finance_track.{type Track}
import gleam/int
import gleam/list

/// Track-level navigation receipt.
///
/// Source credibility is an evidence-maturity score for the implemented
/// canonical source stack. Feature coverage is installation-aware and counts
/// only end-user surfaces active in the current Pi runtime.
pub opaque type Receipt {
  Receipt(
    source_credibility: credibility.Assessment,
    feature_coverage: coverage.Assessment,
  )
}

pub fn inspect(track_value: Track, active_tools: List(String)) -> Receipt {
  let source_credibility = source_assessment(track_value)
  let feature_coverage = feature_assessment(track_value, active_tools)
  Receipt(source_credibility, feature_coverage)
}

pub fn source_credibility(value: Receipt) -> credibility.Assessment {
  value.source_credibility
}

pub fn feature_coverage(value: Receipt) -> coverage.Assessment {
  value.feature_coverage
}

pub fn source_percentage(value: Receipt) -> Int {
  value.source_credibility |> credibility.score_percentage
}

pub fn feature_percentage(value: Receipt) -> Int {
  let basis_points = value.feature_coverage |> coverage.coverage_basis_points
  let assert Ok(percentage) = int.divide(basis_points, by: 100)
  percentage
}

pub fn feature_gaps(value: Receipt) -> List(String) {
  value.feature_coverage |> coverage.missing_requirements
}

pub fn source_critical_gaps(value: Receipt) -> List(String) {
  value.source_credibility |> credibility.critical_gaps
}

fn source_assessment(track: Track) -> credibility.Assessment {
  let #(source_set, criteria) = case track {
    finance_track.Cn -> #("cn_authority_stack_v1", cn_criteria())
    finance_track.Hk -> #("hk_authority_stack_v1", hk_criteria())
    finance_track.Us -> #("us_sec_stack_v1", us_criteria())
  }
  let assert Ok(value) =
    credibility.operational_assessment(track, source_set, criteria)
  value
}

fn feature_assessment(
  track: Track,
  active_tools: List(String),
) -> coverage.Assessment {
  let assert Ok(policy) =
    coverage.operational_policy(track, "end_user_features_v1", 1)
  let contributions = [
    navigation_contribution(track),
    ..tool_contributions(track, active_tools)
  ]
  let assert Ok(value) =
    coverage.assess(policy, feature_requirements(), contributions)
  value
}

fn feature_requirements() -> List(coverage.Requirement) {
  [
    feature("navigation_context", coverage.Critical),
    feature("source_registry", coverage.Critical),
    feature("security_identity", coverage.Critical),
    feature("market_calendar", coverage.Standard),
    feature("effective_rules", coverage.Standard),
    feature("quotes_history", coverage.Standard),
    feature("disclosure_discovery", coverage.Standard),
    feature("raw_fundamentals", coverage.Standard),
    feature("normalized_fundamentals", coverage.Standard),
    feature("reproducible_derivations", coverage.Standard),
  ]
}

fn navigation_contribution(track: Track) -> coverage.Contribution {
  contribution(
    track,
    finance_track.name(track) <> "_navigation",
    "pi_sparkles_track_status",
    ["navigation_context"],
  )
}

fn tool_contributions(
  track: Track,
  active_tools: List(String),
) -> List(coverage.Contribution) {
  case track {
    finance_track.Cn ->
      []
      |> append_when(
        has_any(active_tools, ["cn_authorities", "cn_capabilities"]),
        contribution(track, "cn_source_registry", "cn_setup", [
          "source_registry",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "cn_security_search"),
        contribution(track, "cn_security_identity", "CNINFO", [
          "security_identity",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "cn_market_calendar"),
        contribution(track, "cn_market_calendar", "SSE_SZSE_BSE", [
          "market_calendar",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "cn_trading_rules"),
        contribution(track, "cn_effective_rules", "SSE_SZSE_BSE", [
          "effective_rules",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "cn_disclosure_search"),
        contribution(track, "cn_disclosure_discovery", "CNINFO", [
          "disclosure_discovery",
        ]),
      )
      |> append_when(
        has_all(active_tools, ["cn_stock_quote", "cn_stock_history"]),
        contribution(track, "cn_quotes_history", "Eastmoney", [
          "quotes_history",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "cn_financial_statement"),
        contribution(track, "cn_raw_fundamentals", "Eastmoney", [
          "raw_fundamentals",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "cn_stock_fundamental"),
        contribution(track, "cn_normalized_fundamentals", "Eastmoney", [
          "normalized_fundamentals",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "cn_stock_fundamental_metric"),
        contribution(track, "cn_reproducible_derivations", "Eastmoney", [
          "reproducible_derivations",
        ]),
      )
    finance_track.Hk ->
      []
      |> append_when(
        has_any(active_tools, ["hk_authorities", "hk_capabilities"]),
        contribution(track, "hk_source_registry", "hk_setup", [
          "source_registry",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "hk_security_search"),
        contribution(track, "hk_security_identity", "HKEXnews", [
          "security_identity",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "hk_market_calendar"),
        contribution(track, "hk_market_calendar", "HKEX", [
          "market_calendar",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "hk_trading_rules"),
        contribution(track, "hk_effective_rules", "HKEX", [
          "effective_rules",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "hk_disclosure_search"),
        contribution(track, "hk_disclosure_discovery", "HKEXnews", [
          "disclosure_discovery",
        ]),
      )
      |> append_when(
        has_all(active_tools, ["hk_stock_quote", "hk_stock_history"]),
        contribution(track, "hk_quotes_history", "Eastmoney", [
          "quotes_history",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "hk_financial_statement"),
        contribution(track, "hk_raw_fundamentals", "Eastmoney", [
          "raw_fundamentals",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "hk_stock_fundamental"),
        contribution(track, "hk_normalized_fundamentals", "Eastmoney", [
          "normalized_fundamentals",
        ]),
      )
      |> append_when(
        list.contains(active_tools, "hk_stock_fundamental_metric"),
        contribution(track, "hk_reproducible_derivations", "Eastmoney", [
          "reproducible_derivations",
        ]),
      )
    finance_track.Us -> us_tool_contributions(active_tools)
  }
}

fn us_tool_contributions(
  active_tools: List(String),
) -> List(coverage.Contribution) {
  []
  |> append_when(
    has_any(active_tools, ["finance_capabilities", "finance_provider_health"]),
    contribution(finance_track.Us, "us_source_registry", "finance_setup", [
      "source_registry",
    ]),
  )
  |> append_when(
    has_any(active_tools, ["sec_company_search", "security_resolve"]),
    contribution(finance_track.Us, "us_security_identity", "SEC_and_OpenFIGI", [
      "security_identity",
    ]),
  )
  |> append_when(
    list.contains(active_tools, "sec_company_submissions"),
    contribution(finance_track.Us, "us_disclosure_discovery", "SEC", [
      "disclosure_discovery",
    ]),
  )
  |> append_when(
    list.contains(active_tools, "sec_xbrl_facts"),
    contribution(finance_track.Us, "us_raw_fundamentals", "SEC", [
      "raw_fundamentals",
    ]),
  )
  |> append_when(
    list.contains(active_tools, "stock_fundamental"),
    contribution(finance_track.Us, "us_normalized_fundamentals", "SEC", [
      "normalized_fundamentals",
    ]),
  )
  |> append_when(
    has_any(active_tools, [
      "stock_fundamental_q4",
      "stock_fundamental_trend",
      "stock_fundamental_growth",
      "stock_fundamental_ttm",
      "stock_fundamental_metric",
    ]),
    contribution(finance_track.Us, "us_reproducible_derivations", "SEC", [
      "reproducible_derivations",
    ]),
  )
}

fn cn_criteria() -> List(credibility.Criterion) {
  [
    criterion(
      "official_origin",
      credibility.Critical,
      credibility.Verified,
      "CSRC and exchange/repository ownership is registered",
    ),
    criterion(
      "exact_market_identity",
      credibility.Critical,
      credibility.Partial,
      "exact CNINFO artifact identity is supported but repository bytes alone do not prove SSE, SZSE, or BSE origin",
    ),
    criterion(
      "immutable_raw_evidence",
      credibility.Critical,
      credibility.Verified,
      "authority text and exact PDF bytes retain SHA-256 receipts",
    ),
    criterion(
      "bounded_retrieval",
      credibility.Standard,
      credibility.Verified,
      "allowlists, byte/page/time limits, pacing, retry, pooling, and cancellation are implemented",
    ),
    criterion(
      "freshness_receipt",
      credibility.Critical,
      credibility.Partial,
      "retrieval time is retained but semantic publication time is not decoded for every artifact",
    ),
    criterion(
      "semantic_decoder",
      credibility.Critical,
      credibility.Partial,
      "fixture-tested CNINFO discovery and a narrow Eastmoney vendor accounting decoder are implemented; official document text and filing-linked normalized accounting remain gaps",
    ),
    criterion(
      "fixture_schema_validation",
      credibility.Standard,
      credibility.Partial,
      "transport and structural fixtures exist but accepted real semantic fixtures do not",
    ),
    criterion(
      "entitlement_and_licence",
      credibility.Critical,
      credibility.Partial,
      "read-only local analysis is recorded while redistribution and production products remain unapproved",
    ),
    criterion(
      "independent_conflict_check",
      credibility.Standard,
      credibility.Missing,
      "no accepted independent source pair yet resolves or preserves production conflicts",
    ),
    criterion(
      "track_isolation",
      credibility.Critical,
      credibility.Verified,
      "CN sources and tools cannot borrow HK or US readiness",
    ),
  ]
}

fn hk_criteria() -> List(credibility.Criterion) {
  [
    criterion(
      "official_origin",
      credibility.Critical,
      credibility.Verified,
      "SFC, SEHK, HKEX, and HKEXnews ownership is registered",
    ),
    criterion(
      "exact_market_identity",
      credibility.Critical,
      credibility.Verified,
      "exact HKEXnews artifact identity and path/date relationship are validated",
    ),
    criterion(
      "immutable_raw_evidence",
      credibility.Critical,
      credibility.Verified,
      "SFC text and exact HKEXnews PDF bytes retain SHA-256 receipts",
    ),
    criterion(
      "bounded_retrieval",
      credibility.Standard,
      credibility.Verified,
      "allowlists, byte/page/time limits, pacing, retry, pooling, and cancellation are implemented",
    ),
    criterion(
      "freshness_receipt",
      credibility.Critical,
      credibility.Partial,
      "retrieval time is retained but semantic publication time is not decoded for every artifact",
    ),
    criterion(
      "semantic_decoder",
      credibility.Critical,
      credibility.Partial,
      "fixture-tested HKEXnews discovery and a narrow Eastmoney vendor accounting decoder are implemented; official document text and filing-linked normalized accounting remain gaps",
    ),
    criterion(
      "fixture_schema_validation",
      credibility.Standard,
      credibility.Partial,
      "transport and structural fixtures exist but accepted real semantic fixtures do not",
    ),
    criterion(
      "entitlement_and_licence",
      credibility.Critical,
      credibility.Partial,
      "read-only local analysis is recorded while redistribution and production IIS/data products require contracts",
    ),
    criterion(
      "independent_conflict_check",
      credibility.Standard,
      credibility.Missing,
      "no accepted independent source pair yet resolves or preserves production conflicts",
    ),
    criterion(
      "track_isolation",
      credibility.Critical,
      credibility.Verified,
      "HK sources and tools cannot borrow CN or US readiness",
    ),
  ]
}

fn us_criteria() -> List(credibility.Criterion) {
  [
    criterion(
      "official_origin",
      credibility.Critical,
      credibility.Verified,
      "SEC EDGAR and XBRL are official regulator sources",
    ),
    criterion(
      "exact_market_identity",
      credibility.Critical,
      credibility.Verified,
      "CIK, accession, taxonomy, tag, unit, and filing contexts are validated",
    ),
    criterion(
      "immutable_raw_evidence",
      credibility.Critical,
      credibility.Partial,
      "exact source numeric tokens and contexts are retained but every provider payload is not content-hash addressed",
    ),
    criterion(
      "bounded_retrieval",
      credibility.Standard,
      credibility.Verified,
      "SEC requests have caller identity, allowlists, pagination and response budgets, pacing, retry, and cancellation",
    ),
    criterion(
      "freshness_receipt",
      credibility.Critical,
      credibility.Verified,
      "filed, period, and retrieval contexts are retained",
    ),
    criterion(
      "semantic_decoder",
      credibility.Critical,
      credibility.Verified,
      "submission and company-facts decoders preserve exact source semantics",
    ),
    criterion(
      "fixture_schema_validation",
      credibility.Standard,
      credibility.Verified,
      "provider fixtures cover decoding, resolution, ambiguity, and derivation laws",
    ),
    criterion(
      "entitlement_and_licence",
      credibility.Critical,
      credibility.Partial,
      "public read access is supported while downstream redistribution remains result-specific",
    ),
    criterion(
      "independent_conflict_check",
      credibility.Standard,
      credibility.Missing,
      "the implemented fundamentals path is SEC-primary and has no independent production corroborator",
    ),
    criterion(
      "track_isolation",
      credibility.Critical,
      credibility.Verified,
      "SEC results are explicitly US and cannot satisfy CN or HK readiness",
    ),
  ]
}

fn feature(
  id: String,
  importance: coverage.Importance,
) -> coverage.Requirement {
  let assert Ok(value) = coverage.requirement(id, importance)
  value
}

fn contribution(
  track: Track,
  channel_id: String,
  source_group: String,
  covered: List(String),
) -> coverage.Contribution {
  let assert Ok(value) =
    coverage.contribution(track, channel_id, source_group, covered)
  value
}

fn criterion(
  id: String,
  importance: credibility.Importance,
  level: credibility.Level,
  evidence: String,
) -> credibility.Criterion {
  let assert Ok(value) = credibility.criterion(id, importance, level, evidence)
  value
}

fn has_any(active_tools: List(String), expected: List(String)) -> Bool {
  expected |> list.any(fn(name) { list.contains(active_tools, name) })
}

fn has_all(active_tools: List(String), expected: List(String)) -> Bool {
  expected |> list.all(fn(name) { list.contains(active_tools, name) })
}

fn append_when(
  values: List(value),
  condition: Bool,
  value: value,
) -> List(value) {
  case condition {
    True -> list.append(values, [value])
    False -> values
  }
}
