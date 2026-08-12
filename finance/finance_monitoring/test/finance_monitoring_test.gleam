import finance_monitoring/alerts
import finance_monitoring/source
import finance_provenance/hash
import finance_provenance/identity
import gleam/json
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
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
  let definition = valid_monitor_definition()
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

pub fn replay_rejects_self_hashed_definition_that_normal_define_forbids_test() {
  alerts.decode_jsonl(forged_invalid_definition_event() <> "\n")
  |> should.equal(Error(alerts.InvalidJournal(1)))
}

pub fn replay_rejects_self_hashed_incomplete_evaluation_test() {
  let definition = valid_monitor_definition()
  let assert Ok(definition_hash) = hash.text(definition)
  let definition_sha = identity.sha256_value(definition_hash)
  let assert Ok(#(defined, _, _)) =
    alerts.define(
      alerts.empty(),
      0,
      "definition-1",
      "define-m1-v1",
      1000,
      "review_visible",
      definition,
      definition_sha,
    )
  let incomplete_payload =
    json.object([
      #("monitorId", json.string("m1")),
      #("definitionEventId", json.string("definition-1")),
      #("definitionContentHash", json.string(definition_sha)),
    ])
    |> json.to_string
  let forged =
    forged_event(
      2,
      "evaluation-forged",
      "evaluation-forged-key",
      "m1",
      "evaluation",
      Some("definition-1"),
      incomplete_payload,
    )
  alerts.decode_jsonl(alerts.encode_state(defined) <> forged <> "\n")
  |> should.equal(Error(alerts.InvalidJournal(2)))
}

pub fn evaluation_rejects_known_field_without_value_test() {
  let definition = valid_monitor_definition()
  let assert Ok(definition_hash) = hash.text(definition)
  let assert Ok(#(defined, _, _)) =
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
  let invalid_batch =
    "{\"schemaVersion\":1,\"contractId\":\"finance_alerts_batch_v1\",\"batchId\":\"batch-invalid\",\"monitorId\":\"m1\",\"evaluatedAtUnixMilliseconds\":2000,\"observations\":[{\"observationId\":\"o1\",\"eventIdentity\":\"filing-1\",\"contentHash\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"observedAtUnixMilliseconds\":1900,\"knowledgeAtUnixMilliseconds\":1900,\"corrects\":null,\"fields\":[{\"name\":\"form\",\"state\":\"known\",\"value\":null}]}],\"sourceReceipts\":[\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"]}"
  let assert Ok(batch_hash) = hash.text(invalid_batch)
  alerts.evaluate(
    defined,
    1,
    "evaluation-invalid",
    "evaluation-invalid-key",
    2000,
    "review_visible",
    invalid_batch,
    identity.sha256_value(batch_hash),
  )
  |> should.equal(Error(alerts.InvalidBatch))
}

pub fn evaluation_deduplicates_within_batch_and_honors_window_test() {
  let definition = valid_monitor_definition()
  let assert Ok(definition_hash) = hash.text(definition)
  let assert Ok(#(defined, _, _)) =
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
  let content =
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let first_batch =
    monitor_batch("batch-1", 2000, [#("o1", content), #("o2", content)])
  let assert Ok(first_hash) = hash.text(first_batch)
  let assert Ok(#(first_state, _, first_result)) =
    alerts.evaluate(
      defined,
      1,
      "evaluation-1",
      "evaluation-key-1",
      2000,
      "review_visible",
      first_batch,
      identity.sha256_value(first_hash),
    )
  let first_text = json.to_string(first_result)
  first_text |> string.contains("\"matchCount\":1") |> should.be_true
  first_text |> string.contains("duplicate_suppressed") |> should.be_true

  let later = 86_403_000
  let second_batch = monitor_batch("batch-2", later, [#("o3", content)])
  let assert Ok(second_hash) = hash.text(second_batch)
  let assert Ok(#(_, _, second_result)) =
    alerts.evaluate(
      first_state,
      2,
      "evaluation-2",
      "evaluation-key-2",
      later,
      "review_visible",
      second_batch,
      identity.sha256_value(second_hash),
    )
  json.to_string(second_result)
  |> string.contains("\"matchCount\":1")
  |> should.be_true
}

fn valid_monitor_definition() -> String {
  "{\"schemaVersion\":1,\"contractId\":\"finance_alerts_definition_v1\",\"monitorId\":\"m1\",\"version\":1,\"ownerKind\":\"user\",\"ownerId\":\"owner-1\",\"scope\":{\"kind\":\"company\",\"track\":\"us\",\"listingIds\":[\"US1\"],\"mic\":\"XNAS\",\"sourceScope\":[\"filing_monitor\"],\"eventKinds\":[\"FilingPublished\"],\"portfolioReceipt\":null},\"predicate\":{\"kind\":\"caller_supplied\",\"field\":\"form\",\"operator\":\"exact_equals\",\"value\":\"10-K\"},\"temporal\":{\"freshnessCutoffSeconds\":3600,\"startAtUnixMilliseconds\":1000,\"endAtUnixMilliseconds\":null},\"dedupe\":{\"kind\":\"by_content_hash\",\"windowSeconds\":86400,\"cooldownSeconds\":0,\"scope\":\"per_monitor\"},\"budgets\":{\"maxEventsPerBatch\":100,\"maxMatchesPerBatch\":10,\"maxConsecutiveFailures\":5},\"notificationAuthorization\":{\"authorized\":true,\"authorizationId\":\"auth-1\",\"channel\":\"scripted_local\",\"destinationRef\":\"opaque-destination-1\",\"maximumAttempts\":2},\"retentionPolicy\":\"caller_owned_append_only\",\"parentEventId\":null,\"sourceEntitlementReceipts\":[\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"]}"
}

fn monitor_batch(
  batch_id: String,
  evaluated_at: Int,
  observations: List(#(String, String)),
) -> String {
  json.object([
    #("schemaVersion", json.int(1)),
    #("contractId", json.string("finance_alerts_batch_v1")),
    #("batchId", json.string(batch_id)),
    #("monitorId", json.string("m1")),
    #("evaluatedAtUnixMilliseconds", json.int(evaluated_at)),
    #(
      "observations",
      json.array(observations, fn(value) {
        let #(observation_id, content_hash) = value
        json.object([
          #("observationId", json.string(observation_id)),
          #("eventIdentity", json.string("event-" <> observation_id)),
          #("contentHash", json.string(content_hash)),
          #("observedAtUnixMilliseconds", json.int(evaluated_at)),
          #("knowledgeAtUnixMilliseconds", json.int(evaluated_at)),
          #("corrects", json.null()),
          #(
            "fields",
            json.array([#("form", "known", "10-K")], fn(field) {
              let #(name, state, value) = field
              json.object([
                #("name", json.string(name)),
                #("state", json.string(state)),
                #("value", json.string(value)),
              ])
            }),
          ),
        ])
      }),
    ),
    #(
      "sourceReceipts",
      json.array(
        [
          "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        ],
        json.string,
      ),
    ),
  ])
  |> json.to_string
}

fn forged_event(
  revision: Int,
  event_id: String,
  idempotency_key: String,
  monitor_id: String,
  kind: String,
  parent_event_id: Option(String),
  payload: String,
) -> String {
  let assert Ok(payload_digest) = hash.text(payload)
  let semantic =
    json.object([
      #("schemaVersion", json.int(1)),
      #("revision", json.int(revision)),
      #("eventId", json.string(event_id)),
      #("idempotencyKey", json.string(idempotency_key)),
      #("monitorId", json.string(monitor_id)),
      #("kind", json.string(kind)),
      #("occurredAtUnixMilliseconds", json.int(2000)),
      #("privacy", json.string("review_visible")),
      #("parentEventId", json.nullable(parent_event_id, json.string)),
      #("payload", json.string(payload)),
      #("payloadSha256", payload_digest |> identity.sha256_value |> json.string),
    ])
  let assert Ok(canonical_digest) = semantic |> json.to_string |> hash.text
  json.object([
    #("event", semantic),
    #(
      "canonicalContentHash",
      canonical_digest |> identity.sha256_value |> json.string,
    ),
  ])
  |> json.to_string
}

fn forged_invalid_definition_event() -> String {
  let payload = "{}"
  let assert Ok(payload_digest) = hash.text(payload)
  let semantic =
    json.object([
      #("schemaVersion", json.int(1)),
      #("revision", json.int(1)),
      #("eventId", json.string("forged-1")),
      #("idempotencyKey", json.string("forged-key-1")),
      #("monitorId", json.string("m1")),
      #("kind", json.string("definition")),
      #("occurredAtUnixMilliseconds", json.int(1)),
      #("privacy", json.string("review_visible")),
      #("parentEventId", json.null()),
      #("payload", json.string(payload)),
      #("payloadSha256", payload_digest |> identity.sha256_value |> json.string),
    ])
  let assert Ok(canonical_digest) = semantic |> json.to_string |> hash.text
  json.object([
    #("event", semantic),
    #(
      "canonicalContentHash",
      canonical_digest |> identity.sha256_value |> json.string,
    ),
  ])
  |> json.to_string
}
