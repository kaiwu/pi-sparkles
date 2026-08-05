import finance_authority_pdf/capture as pdf_artifact
import finance_authority_snapshot/artifact
import finance_core/source
import finance_core/time.{type Instant}
import finance_hkex.{type DocumentRef}
import finance_http/binary_response.{type Response}
import finance_http/transport.{type Cancellation}
import finance_pdf/inspector
import finance_track
import gleam/javascript/promise.{type Promise}

pub fn capture(
  document document_value: DocumentRef,
  response response_value: Response,
  retrieved_at retrieved_at_value: Instant,
) -> Result(artifact.Artifact, artifact.CaptureError) {
  artifact.capture(
    artifact_policy(document_value),
    response_value,
    retrieved_at_value,
    retrieved_at_value,
  )
}

pub fn capture_inspected(
  document document_value: DocumentRef,
  response response_value: Response,
  retrieved_at retrieved_at_value: Instant,
  cancellation cancellation_value: Cancellation,
) -> Promise(Result(pdf_artifact.PdfArtifact, pdf_artifact.CaptureError)) {
  pdf_artifact.capture(
    artifact_policy(document_value),
    inspection_policy(),
    response_value,
    retrieved_at_value,
    retrieved_at_value,
    cancellation_value,
  )
}

fn artifact_policy(document_value: DocumentRef) -> artifact.Policy {
  let assert Ok(source_ref) =
    source.new(
      provider: "HKEXnews",
      reference: finance_hkex.canonical_url(document_value),
      kind: source.Exchange,
    )
  let assert Ok(policy) =
    artifact.local_analysis_policy(
      finance_track.Hk,
      "hk_hkexnews",
      source_ref,
      "direct:HKEXnews",
      ["application/pdf", "application/octet-stream"],
      25_000_000,
      artifact.Pdf,
    )
  policy
}

fn inspection_policy() -> inspector.Policy {
  let assert Ok(timeout) = time.duration(10_000)
  let assert Ok(policy) = inspector.policy(25_000_000, 2000, timeout)
  policy
}
