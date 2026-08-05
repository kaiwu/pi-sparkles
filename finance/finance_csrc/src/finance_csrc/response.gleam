import finance_authority_snapshot/snapshot
import finance_core/source
import finance_core/time.{type Instant}
import finance_csrc.{type Dataset}
import finance_csrc/request
import finance_http/response.{type Response}
import finance_track

pub fn capture(
  dataset dataset_value: Dataset,
  response response_value: Response,
  retrieved_at retrieved_at_value: Instant,
) -> Result(snapshot.Snapshot, snapshot.CaptureError) {
  let assert Ok(source_ref) =
    source.new(
      provider: "CSRC",
      reference: request.origin <> request.path(dataset_value),
      kind: source.Regulator,
    )
  let assert Ok(policy) =
    snapshot.local_analysis_policy(
      finance_track.Cn,
      "cn_csrc",
      source_ref,
      ["text/html", "application/xhtml+xml"],
      2_000_000,
    )
  snapshot.capture(
    policy,
    response_value,
    retrieved_at_value,
    retrieved_at_value,
  )
}
