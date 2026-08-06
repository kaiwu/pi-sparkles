import finance_authority_snapshot
import finance_authority_snapshot/artifact
import finance_authority_snapshot/runtime
import finance_authority_snapshot/snapshot
import finance_core/source
import finance_core/time
import finance_http/binary_response
import finance_http/response
import finance_provenance/evidence
import finance_provenance/hash
import finance_provenance/identity
import finance_track
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_authority_snapshot.status()
  |> should.equal(finance_authority_snapshot.Experimental)
}

pub fn raw_authority_text_becomes_hashed_local_evidence_test() {
  let body = "<rss><channel><title>官方公告</title></channel></rss>"
  let assert Ok(source_ref) =
    source.new("SFC", "https://www.sfc.hk/feed", source.Regulator)
  let assert Ok(policy) =
    snapshot.local_analysis_policy(
      finance_track.Hk,
      "hk_sfc",
      source_ref,
      ["application/xml"],
      10_000,
    )
  let assert Ok(duration) = time.duration(5)
  let assert Ok(response_value) =
    response.new(
      200,
      [response.Header("Content-Type", "application/xml; charset=utf-8")],
      body,
      string.byte_size(body),
      duration,
    )
  let retrieved = instant(2000)
  let assert Ok(value) =
    snapshot.capture(policy, response_value, retrieved, retrieved)

  snapshot.track(value) |> should.equal(finance_track.Hk)
  snapshot.authority_id(value) |> should.equal("hk_sfc")
  snapshot.body(value) |> should.equal(body)
  let evidence.Evidence(
    _,
    _,
    _,
    licence,
    _,
    _,
    media_type,
    byte_length,
    content_hash,
    _,
    _,
    _,
  ) = snapshot.evidence(value)
  licence
  |> should.equal(evidence.Licence(
    "official-public-local-analysis-only",
    evidence.NoRedistribution,
    Some(
      "Public read access does not grant bulk redistribution; retain the official source link and attribution.",
    ),
  ))
  byte_length |> should.equal(string.byte_size(body))
  media_type |> should.equal("application/xml")
  content_hash |> should.not_equal(hash_of("x"))
}

pub fn capture_rejects_non_authority_wrong_media_and_length_test() {
  let assert Ok(vendor) =
    source.new("vendor", "https://example.test", source.LicensedVendor)
  snapshot.local_analysis_policy(
    finance_track.Cn,
    "cn_csrc",
    vendor,
    ["text/html"],
    1000,
  )
  |> should.equal(Error(snapshot.NonAuthoritySource))

  let assert Ok(regulator) =
    source.new("CSRC", "https://www.csrc.gov.cn/list", source.Regulator)
  let assert Ok(policy) =
    snapshot.local_analysis_policy(
      finance_track.Cn,
      "cn_csrc",
      regulator,
      ["text/html"],
      1000,
    )
  let html = "<html>公告</html>"
  let json_response = response_value("application/json", html, 1)

  snapshot.capture(policy, json_response, instant(1), instant(1))
  |> should.equal(Error(snapshot.UnsupportedMediaType("application/json")))

  let wrong_length = response_value("text/html", html, 1)
  snapshot.capture(policy, wrong_length, instant(1), instant(1))
  |> should.equal(Error(snapshot.ByteLengthMismatch(1, string.byte_size(html))))
}

pub fn binary_pdf_becomes_byte_preserving_hashed_evidence_test() {
  let assert Ok(source_ref) =
    source.new(
      "HKEXnews",
      "https://www1.hkexnews.hk/listedco/example.pdf",
      source.Exchange,
    )
  let assert Ok(policy) =
    artifact.local_analysis_policy(
      finance_track.Hk,
      "hk_hkexnews",
      source_ref,
      "direct",
      ["application/pdf"],
      10_000,
      artifact.Pdf,
    )
  let assert Ok(response_value) =
    binary_response.new(
      200,
      [response.Header("Content-Type", "application/pdf")],
      "JVBERi0=",
      5,
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "255044462d",
      duration(5),
    )
  let retrieved = instant(2000)
  let assert Ok(value) =
    artifact.capture(policy, response_value, retrieved, retrieved)

  artifact.track(value) |> should.equal(finance_track.Hk)
  artifact.authority_id(value) |> should.equal("hk_hkexnews")
  artifact.retrieval_route(value) |> should.equal("direct")
  artifact.body_base64(value) |> should.equal("JVBERi0=")
  let evidence.Evidence(_, _, _, licence, _, _, media_type, bytes, _, _, _, _) =
    artifact.evidence(value)
  media_type |> should.equal("application/pdf")
  bytes |> should.equal(5)
  licence.redistribution |> should.equal(evidence.NoRedistribution)
}

pub fn binary_pdf_capture_rejects_signature_mismatch_test() {
  let assert Ok(source_ref) =
    source.new("CNINFO", "https://static.cninfo.com.cn/a.pdf", source.Official)
  let assert Ok(policy) =
    artifact.local_analysis_policy(
      finance_track.Cn,
      "cn_cninfo",
      source_ref,
      "CNINFO",
      ["application/pdf"],
      10_000,
      artifact.Pdf,
    )
  let assert Ok(response_value) =
    binary_response.new(
      200,
      [response.Header("Content-Type", "application/pdf")],
      "aGVsbG8=",
      5,
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "68656c6c6f",
      duration(5),
    )

  artifact.capture(policy, response_value, instant(1), instant(1))
  |> should.equal(Error(artifact.SignatureMismatch(artifact.Pdf)))
}

pub fn binary_zip_becomes_byte_preserving_hashed_evidence_test() {
  let assert Ok(source_ref) =
    source.new(
      "HKEX",
      "https://www.hkex.com.hk/ListOfSecurities.xlsx",
      source.Exchange,
    )
  let assert Ok(policy) =
    artifact.local_analysis_policy(
      finance_track.Hk,
      "hk_hkex_securities",
      source_ref,
      "direct:HKEX",
      ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"],
      10_000,
      artifact.Zip,
    )
  let assert Ok(response_value) =
    binary_response.new(
      200,
      [
        response.Header(
          "Content-Type",
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ),
      ],
      "UEsDBA==",
      4,
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "504b0304",
      duration(5),
    )

  let assert Ok(value) =
    artifact.capture(policy, response_value, instant(1), instant(2))
  artifact.track(value) |> should.equal(finance_track.Hk)
  artifact.body_base64(value) |> should.equal("UEsDBA==")
}

pub fn runtime_policy_is_allowlisted_and_bounded_test() {
  let assert Ok(window) = time.duration(1000)
  let assert Ok(elapsed) = time.duration(15_000)
  let assert Ok(base) = time.duration(500)
  let assert Ok(maximum) = time.duration(2000)
  let assert Ok(value) =
    runtime.policy(
      origin: "https://www.sfc.hk",
      allowed_paths: ["/en/RSS-Feeds/Press-releases"],
      admissions_per_window: 1,
      window: window,
      maximum_in_flight: 1,
      maximum_waiting: 50,
      maximum_attempts: 2,
      maximum_elapsed: elapsed,
      base_delay: base,
      maximum_delay: maximum,
    )
  runtime.origin(value) |> should.equal("https://www.sfc.hk")
  runtime.allowed_paths(value)
  |> should.equal(["/en/RSS-Feeds/Press-releases"])

  runtime.policy(
    origin: "https://www.sfc.hk",
    allowed_paths: ["/unsafe?query=yes"],
    admissions_per_window: 1,
    window: window,
    maximum_in_flight: 1,
    maximum_waiting: 50,
    maximum_attempts: 2,
    maximum_elapsed: elapsed,
    base_delay: base,
    maximum_delay: maximum,
  )
  |> should.equal(Error(runtime.InvalidPath("/unsafe?query=yes")))
}

fn response_value(
  media_type: String,
  body: String,
  bytes: Int,
) -> response.Response {
  let assert Ok(duration) = time.duration(5)
  let assert Ok(value) =
    response.new(
      200,
      [response.Header("content-type", media_type)],
      body,
      bytes,
      duration,
    )
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(parsed) = time.instant(value)
  parsed
}

fn duration(value: Int) -> time.Duration {
  let assert Ok(parsed) = time.duration(value)
  parsed
}

fn hash_of(value: String) -> identity.Sha256 {
  let assert Ok(value) = hash.text(value)
  value
}
