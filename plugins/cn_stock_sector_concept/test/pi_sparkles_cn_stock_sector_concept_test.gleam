import finance_capco
import finance_capco/classification
import finance_capco/pdf_text
import finance_capco/response
import finance_core/time
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_cn_stock_sector_concept/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn plan_requires_exact_track_period_and_six_digit_code_test() {
  domain.plan("cn", "2025-H2", "000001") |> should.be_ok
  domain.plan("hk", "2025-H2", "000001")
  |> should.equal(Error(domain.WrongTrack("hk")))
  domain.plan("cn", "latest", "000001")
  |> should.equal(Error(domain.UnsupportedResultPeriod("latest")))
  domain.plan("cn", "2025-H2", "00001A")
  |> should.equal(Error(domain.InvalidListingCode))
}

pub fn output_keeps_all_session_20_dates_and_unknowns_test() {
  let assert Ok(plan) = domain.plan("cn", "2025-H2", "000001")
  let capture =
    capture([
      item(44.72, "000001"),
      item(79.01, "平安银行"),
      item(132.51, "J"),
      item(192.62, "金融业"),
      item(423.09, "66"),
      item(478.32, "货币金融服务"),
    ])
  let assert Ok(output) = domain.assemble(plan, capture)
  let encoded = json.to_string(output.details)
  string.contains(encoded, "\"taxonomyEffective\"") |> should.be_true
  string.contains(encoded, "\"2023-05-01\"") |> should.be_true
  string.contains(encoded, "\"resultPeriod\"") |> should.be_true
  string.contains(encoded, "\"2025-H2\"") |> should.be_true
  string.contains(encoded, "\"publishedOn\"") |> should.be_true
  string.contains(encoded, "\"2026-04-03\"") |> should.be_true
  string.contains(encoded, "\"retrievedAtUnixMs\"") |> should.be_true
  string.contains(encoded, "\"membershipValidity\"") |> should.be_true
  string.contains(encoded, "\"state\":\"unknown\"") |> should.be_true
  string.contains(encoded, "\"mic\"") |> should.be_true
  string.contains(encoded, "\"no_redistribution\"") |> should.be_true
  string.contains(encoded, "\"pluginDecisionFields\":[]") |> should.be_true
}

pub fn output_preserves_manufacturing_subclass_and_no_middle_class_test() {
  let assert Ok(plan) = domain.plan("cn", "2025-H2", "000008")
  let capture =
    capture([
      item(44.72, "000008"),
      item(79.01, "神州高铁"),
      item(130.98, "C"),
      item(192.62, "制造业"),
      item(269.91, "CG"),
      item(303.26, "专用、通用及交通运输设备"),
      item(423.09, "37"),
      item(450.32, "铁路、船舶、航空航天和其他"),
      item(474.32, "运输设备制造业"),
    ])
  let assert Ok(output) = domain.assemble(plan, capture)
  let encoded = json.to_string(output.details)
  string.contains(encoded, "\"次类\":{\"code\":\"CG\"")
  |> should.be_true
  string.contains(encoded, "\"中类\":null") |> should.be_true
  string.contains(
    output.summary,
    "Membership effective dates and MIC are not published",
  )
  |> should.be_true
}

pub fn missing_code_is_an_exact_snapshot_error_test() {
  let assert Ok(plan) = domain.plan("cn", "2025-H2", "000002")
  domain.assemble(
    plan,
    capture([
      item(44.72, "000001"),
      item(79.01, "平安银行"),
      item(132.51, "J"),
      item(192.62, "金融业"),
      item(423.09, "66"),
      item(478.32, "货币金融服务"),
    ]),
  )
  |> should.equal(
    Error(domain.ClassificationRejected(classification.ListingCodeNotFound)),
  )
}

pub fn capture_period_or_hash_drift_cannot_be_joined_test() {
  let assert Ok(plan) = domain.plan("cn", "2025-H2", "000001")
  let original = capture([])
  let wrong_snapshot =
    finance_capco.Snapshot(
      ..original.snapshot,
      expected_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
  domain.assemble(plan, response.Capture(..original, snapshot: wrong_snapshot))
  |> should.equal(Error(domain.CapturePeriodMismatch))
}

fn capture(items: List(pdf_text.TextItem)) -> response.Capture {
  let assert Ok(snapshot) = finance_capco.select("2025-H2")
  let assert Ok(retrieved_at) = time.instant(1_775_200_000_000)
  response.Capture(
    snapshot: snapshot,
    extraction: pdf_text.Extraction(
      158,
      772_144,
      "pdfjs-dist",
      "6.2.108",
      items,
    ),
    retrieved_at: retrieved_at,
    source_reference: snapshot.pdf_origin <> snapshot.pdf_path,
    evidence_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    source_fingerprint: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    media_type: "application/pdf",
    response_byte_length: 772_144,
    content_sha256: snapshot.expected_sha256,
  )
}

fn item(x: Float, text: String) -> pdf_text.TextItem {
  pdf_text.TextItem(1, x, text)
}
