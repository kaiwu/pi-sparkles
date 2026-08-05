import finance_calendar/calendar
import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/instrument
import finance_core/market
import finance_core/source
import finance_core/time
import finance_hk_accounting/fact as hk_fact
import finance_hk_calendar/dataset as hk_calendar
import finance_hk_documents/document as hk_document
import finance_hk_identity/identity
import finance_hk_rules/rule as hk_rule
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

pub const provider = "SYNTHETIC_HK_TEST_DATA"

pub type Case {
  MainBoard
  Gem
  DepositaryReceipt
  Suspended
  ParallelLanguageReport
  CorrectedResults
}

pub type Scenario {
  Scenario(
    kind: Case,
    listing: identity.Listing,
    calendar: market_calendar.Dataset,
    rules: List(hk_rule.Rule),
    documents: List(hk_document.Document),
    relations: List(market_document.Relation),
    facts: List(hk_fact.Fact),
  )
}

pub fn all_cases() -> List(Case) {
  [
    MainBoard,
    Gem,
    DepositaryReceipt,
    Suspended,
    ParallelLanguageReport,
    CorrectedResults,
  ]
}

pub fn generate(initial: Seed) -> #(Seed, Scenario) {
  let assert Ok(#(next, selected)) = seed.between(initial, 0, 5)
  #(next, for_case(case_from_int(selected), next))
}

pub fn for_case(kind value: Case, seed seed_value: Seed) -> Scenario {
  let listing = listing_for(value, seed_value)
  let source = source_ref(value)
  let evidence_id = evidence_id(value)
  let calendar = calendar_for(source)
  let rules = [rule_for(value, listing, source, evidence_id)]
  let #(documents, relations, active_document) =
    documents_for(value, listing, source, evidence_id, seed_value)
  let facts = [accounting_fact(value, listing, active_document)]
  Scenario(value, listing, calendar, rules, documents, relations, facts)
}

fn listing_for(value: Case, seed_value: Seed) -> identity.Listing {
  let #(code, board, share_class) = case value {
    MainBoard -> #("00001", identity.MainBoard, identity.OrdinaryShare)
    Gem -> #("08001", identity.Gem, identity.OrdinaryShare)
    DepositaryReceipt -> #(
      "09001",
      identity.MainBoard,
      identity.DepositaryReceipt,
    )
    Suspended -> #("00002", identity.MainBoard, identity.OrdinaryShare)
    ParallelLanguageReport -> #(
      "00003",
      identity.MainBoard,
      identity.OrdinaryShare,
    )
    CorrectedResults -> #("00004", identity.MainBoard, identity.OrdinaryShare)
  }
  let id =
    "synthetic-hk-"
    <> int.to_string(seed.value(seed_value))
    <> "-"
    <> case_name(value)
  let assert Ok(instrument_id) = identifier.instrument_id(id)
  let assert Ok(hkd) = currency.from_code("HKD")
  let listing_status = case value {
    Suspended -> instrument.Suspended
    _ -> instrument.Active
  }
  let assert Ok(listing) =
    identity.new(
      instrument_id: instrument_id,
      code: code,
      board: board,
      share_class: share_class,
      currency: hkd,
      status: listing_status,
    )
  listing
}

fn calendar_for(source: source.SourceRef) -> market_calendar.Dataset {
  let sessions = [
    session("synthetic opening auction", 9, 0, 9, 30),
    session("synthetic morning", 9, 30, 12, 0),
    session("synthetic afternoon", 13, 0, 16, 0),
  ]
  let assert Ok(value) =
    hk_calendar.new(
      version: "synthetic-hk-scenario-v1",
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
      weekly: hk_calendar.weekday_template(sessions),
      overrides: [#(civil(2024, 2, 12), calendar.Closed("synthetic closure"))],
    )
  value
}

fn rule_for(
  value: Case,
  listing: identity.Listing,
  source: source.SourceRef,
  evidence_id: provenance_identity.EvidenceId,
) -> hk_rule.Rule {
  let status = case value {
    Suspended -> hk_rule.Suspended
    _ -> hk_rule.Normal
  }
  let limit = case value {
    Suspended -> market_rule.TradingProhibited
    _ -> market_rule.ProviderPublishedOnly
  }
  let lot = case value {
    MainBoard | ParallelLanguageReport -> 500
    Gem -> 2000
    DepositaryReceipt -> 100
    CorrectedResults -> 1000
    Suspended -> 500
  }
  let assert Ok(value) =
    hk_rule.new(
      listing: listing,
      effective: interval(),
      security_type: case value {
        DepositaryReceipt -> hk_rule.DepositaryReceipt
        _ -> hk_rule.Equity
      },
      market_status: status,
      tick_size: exact("0.01"),
      buy_lot: lot,
      sell_lot: lot,
      price_limit: limit,
      settlement: market_rule.BusinessDays(2),
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
  List(hk_document.Document),
  List(market_document.Relation),
  hk_document.Document,
) {
  let suffix = int.to_string(seed.value(seed_value))
  let original =
    document(
      id: "hk-results-" <> suffix,
      listing: listing,
      title: "截至2024年12月31日止年度業績公告",
      text: "收益以港幣千元列報。",
      language: hk_document.TraditionalChinese,
      published: 1_711_843_200_000,
      source: source,
      evidence_id: evidence_id,
    )
  case value {
    ParallelLanguageReport -> {
      let english =
        document(
          id: "hk-results-" <> suffix <> "-en",
          listing: listing,
          title: "Annual results for the year ended 31 December 2024",
          text: "Revenue is reported in HKD thousands.",
          language: hk_document.English,
          published: 1_711_843_200_000,
          source: source,
          evidence_id: evidence_id,
        )
      let assert Ok(relation) =
        market_document.relation(
          market_document.ParallelLanguage,
          hk_document.common(original),
          hk_document.common(english),
          evidence_id,
        )
      #([original, english], [relation], original)
    }
    CorrectedResults -> {
      let corrected =
        document(
          id: "hk-results-" <> suffix <> "-correction",
          listing: listing,
          title: "年度業績公告（更正）",
          text: "更正後收益以港幣千元列報。",
          language: hk_document.TraditionalChinese,
          published: 1_711_929_600_000,
          source: source,
          evidence_id: evidence_id,
        )
      let assert Ok(relation) =
        market_document.relation(
          market_document.Correction,
          hk_document.common(original),
          hk_document.common(corrected),
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
  language language: hk_document.Language,
  published published: Int,
  source source_ref: source.SourceRef,
  evidence_id evidence_id: provenance_identity.EvidenceId,
) -> hk_document.Document {
  let assert Ok(id) = market_document.document_id(id_value)
  let assert Ok(period) =
    market_document.period(Some(civil(2024, 1, 1)), civil(2024, 12, 31))
  let assert Ok(value) =
    hk_document.new(
      id: id,
      issuer: listing_value,
      kind: hk_document.ResultsAnnouncement,
      original_title: title,
      original_text: Some(text),
      language: language,
      published_at: instant(published),
      period: Some(period),
      source: source_ref,
      evidence_id: evidence_id,
    )
  value
}

fn accounting_fact(
  value: Case,
  listing: identity.Listing,
  document: hk_document.Document,
) -> hk_fact.Fact {
  let assert Ok(reported) = market_fact.numeric("9007199254740993.0100")
  let assert Ok(scale) = market_fact.scale("港幣千元", exact("1000"))
  let assert Ok(hkd) = currency.from_code("HKD")
  let standard = case value {
    DepositaryReceipt -> hk_fact.InternationalFinancialReportingStandards
    _ -> hk_fact.HongKongFinancialReportingStandards
  }
  let restatement = case value {
    CorrectedResults -> market_fact.Corrected
    _ -> market_fact.Original
  }
  let assert Ok(value) =
    hk_fact.new(
      listing: listing,
      document: document,
      line_code: Some("revenue"),
      original_label: "收益",
      value: reported,
      reported_unit: "港幣千元",
      scale: scale,
      normalized_unit: Some(market.Currency(hkd)),
      standard: standard,
      statement_scope: market_fact.Consolidated,
      period: market_fact.Duration(civil(2024, 1, 1), civil(2024, 12, 31)),
      report_class: hk_fact.ResultsAnnouncement,
      audit_state: market_fact.Reviewed,
      restatement_state: restatement,
    )
  value
}

fn source_ref(value: Case) -> source.SourceRef {
  let assert Ok(value) =
    source.new(provider, "fixture/hk/" <> case_name(value), source.Synthetic)
  value
}

fn evidence_id(value: Case) -> provenance_identity.EvidenceId {
  let character = case value {
    MainBoard -> "7"
    Gem -> "8"
    DepositaryReceipt -> "9"
    Suspended -> "a"
    ParallelLanguageReport -> "b"
    CorrectedResults -> "c"
  }
  let assert Ok(hash) = provenance_identity.sha256(string.repeat(character, 64))
  provenance_identity.evidence_id(hash)
}

fn case_from_int(value: Int) -> Case {
  case value {
    0 -> MainBoard
    1 -> Gem
    2 -> DepositaryReceipt
    3 -> Suspended
    4 -> ParallelLanguageReport
    _ -> CorrectedResults
  }
}

fn case_name(value: Case) -> String {
  case value {
    MainBoard -> "main_board"
    Gem -> "gem"
    DepositaryReceipt -> "depositary_receipt"
    Suspended -> "suspended"
    ParallelLanguageReport -> "parallel_language_report"
    CorrectedResults -> "corrected_results"
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
