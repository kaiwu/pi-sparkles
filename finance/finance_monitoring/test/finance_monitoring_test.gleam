import finance_monitoring/alerts
import finance_monitoring/source
import finance_provenance/hash
import finance_provenance/identity
import gleam/result
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn timeline_preserves_correction_and_equal_time_order_test() {
  let packet =
    "{\"schemaVersion\":1,\"contractId\":\"filing_monitor_v1\",\"requestId\":\"r1\",\"track\":\"us\",\"listingId\":\"US1\",\"mic\":\"XNAS\",\"rangeStart\":\"2026-01-01\",\"rangeEnd\":\"2026-12-31\",\"timezone\":\"America/New_York\",\"sources\":[{\"sourceId\":\"sec\",\"provider\":\"SEC EDGAR\",\"authorityRole\":\"official_filing_repository\",\"retrievedAt\":\"2026-08-11T00:00:00Z\",\"coverage\":\"bounded submissions receipt\",\"entitlement\":\"public\",\"licence\":\"public filing\",\"contentHash\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"status\":\"complete_for_page\",\"limitations\":[]}],\"events\":[{\"ordinal\":0,\"eventId\":\"f1\",\"kind\":\"FilingPublished\",\"title\":\"10-K\",\"language\":\"en\",\"eventTime\":null,\"publicationTime\":\"2026-02-01T00:00:00Z\",\"retrievalTime\":\"2026-08-11T00:00:00Z\",\"effectiveTime\":\"2025-12-31\",\"sourceId\":\"sec\",\"sourceReceipt\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"documentId\":\"d1\",\"originalLexeme\":\"10-K\",\"corrects\":null,\"retracted\":false},{\"ordinal\":1,\"eventId\":\"f2\",\"kind\":\"FilingAmended\",\"title\":\"10-K/A\",\"language\":\"en\",\"eventTime\":null,\"publicationTime\":\"2026-02-01T00:00:00Z\",\"retrievalTime\":\"2026-08-11T00:00:00Z\",\"effectiveTime\":\"2025-12-31\",\"sourceId\":\"sec\",\"sourceReceipt\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"documentId\":\"d2\",\"originalLexeme\":\"10-K/A\",\"corrects\":\"f1\",\"retracted\":false}],\"omissions\":[]}"
  let assert Ok(digest) = hash.text(packet)
  source.project(
    source.Descriptor("filing_monitor_v1", ["us"], [
      "FilingPublished",
      "FilingAmended",
    ]),
    packet,
    identity.sha256_value(digest),
    0,
    20,
  )
  |> should.be_ok
}

pub fn durable_monitor_evaluates_replays_and_authorizes_notification_test() {
  let definition =
    "{\"schemaVersion\":1,\"contractId\":\"finance_alerts_definition_v1\",\"monitorId\":\"m1\",\"version\":1,\"ownerKind\":\"user\",\"ownerId\":\"owner-1\",\"scope\":{\"kind\":\"company\",\"track\":\"us\",\"listingIds\":[\"US1\"],\"mic\":\"XNAS\",\"sourceScope\":[\"filing_monitor\"],\"eventKinds\":[\"FilingPublished\"],\"portfolioReceipt\":null},\"predicate\":{\"kind\":\"caller_supplied\",\"field\":\"form\",\"operator\":\"exact_equals\",\"value\":\"10-K\"},\"temporal\":{\"freshnessCutoffSeconds\":3600,\"startAtUnixMilliseconds\":1000,\"endAtUnixMilliseconds\":null},\"dedupe\":{\"kind\":\"by_content_hash\",\"windowSeconds\":86400,\"cooldownSeconds\":0,\"scope\":\"per_monitor\"},\"budgets\":{\"maxEventsPerBatch\":100,\"maxMatchesPerBatch\":10,\"maxConsecutiveFailures\":5},\"notificationAuthorization\":{\"authorized\":true,\"authorizationId\":\"auth-1\",\"channel\":\"scripted_local\",\"destinationRef\":\"opaque-destination-1\",\"maximumAttempts\":2},\"retentionPolicy\":\"caller_owned_append_only\",\"parentEventId\":null,\"sourceEntitlementReceipts\":[\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"]}"
  let assert Ok(definition_hash) = hash.text(definition)
  let assert Ok(#(defined, alerts.Stored("definition-1"), _)) =
    alerts.define(
      alerts.empty(),
      0,
      "definition-1",
      "define-m1-v1",
      1000,
      "review_visible",
      definition,
      identity.sha256_value(definition_hash),
    )
  let batch =
    "{\"schemaVersion\":1,\"contractId\":\"finance_alerts_batch_v1\",\"batchId\":\"batch-1\",\"monitorId\":\"m1\",\"evaluatedAtUnixMilliseconds\":2000,\"observations\":[{\"observationId\":\"o1\",\"eventIdentity\":\"filing-1\",\"contentHash\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"observedAtUnixMilliseconds\":1900,\"knowledgeAtUnixMilliseconds\":1900,\"corrects\":null,\"fields\":[{\"name\":\"form\",\"state\":\"known\",\"value\":\"10-K\"}]}],\"sourceReceipts\":[\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"]}"
  let assert Ok(batch_hash) = hash.text(batch)
  let assert Ok(#(evaluated, alerts.Stored("evaluation-1"), _)) =
    alerts.evaluate(
      defined,
      1,
      "evaluation-1",
      "evaluate-batch-1",
      2000,
      "review_visible",
      batch,
      identity.sha256_value(batch_hash),
    )
  let assert Ok(#(notified, alerts.Stored("notification-1"), _)) =
    alerts.record_notification(
      evaluated,
      2,
      "notification-1",
      "notify-match-1-attempt-1",
      "m1",
      "m1:o1:v1",
      "auth-1",
      "scripted_local",
      "opaque-destination-1",
      1,
      "delivered",
      "scripted:delivered:1",
      2100,
      "review_visible",
    )
  alerts.revision(notified) |> should.equal(3)
  notified
  |> alerts.encode_state
  |> alerts.decode_jsonl
  |> result.map(alerts.revision)
  |> should.equal(Ok(3))
}

pub fn notification_fails_closed_without_exact_authorization_test() {
  alerts.record_notification(
    alerts.empty(),
    0,
    "n1",
    "n1",
    "missing",
    "match",
    "auth",
    "scripted_local",
    "destination",
    1,
    "delivered",
    "receipt",
    1,
    "private",
  )
  |> should.equal(Error(alerts.MonitorNotFound("missing")))
}
