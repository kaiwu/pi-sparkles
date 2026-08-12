import finance_authority_pdf
import finance_authority_pdf/capture
import finance_authority_snapshot/artifact
import finance_core/source
import finance_core/time
import finance_http/binary_response
import finance_http/response
import finance_http/transport
import finance_pdf/inspector
import finance_track
import gleam/javascript/promise
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_authority_pdf.status()
  |> should.equal(finance_authority_pdf.Experimental)
}

pub fn capture_contains_a_rejected_injected_inspector_test() {
  let assert Ok(source_ref) =
    source.new(
      "Test authority",
      "https://example.test/report.pdf",
      source.Official,
    )
  let assert Ok(artifact_policy) =
    artifact.local_analysis_policy(
      finance_track.Cn,
      "cn_test_authority_pdf",
      source_ref,
      "direct:test authority PDF",
      ["application/pdf"],
      100,
      artifact.Pdf,
    )
  let assert Ok(timeout) = time.duration(1000)
  let assert Ok(inspection_policy) = inspector.policy(100, 10, timeout)
  let assert Ok(elapsed) = time.duration(1)
  let assert Ok(response_value) =
    binary_response.new(
      200,
      [response.Header("content-type", "application/pdf")],
      "JVBERi0=",
      5,
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "255044462d",
      elapsed,
    )
  let assert Ok(now) = time.instant(1_700_000_000_000)

  use result <- promise.await(capture.capture_with(
    artifact_policy,
    inspection_policy,
    response_value,
    now,
    now,
    transport.new_cancellation(),
    rejected_inspector,
  ))
  result |> should.equal(Error(capture.InspectionEffectRejected))
  promise.resolve(Nil)
}

@external(javascript, "./finance_authority_pdf_test_ffi.mjs", "rejected_inspector")
fn rejected_inspector(
  policy: inspector.Policy,
  response: binary_response.Response,
  cancellation: transport.Cancellation,
) -> promise.Promise(Result(inspector.Inspection, inspector.InspectionError))
