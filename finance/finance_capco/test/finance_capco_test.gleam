import finance_capco
import finance_capco/classification
import finance_capco/pdf_text
import finance_capco/request
import finance_capco/response as capco_response
import finance_core/time
import finance_http/binary_response
import finance_http/request as http_request
import finance_http/response as http_response
import finance_http/transport
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_snapshot_and_request_are_fixed_test() {
  let assert Ok(snapshot) = finance_capco.select("2025-H2")
  snapshot.taxonomy_effective |> should.equal("2023-05-01")
  snapshot.published_on |> should.equal("2026-04-03")
  snapshot.expected_byte_length |> should.equal(772_144)
  finance_capco.select("latest")
  |> should.equal(Error(finance_capco.UnsupportedResultPeriod("latest")))

  let assert Ok(request_value) = request.classification_pdf(snapshot)
  http_request.origin(request_value) |> should.equal(snapshot.pdf_origin)
  http_request.path(request_value) |> should.equal(snapshot.pdf_path)
  http_request.maximum_response_bytes(request_value) |> should.equal(1_000_000)
}

pub fn exact_non_manufacturing_row_preserves_wrapped_labels_test() {
  let extraction =
    fixture([
      item(1, 44.72, "000004"),
      item(1, 81.03, "*ST国华"),
      item(1, 132.49, "I"),
      item(1, 156.62, "信息传输、软件和信息技术"),
      item(1, 192.62, "服务业"),
      item(1, 423.09, "65"),
      item(1, 462.32, "软件和信息技术服务业"),
      item(1, 44.72, "000006"),
    ])
  classification.find(extraction, "000004")
  |> should.equal(
    Ok(classification.Classification(
      listing_code: "000004",
      listing_name: "*ST国华",
      section: classification.Level("I", "信息传输、软件和信息技术服务业"),
      manufacturing_subclass: None,
      division: classification.Level("65", "软件和信息技术服务业"),
    )),
  )
}

pub fn manufacturing_row_requires_and_preserves_subclass_test() {
  let extraction =
    fixture([
      item(1, 44.72, "000008"),
      item(1, 79.01, "神州高铁"),
      item(1, 130.98, "C"),
      item(1, 192.62, "制造业"),
      item(1, 269.91, "CG"),
      item(1, 303.26, "专用、通用及交通运输设备"),
      item(1, 423.09, "37"),
      item(1, 450.32, "铁路、船舶、航空航天和其他"),
      item(1, 474.32, "运输设备制造业"),
    ])
  classification.find(extraction, "000008")
  |> should.equal(
    Ok(classification.Classification(
      listing_code: "000008",
      listing_name: "神州高铁",
      section: classification.Level("C", "制造业"),
      manufacturing_subclass: Some(classification.Level("CG", "专用、通用及交通运输设备")),
      division: classification.Level("37", "铁路、船舶、航空航天和其他运输设备制造业"),
    )),
  )
}

pub fn missing_duplicate_and_malformed_rows_fail_closed_test() {
  let row = [
    item(1, 44.72, "000001"),
    item(1, 79.01, "平安银行"),
    item(1, 132.51, "J"),
    item(1, 192.62, "金融业"),
    item(1, 423.09, "66"),
    item(1, 478.32, "货币金融服务"),
  ]
  classification.find(fixture(row), "000002")
  |> should.equal(Error(classification.ListingCodeNotFound))
  classification.find(fixture(list.append(row, row)), "000001")
  |> should.equal(Error(classification.DuplicateListingCode))
  classification.find(
    fixture([
      item(1, 44.72, "000008"),
      item(1, 79.01, "神州高铁"),
      item(1, 130.98, "C"),
      item(1, 192.62, "制造业"),
      item(1, 423.09, "37"),
      item(1, 450.32, "运输设备制造业"),
    ]),
    "000008",
  )
  |> should.equal(Error(classification.MalformedRow("manufacturing_subclass")))
}

pub fn changed_official_pdf_is_rejected_before_text_extraction_test() {
  let assert Ok(snapshot) = finance_capco.select("2025-H2")
  let assert Ok(duration) = time.duration(1)
  let assert Ok(response_value) =
    binary_response.new(
      200,
      [http_response.Header("content-type", "application/pdf")],
      "JVBERi0=",
      5,
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "255044462d",
      duration,
    )
  let assert Ok(retrieved_at) = time.instant(1_775_200_000_000)
  use outcome <- promise.await(capco_response.capture(
    snapshot,
    response_value,
    retrieved_at,
    transport.new_cancellation(),
  ))
  outcome
  |> should.equal(Error(capco_response.UnexpectedByteLength(772_144, 5)))
  promise.resolve(Nil)
}

fn fixture(items: List(pdf_text.TextItem)) -> pdf_text.Extraction {
  pdf_text.Extraction(1, 1, "synthetic", "1", items)
}

fn item(page: Int, x: Float, text: String) -> pdf_text.TextItem {
  pdf_text.TextItem(page, x, text)
}
