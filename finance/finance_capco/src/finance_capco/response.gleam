import finance_authority_snapshot/artifact
import finance_capco.{type Snapshot}
import finance_capco/pdf_text.{type Extraction}
import finance_core/source
import finance_core/time.{type Instant}
import finance_http/binary_response.{type Response}
import finance_http/transport.{type Cancellation}
import finance_provenance/evidence
import finance_provenance/identity
import finance_track
import gleam/javascript/promise.{type Promise}

pub type Capture {
  Capture(
    snapshot: Snapshot,
    extraction: Extraction,
    retrieved_at: Instant,
    source_reference: String,
    evidence_id: String,
    source_fingerprint: String,
    media_type: String,
    response_byte_length: Int,
    content_sha256: String,
  )
}

pub type CaptureError {
  ArtifactRejected(artifact.CaptureError)
  UnexpectedByteLength(expected: Int, received: Int)
  UnreviewedContentHash(expected: String, received: String)
  TextRejected(pdf_text.ExtractionError)
}

pub fn capture(
  snapshot: Snapshot,
  response: Response,
  retrieved_at: Instant,
  cancellation: Cancellation,
) -> Promise(Result(Capture, CaptureError)) {
  case
    artifact.capture(policy(snapshot), response, retrieved_at, retrieved_at)
  {
    Error(error) -> promise.resolve(Error(ArtifactRejected(error)))
    Ok(captured) ->
      case
        binary_response.byte_length(response) == snapshot.expected_byte_length,
        binary_response.content_sha256(response) == snapshot.expected_sha256
      {
        False, _ ->
          promise.resolve(
            Error(UnexpectedByteLength(
              snapshot.expected_byte_length,
              binary_response.byte_length(response),
            )),
          )
        _, False ->
          promise.resolve(
            Error(UnreviewedContentHash(
              snapshot.expected_sha256,
              binary_response.content_sha256(response),
            )),
          )
        True, True -> {
          use extracted <- promise.await(pdf_text.extract(
            response,
            cancellation,
          ))
          case extracted {
            Error(error) -> promise.resolve(Error(TextRejected(error)))
            Ok(extraction) -> {
              let evidence.Evidence(
                evidence_id,
                source_fingerprint,
                _,
                _,
                _,
                _,
                media_type,
                response_byte_length,
                content_sha256,
                _,
                _,
                _,
              ) = artifact.evidence(captured)
              promise.resolve(
                Ok(Capture(
                  snapshot: snapshot,
                  extraction: extraction,
                  retrieved_at: retrieved_at,
                  source_reference: snapshot.pdf_origin <> snapshot.pdf_path,
                  evidence_id: identity.evidence_id_value(evidence_id),
                  source_fingerprint: identity.source_fingerprint_value(
                    source_fingerprint,
                  ),
                  media_type: media_type,
                  response_byte_length: response_byte_length,
                  content_sha256: identity.sha256_value(content_sha256),
                )),
              )
            }
          }
        }
      }
  }
}

fn policy(snapshot: Snapshot) -> artifact.Policy {
  let assert Ok(source_ref) =
    source.new(
      provider: "China Association for Public Companies (CAPCO)",
      reference: snapshot.pdf_origin <> snapshot.pdf_path,
      kind: source.Official,
    )
  let assert Ok(value) =
    artifact.local_analysis_policy(
      finance_track.Cn,
      "cn_capco",
      source_ref,
      "direct:CAPCO stock-code-sorted industry classification PDF",
      ["application/pdf"],
      1_000_000,
      artifact.Pdf,
    )
  value
}
