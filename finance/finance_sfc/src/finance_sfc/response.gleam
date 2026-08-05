import finance_authority_snapshot/snapshot
import finance_core/source
import finance_core/time.{type Instant}
import finance_http/response.{type Response}
import finance_track

pub fn capture_press_releases(
  response response_value: Response,
  retrieved_at retrieved_at_value: Instant,
) -> Result(snapshot.Snapshot, snapshot.CaptureError) {
  let assert Ok(source_ref) =
    source.new(
      provider: "SFC",
      reference: "https://www.sfc.hk/en/RSS-Feeds/Press-releases",
      kind: source.Regulator,
    )
  let assert Ok(policy) =
    snapshot.local_analysis_policy(
      finance_track.Hk,
      "hk_sfc",
      source_ref,
      ["application/rss+xml", "application/xml", "text/xml"],
      1_000_000,
    )
  snapshot.capture(
    policy,
    response_value,
    retrieved_at_value,
    retrieved_at_value,
  )
}
