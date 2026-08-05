import finance_calendar/calendar
import finance_cn_accounting/fact as cn_fact
import finance_cn_calendar/dataset as cn_calendar
import finance_cn_documents/document as cn_document
import finance_cn_identity/identity
import finance_cn_rules/rule as cn_rule
import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/instrument
import finance_core/market
import finance_core/source
import finance_core/time
import finance_listing/effective
import finance_market_accounting/fact as market_fact
import finance_market_calendar/dataset as market_calendar
import finance_market_documents/document as market_document
import finance_market_rules/rule as market_rule
import finance_provenance/evidence
import finance_provenance/identity as provenance_identity
import finance_testkit/seed.{type Seed}
import gleam/int
import gleam/option.{None, Some}
import gleam/string

pub const algorithm_version = 1

pub const provider = "SYNTHETIC_CN_TEST_DATA"

pub type Case {
  SseMainBoard
  StarMarket
  ChiNextSpecialTreatment
  Suspended
  BShareCurrency
  CorrectedAnnualReport
}

pub type Scenario {
  Scenario(
    kind: Case,
    listing: identity.Listing,
    calendar: market_calendar.Dataset,
    rules: List(cn_rule.Rule),
    documents: List(cn_document.Document),
    relations: List(market_document.Relation),
    facts: List(cn_fact.Fact),
  )
}

pub fn all_cases() -> List(Case) {
  [
    SseMainBoard,
    StarMarket,
    ChiNextSpecialTreatment,
    Suspended,
    BShareCurrency,
    CorrectedAnnualReport,
  ]
}

/// Select a scenario deterministically from an explicit seed.
pub fn generate(initial: Seed) -> #(Seed, Scenario) {
  let assert Ok(#(next, selected)) = seed.between(initial, 0, 5)
  #(next, for_case(case_from_int(selected), next))
}

/// Build an exact market-owned case while still using the seed for stable
/// issuer and document identity. All data is synthetic and test-only.
pub fn for_case(kind value: Case, seed seed_value: Seed) -> Scenario {
  let listing = listing_for(value, seed_value)
  let source = source_ref(value)
  let evidence_id = evidence_id(value)
  let calendar = calendar_for(listing, source)
  let rules = [rule_for(value, listing, source, evidence_id)]
  let #(documents, relations, active_document) =
    documents_for(value, listing, source, evidence_id, seed_value)
  let facts = facts_for(value, listing, active_document)
  Scenario(value, listing, calendar, rules, documents, relations, facts)
}

fn listing_for(value: Case, seed_value: Seed) -> identity.Listing {
  let #(code, venue, board, share_class, currency_code) = case value {
    SseMainBoard -> #(
      "600001",
      identity.Sse,
      identity.SseMainBoard,
      identity.AShare,
      "CNY",
    )
    StarMarket -> #(
      "688001",
      identity.Sse,
      identity.StarMarket,
      identity.AShare,
      "CNY",
    )
    ChiNextSpecialTreatment -> #(
      "300001",
      identity.Szse,
      identity.ChiNext,
      identity.AShare,
      "CNY",
    )
    Suspended -> #(
      "000002",
      identity.Szse,
      identity.SzseMainBoard,
      identity.AShare,
      "CNY",
    )
    BShareCurrency -> #(
      "900901",
      identity.Sse,
      identity.SseMainBoard,
      identity.BShare,
      "USD",
    )
    CorrectedAnnualReport -> #(
      "000001",
      identity.Szse,
      identity.SzseMainBoard,
      identity.AShare,
      "CNY",
    )
  }
  let id =
    "synthetic-cn-"
    <> int.to_string(seed.value(seed_value))
    <> "-"
    <> case_name(value)
  let assert Ok(instrument_id) = identifier.instrument_id(id)
  let assert Ok(listing_currency) = currency.from_code(currency_code)
  let listing_status = case value {
    Suspended -> instrument.Suspended
    _ -> instrument.Active
  }
  let assert Ok(listing) =
    identity.new(
      instrument_id: instrument_id,
      code: code,
      venue: venue,
      board: board,
      share_class: share_class,
      currency: listing_currency,
      status: listing_status,
    )
  listing
}

fn calendar_for(
  listing: identity.Listing,
  source: source.SourceRef,
) -> market_calendar.Dataset {
  let sessions = [
    session("synthetic opening auction", 9, 15, 9, 25),
    session("synthetic morning", 9, 30, 11, 30),
    session("synthetic afternoon", 13, 0, 14, 57),
    session("synthetic closing auction", 14, 57, 15, 0),
  ]
  let assert Ok(value) =
    cn_calendar.new(
      venue: identity.venue(listing),
      version: "synthetic-cn-scenario-v1",
      coverage_start: civil(2024, 1, 1),
      coverage_end: civil(2024, 12, 31),
      source: source,
      licence: evidence.Licence(
        "synthetic-test-data",
        evidence.PublicDomain,
        None,
      ),
      entitlement: "synthetic_test_only",
      limitations: ["not_authoritative", "not_for_market_use"],
      weekly: cn_calendar.weekday_template(sessions),
      overrides: [#(civil(2024, 2, 12), calendar.Closed("synthetic closure"))],
    )
  value
}

fn rule_for(
  value: Case,
  listing: identity.Listing,
  source: source.SourceRef,
  evidence_id: provenance_identity.EvidenceId,
) -> cn_rule.Rule {
  let status = case value {
    ChiNextSpecialTreatment -> cn_rule.SpecialTreatment
    Suspended -> cn_rule.Suspended
    _ -> cn_rule.Normal
  }
  let price_limit = case value {
    Suspended -> market_rule.TradingProhibited
    _ -> market_rule.ProviderPublishedOnly
  }
  let lot = case value {
    StarMarket -> 200
    _ -> 100
  }
  let assert Ok(value) =
    cn_rule.new(
      listing: listing,
      effective: interval(),
      security_type: cn_rule.Equity,
      market_status: status,
      tick_size: exact("0.01"),
      buy_lot: lot,
      sell_lot: 1,
      price_limit: price_limit,
      settlement: market_rule.BusinessDays(1),
      eligibility: ["synthetic_test_only"],
      source: source,
      evidence_id: Some(evidence_id),
    )
  value
}

fn documents_for(
  value: Case,
  listing: identity.Listing,
  source: source.SourceRef,
  evidence_id: provenance_identity.EvidenceId,
  seed_value: Seed,
) -> #(
  List(cn_document.Document),
  List(market_document.Relation),
  cn_document.Document,
) {
  let suffix = int.to_string(seed.value(seed_value))
  let original =
    document(
      id: "cn-annual-" <> suffix,
      listing: listing,
      title: "2024年年度报告",
      text: "营业收入以万元列报；股本以万股列报。",
      published: 1_711_843_200_000,
      source: source,
      evidence_id: evidence_id,
    )
  case value {
    CorrectedAnnualReport -> {
      let corrected =
        document(
          id: "cn-annual-" <> suffix <> "-correction",
          listing: listing,
          title: "2024年年度报告（更正）",
          text: "更正后营业收入以万元列报；原公告已被更正。",
          published: 1_711_929_600_000,
          source: source,
          evidence_id: evidence_id,
        )
      let assert Ok(relation) =
        market_document.relation(
          market_document.Correction,
          cn_document.common(original),
          cn_document.common(corrected),
          evidence_id,
        )
      #([original, corrected], [relation], corrected)
    }
    _ -> #([original], [], original)
  }
}

fn document(
  id id_value: String,
  listing listing_value: identity.Listing,
  title title: String,
  text text: String,
  published published: Int,
  source source_ref: source.SourceRef,
  evidence_id evidence_id: provenance_identity.EvidenceId,
) -> cn_document.Document {
  let assert Ok(id) = market_document.document_id(id_value)
  let assert Ok(period) =
    market_document.period(Some(civil(2024, 1, 1)), civil(2024, 12, 31))
  let assert Ok(value) =
    cn_document.new(
      id: id,
      issuer: listing_value,
      kind: cn_document.PeriodicReport,
      original_title: title,
      original_text: Some(text),
      language: cn_document.SimplifiedChinese,
      published_at: instant(published),
      period: Some(period),
      source: source_ref,
      evidence_id: evidence_id,
    )
  value
}

fn facts_for(
  value: Case,
  listing: identity.Listing,
  document: cn_document.Document,
) -> List(cn_fact.Fact) {
  let state = case value {
    CorrectedAnnualReport -> market_fact.Corrected
    _ -> market_fact.Original
  }
  let assert Ok(cny) = currency.from_code("CNY")
  [
    accounting_fact(
      listing: listing,
      document: document,
      code: "revenue",
      label: "营业收入",
      raw: "9007199254740993.0100",
      reported_unit: "万元",
      normalized_unit: market.Currency(cny),
      restatement: state,
    ),
    accounting_fact(
      listing: listing,
      document: document,
      code: "share_capital",
      label: "股本",
      raw: "12345.00",
      reported_unit: "万股",
      normalized_unit: market.Shares,
      restatement: state,
    ),
  ]
}

fn accounting_fact(
  listing listing: identity.Listing,
  document document: cn_document.Document,
  code code: String,
  label label: String,
  raw raw: String,
  reported_unit reported_unit: String,
  normalized_unit normalized_unit: market.Unit,
  restatement restatement: market_fact.RestatementState,
) -> cn_fact.Fact {
  let assert Ok(value) = market_fact.numeric(raw)
  let assert Ok(scale) = market_fact.scale(reported_unit, exact("10000"))
  let assert Ok(value) =
    cn_fact.new(
      listing: listing,
      document: document,
      line_code: Some(code),
      original_label: label,
      value: value,
      reported_unit: reported_unit,
      scale: scale,
      normalized_unit: Some(normalized_unit),
      standard: cn_fact.ChineseAccountingStandards,
      statement_scope: market_fact.Consolidated,
      period: market_fact.Duration(civil(2024, 1, 1), civil(2024, 12, 31)),
      report_class: cn_fact.Annual,
      audit_state: market_fact.Audited,
      restatement_state: restatement,
    )
  value
}

fn source_ref(value: Case) -> source.SourceRef {
  let assert Ok(value) =
    source.new(provider, "fixture/cn/" <> case_name(value), source.Synthetic)
  value
}

fn evidence_id(value: Case) -> provenance_identity.EvidenceId {
  let character = case value {
    SseMainBoard -> "1"
    StarMarket -> "2"
    ChiNextSpecialTreatment -> "3"
    Suspended -> "4"
    BShareCurrency -> "5"
    CorrectedAnnualReport -> "6"
  }
  let assert Ok(hash) = provenance_identity.sha256(string.repeat(character, 64))
  provenance_identity.evidence_id(hash)
}

fn case_from_int(value: Int) -> Case {
  case value {
    0 -> SseMainBoard
    1 -> StarMarket
    2 -> ChiNextSpecialTreatment
    3 -> Suspended
    4 -> BShareCurrency
    _ -> CorrectedAnnualReport
  }
}

fn case_name(value: Case) -> String {
  case value {
    SseMainBoard -> "sse_main_board"
    StarMarket -> "star_market"
    ChiNextSpecialTreatment -> "chinext_special_treatment"
    Suspended -> "suspended"
    BShareCurrency -> "b_share_currency"
    CorrectedAnnualReport -> "corrected_annual_report"
  }
}

fn session(
  label: String,
  open_hour: Int,
  open_minute: Int,
  close_hour: Int,
  close_minute: Int,
) -> calendar.Session {
  let assert Ok(value) =
    calendar.session(
      label: label,
      opens_at: clock(open_hour, open_minute),
      closes_at: clock(close_hour, close_minute),
      close_day: calendar.SameDay,
    )
  value
}

fn interval() -> effective.Interval {
  let assert Ok(value) = effective.new(civil(2024, 1, 1), None)
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn clock(hour: Int, minute: Int) -> time.TimeOfDay {
  let assert Ok(value) = time.time_of_day(hour, minute)
  value
}

fn instant(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}

fn exact(value: String) -> decimal.Decimal {
  let assert Ok(value) = decimal.parse(value)
  value
}
