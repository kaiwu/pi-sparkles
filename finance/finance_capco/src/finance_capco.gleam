pub type Snapshot {
  Snapshot(
    result_period: String,
    taxonomy: String,
    taxonomy_effective: String,
    reference_standard: String,
    published_on: String,
    result_page_url: String,
    legal_statement_url: String,
    pdf_origin: String,
    pdf_path: String,
    expected_byte_length: Int,
    expected_sha256: String,
  )
}

pub type SelectionError {
  UnsupportedResultPeriod(received: String)
}

/// Select one reviewed immutable CAPCO result. No latest/fallback choice is
/// made inside the adapter.
pub fn select(result_period: String) -> Result(Snapshot, SelectionError) {
  case result_period {
    "2025-H2" ->
      Ok(Snapshot(
        result_period: "2025-H2",
        taxonomy: "CAPCO Listed Company Industry Statistical Classification Guideline",
        taxonomy_effective: "2023-05-01",
        reference_standard: "GB/T 4754-2017",
        published_on: "2026-04-03",
        result_page_url: "https://www.capco.org.cn/xhgg/hyfl/hyfljg/202604/20260403/j_2026040315001700017751997384265508.html",
        legal_statement_url: "https://www.capco.org.cn/flsm/index.html",
        pdf_origin: "https://sp.capco.org.cn:82",
        pdf_path: "/file/202604/hangyefenlei/2025xiaban/2025xiabangupiaodaima.pdf",
        expected_byte_length: 772_144,
        expected_sha256: "b1d0140572b20de11cd62ca478edb4da6e229928b216116df6345b3c2e461f58",
      ))
    value -> Error(UnsupportedResultPeriod(value))
  }
}
