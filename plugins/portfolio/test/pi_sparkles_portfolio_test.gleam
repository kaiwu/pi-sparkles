import finance_core/time
import finance_provenance/identity
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_portfolio/domain
import pi_sparkles_portfolio/raw

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn coherent_json_preserves_exact_facts_and_reconciles_without_verdict_test() {
  let assert Ok(snapshot) =
    decode(
      json_document([
        position(
          "P1",
          "us",
          "CommonStock",
          "Long",
          "10",
          "125.00",
          "1250.00",
          "USD",
          "row-1",
          "\"cost_basis_total\":\"1000\",\"unrealized_pnl\":\"250\",\"tax_id\":\"secret-tax\"",
        ),
      ]),
    )
  let summary = snapshot |> domain.summary("portfolio_import") |> json.to_string
  summary |> string.contains("\"state\":\"calculated\"") |> should.be_true
  summary |> string.contains("\"delta\":\"0\"") |> should.be_true
  summary |> string.contains("\"withinTolerance\":true") |> should.be_true
  summary |> string.contains("correctnessVerdict\":null") |> should.be_true
  summary |> string.contains("broker_authentication") |> should.be_true
  summary
  |> string.contains("account_visibility_not_review_visible")
  |> should.be_true

  let assert Ok(page) =
    domain.positions_page(snapshot, 0, 10, domain.empty_filter())
  let page = json.to_string(page)
  page |> string.contains("\"marketValueReconciliation\"") |> should.be_true
  page |> string.contains("source_unrealized_pnl") |> should.be_true
  page |> string.contains("secret-tax") |> should.be_false
  page
  |> string.contains("\"tax_id\":{\"state\":\"redacted\"}")
  |> should.be_true
}

pub fn multi_currency_legs_remain_separate_and_block_base_reconciliation_test() {
  let assert Ok(snapshot) =
    decode(
      json_document([
        position(
          "P1",
          "cn",
          "CommonStock",
          "Long",
          "10",
          "10",
          "100",
          "USD",
          "row-1",
          "",
        ),
        position(
          "P2",
          "hk",
          "CommonStock",
          "Long",
          "20",
          "20",
          "400",
          "HKD",
          "row-2",
          "",
        ),
      ]),
    )
  let text = snapshot |> domain.summary("portfolio_import") |> json.to_string
  text |> string.contains("\"currency\":\"HKD\"") |> should.be_true
  text |> string.contains("\"currency\":\"USD\"") |> should.be_true
  text
  |> string.contains("foreign_currency_legs_not_aggregated")
  |> should.be_true
  text |> string.contains("FX conversion") |> should.be_true
}

pub fn malformed_unsupported_and_unknown_rows_are_retained_test() {
  let malformed =
    position(
      "P1",
      "us",
      "Option",
      "Long",
      "N/A",
      "5",
      "",
      "USD",
      "row-1",
      "\"broker_custom\":{\"nested\":true}",
    )
  let assert Ok(snapshot) = decode(json_document([malformed]))
  let summary = snapshot |> domain.summary("portfolio_import") |> json.to_string
  summary |> string.contains("\"unsupported\":1") |> should.be_true
  summary |> string.contains("\"retainedRows\":1") |> should.be_true
  let assert Ok(page) =
    domain.positions_page(snapshot, 0, 10, domain.empty_filter())
  let text = json.to_string(page)
  text |> string.contains("derivative_not_yet_supported") |> should.be_true
  text |> string.contains("\"state\":\"unavailable\"") |> should.be_true
  text |> string.contains("broker_custom") |> should.be_true
  text |> string.contains("silently") |> should.be_false
}

pub fn exact_duplicates_collapse_but_conflicting_ids_all_remain_test() {
  let first =
    position(
      "P1",
      "us",
      "CommonStock",
      "Long",
      "10",
      "5",
      "50",
      "USD",
      "row-1",
      "",
    )
  let conflict =
    string.replace(first, "\"quantity\":\"10\"", "\"quantity\":\"11\"")
  let assert Ok(duplicates) = decode(json_document([first, first]))
  let duplicate_summary =
    duplicates |> domain.summary("portfolio_import") |> json.to_string
  duplicate_summary
  |> string.contains("\"duplicatesCollapsed\":1")
  |> should.be_true
  duplicate_summary |> string.contains("\"retainedRows\":1") |> should.be_true

  let assert Ok(conflicts) = decode(json_document([first, conflict]))
  let conflict_summary =
    conflicts |> domain.summary("portfolio_import") |> json.to_string
  conflict_summary |> string.contains("\"conflicts\":2") |> should.be_true
  let assert Ok(page) =
    domain.positions_page(conflicts, 0, 10, domain.empty_filter())
  json.to_string(page)
  |> string.contains("\"conflictingPositionId\":true")
  |> should.be_true
}

pub fn csv_quotes_unknown_columns_formula_and_row_budget_are_explicit_test() {
  let header =
    "snapshot_id,source_kind,base_currency,source_as_of,entitlement,position_id,track,listing_id,source_symbol,security_type,direction,quantity,quantity_unit,current_mark,mark_time,market_value,position_currency,source_row_id,note,avg_cost\n"
  let first =
    "snap-csv,ImportedFile,USD,Unknown(source),caller_private,P1,us,L1,AAPL,CommonStock,Long,10,shares,5,2026-08-08T00:00:00Z,50,USD,row-1,\"exact, note\",=A1\n"
  let second =
    "snap-csv,ImportedFile,USD,Unknown(source),caller_private,P2,us,L2,MSFT,CommonStock,Long,2,shares,10,2026-08-08T00:00:00Z,20,USD,row-2,other,9\n"
  let assert Ok(plan) = plan(1)
  let assert Ok(digest) = identity.sha256(string.repeat("b", 64))
  let assert Ok(snapshot) =
    domain.decode_document(
      plan,
      header <> first <> second,
      string.length(header <> first <> second),
      string.length(header <> first <> second),
      False,
      digest,
      now(),
    )
  let summary = snapshot |> domain.summary("portfolio_import") |> json.to_string
  summary |> string.contains("truncated_by_row_budget") |> should.be_true
  summary |> string.contains("\"formulaCells\":1") |> should.be_true
  let assert Ok(page) =
    domain.positions_page(snapshot, 0, 10, domain.empty_filter())
  let page = json.to_string(page)
  page |> string.contains("exact, note") |> should.be_true
  page |> string.contains("formula_text_not_evaluated") |> should.be_true
}

pub fn csv_controls_and_json_depth_or_byte_truncation_fail_closed_test() {
  let budgets = raw.Budgets(10, 100, 4096, 4, 100)
  raw.decode_csv(
    "snapshot_id,source_kind,base_currency,source_as_of,entitlement\ns,ImportedFile,USD,Unknown,e\u{0001}\n",
    raw.Comma,
    budgets,
    None,
  )
  |> should.equal(Error(raw.ControlCharacter))

  case
    raw.decode_json(
      "{\"snapshot\":{},\"positions\":[],\"nested\":{\"a\":{\"b\":{\"c\":1}}}}",
      raw.Budgets(10, 100, 4096, 3, 100),
      False,
    )
  {
    Error(raw.JsonTooDeep(_, _)) -> Nil
    _ -> should.fail()
  }
  raw.decode_json(json_document([]), budgets, True)
  |> should.equal(Error(raw.JsonByteTruncation))
}

pub fn session_store_is_idempotent_and_never_overwrites_a_snapshot_id_test() {
  let assert Ok(first) = decode(json_document([]))
  let state = domain.new_state()
  let assert Ok(domain.Stored(state, _)) = domain.store_snapshot(state, first)
  let assert Ok(domain.Existing(_, _)) = domain.store_snapshot(state, first)

  let assert Ok(other_digest) = identity.sha256(string.repeat("c", 64))
  let other = domain.Snapshot(..first, source_file_sha256: other_digest)
  domain.store_snapshot(state, other)
  |> should.equal(Error(domain.SnapshotIdConflict("snap-json")))
}

pub fn position_filters_and_paging_use_exact_retained_facts_test() {
  let assert Ok(snapshot) =
    decode(
      json_document([
        position(
          "P1",
          "us",
          "CommonStock",
          "Long",
          "1",
          "1",
          "1",
          "USD",
          "r1",
          "",
        ),
        position("P2", "hk", "Option", "Long", "1", "1", "1", "HKD", "r2", ""),
      ]),
    )
  let filter =
    domain.PositionFilter(
      None,
      None,
      Some("hk"),
      None,
      None,
      None,
      Some(True),
      None,
      None,
    )
  let assert Ok(page) = domain.positions_page(snapshot, 0, 1, filter)
  let text = json.to_string(page)
  text |> string.contains("\"matchedCount\":1") |> should.be_true
  text |> string.contains("\"value\":\"hk\"") |> should.be_true
  text |> string.contains("\"nextCursor\":null") |> should.be_true
}

fn decode(source: String) -> Result(domain.Snapshot, domain.ImportError) {
  let assert Ok(plan) = plan(100)
  let assert Ok(digest) = identity.sha256(string.repeat("a", 64))
  domain.decode_document(
    plan,
    source,
    string.length(source),
    string.length(source),
    False,
    digest,
    now(),
  )
}

fn plan(maximum_rows: Int) -> Result(domain.ImportPlan, domain.ImportError) {
  domain.import_plan(
    "/caller/portfolio.json",
    case maximum_rows {
      1 -> "csv"
      _ -> "json"
    },
    "comma",
    "plain_dot",
    1_000_000,
    maximum_rows,
    100,
    4096,
    10,
    10_000,
    "0.01",
    "redacted",
  )
}

fn now() -> time.Instant {
  let assert Ok(value) = time.instant(1_786_000_000_000)
  value
}

fn json_document(positions: List(String)) -> String {
  "{\"snapshot\":{\"snapshot_id\":\"snap-json\",\"source_kind\":\"ImportedFile\",\"account_id\":\"private-account\",\"base_currency\":\"USD\",\"source_as_of\":\"2026-08-08T20:00:00Z\",\"entitlement\":\"caller_private_local_use\",\"source_declared_total\":\"1250.00\",\"source_total_currency\":\"USD\"},\"positions\":["
  <> string.join(positions, with: ",")
  <> "]}"
}

fn position(
  id: String,
  track: String,
  security_type: String,
  direction: String,
  quantity: String,
  mark: String,
  market_value: String,
  currency: String,
  source_row_id: String,
  extras: String,
) -> String {
  "{\"position_id\":\""
  <> id
  <> "\",\"track\":\""
  <> track
  <> "\",\"listing_id\":\"listing-"
  <> id
  <> "\",\"mic\":\"XNAS\",\"source_symbol\":\"SYM\",\"security_type\":\""
  <> security_type
  <> "\",\"direction\":\""
  <> direction
  <> "\",\"quantity\":\""
  <> quantity
  <> "\",\"quantity_unit\":\"shares\",\"current_mark\":\""
  <> mark
  <> "\",\"mark_time\":\"2026-08-08T20:00:00Z\",\"market_value\":\""
  <> market_value
  <> "\",\"position_currency\":\""
  <> currency
  <> "\",\"source_row_id\":\""
  <> source_row_id
  <> "\""
  <> case extras {
    "" -> ""
    _ -> "," <> extras
  }
  <> "}"
}
