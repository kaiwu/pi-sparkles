import finance_authority_snapshot/artifact
import finance_core/time.{type Instant}
import finance_document_attachment/policy as attachment_policy
import finance_http/binary_response.{type Response}
import finance_http/transport.{type Cancellation}
import finance_pdf/inspector
import finance_provenance/evidence
import gleam/javascript/promise.{type Promise}
import gleam/option.{Some}

pub type Inspector =
  fn(inspector.Policy, Response, Cancellation) ->
    Promise(Result(inspector.Inspection, inspector.InspectionError))

pub opaque type PdfArtifact {
  PdfArtifact(artifact: artifact.Artifact, inspection: inspector.Inspection)
}

pub type CaptureError {
  ArtifactRejected(error: artifact.CaptureError)
  InspectionRejected(error: inspector.InspectionError)
  InspectionEffectRejected
}

/// Capture and inspect the same response, preventing a caller from pairing a
/// page count from one PDF with the evidence hash of another.
pub fn capture(
  artifact_policy artifact_policy_value: artifact.Policy,
  inspection_policy inspection_policy_value: inspector.Policy,
  response response_value: Response,
  as_of as_of_value: Instant,
  retrieved_at retrieved_at_value: Instant,
  cancellation cancellation_value: Cancellation,
) -> Promise(Result(PdfArtifact, CaptureError)) {
  capture_with(
    artifact_policy_value,
    inspection_policy_value,
    response_value,
    as_of_value,
    retrieved_at_value,
    cancellation_value,
    inspector.inspect,
  )
}

/// Inject the inspector effect for deterministic provider tests.
pub fn capture_with(
  artifact_policy artifact_policy_value: artifact.Policy,
  inspection_policy inspection_policy_value: inspector.Policy,
  response response_value: Response,
  as_of as_of_value: Instant,
  retrieved_at retrieved_at_value: Instant,
  cancellation cancellation_value: Cancellation,
  inspect inspect_effect: Inspector,
) -> Promise(Result(PdfArtifact, CaptureError)) {
  case
    artifact.capture(
      artifact_policy_value,
      response_value,
      as_of_value,
      retrieved_at_value,
    )
  {
    Error(error) -> promise.resolve(Error(ArtifactRejected(error)))
    Ok(captured) -> {
      use inspected <- promise.await(
        inspect_effect(
          inspection_policy_value,
          response_value,
          cancellation_value,
        )
        |> promise.map(Ok)
        |> promise.rescue(fn(_) { Error(Nil) }),
      )
      case inspected {
        Error(_) -> promise.resolve(Error(InspectionEffectRejected))
        Ok(Error(error)) -> promise.resolve(Error(InspectionRejected(error)))
        Ok(Ok(value)) -> promise.resolve(Ok(PdfArtifact(captured, value)))
      }
    }
  }
}

pub fn artifact(value: PdfArtifact) -> artifact.Artifact {
  value.artifact
}

pub fn inspection(value: PdfArtifact) -> inspector.Inspection {
  value.inspection
}

pub fn page_count(value: PdfArtifact) -> Int {
  value.inspection |> inspector.page_count
}

/// Compose proven byte/hash/page facts into the existing attachment policy.
///
/// OCR remains an explicit caller decision because structural PDF inspection
/// does not prove whether a document has an adequate text layer.
pub fn attachment_metadata(
  value: PdfArtifact,
  ocr ocr_decision: attachment_policy.Ocr,
) -> attachment_policy.Metadata {
  let evidence.Evidence(
    _,
    _,
    _,
    _,
    _,
    _,
    media_type,
    byte_length,
    content_hash,
    _,
    _,
    _,
  ) = artifact.evidence(value.artifact)
  attachment_policy.Metadata(
    media_type: media_type,
    byte_length: byte_length,
    page_count: Some(page_count(value)),
    redirect_count: 0,
    cross_host_redirect: False,
    archive: attachment_policy.NotArchive,
    ocr: ocr_decision,
    cancelled: False,
    content_hash: Some(content_hash),
  )
}
