import finance_portfolio_review as review
import finance_portfolio_review/review as journal
import finance_provenance/hash
import finance_provenance/identity
import gleam/json
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn scenario_keeps_mixed_tracks_and_exact_impact_test() {
  let packet =
    "{\"schemaVersion\":1,\"contractId\":\"portfolio_scenarios_v1\",\"operation\":\"run_scenario\",\"requestId\":\"r1\",\"snapshotId\":\"s1\",\"baseCurrency\":\"USD\",\"scale\":6,\"rounding\":\"half_even\",\"trackLegs\":[\"cn\",\"us\"],\"sourceReceipts\":[\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"],\"assumptions\":[],\"scenarioId\":\"shock-1\",\"scenarioLabel\":\"caller crash\",\"resultLabel\":\"hypothetical\",\"nlv\":\"1000\",\"positions\":[{\"positionId\":\"cn-1\",\"listingId\":\"cn-listing\",\"track\":\"cn\",\"currency\":\"CNY\",\"quantity\":\"10\",\"currentPrice\":\"50\",\"fxToBase\":\"0.14\"},{\"positionId\":\"us-1\",\"listingId\":\"us-listing\",\"track\":\"us\",\"currency\":\"USD\",\"quantity\":\"2\",\"currentPrice\":\"100\",\"fxToBase\":null}],\"shocks\":[{\"shockId\":\"a\",\"kind\":\"price_shock\",\"listingId\":\"cn-listing\",\"value\":\"-0.1\"},{\"shockId\":\"b\",\"kind\":\"price_shock\",\"listingId\":\"us-listing\",\"value\":\"-0.2\"}]}"
  let assert Ok(digest) = hash.text(packet)
  review.calculate(
    review.Descriptor("portfolio_scenarios_v1", ["run_scenario"]),
    "run_scenario",
    packet,
    identity.sha256_value(digest),
  )
  |> should.be_ok
}

pub fn rejects_changed_packet_test() {
  review.calculate(
    review.Descriptor("portfolio_scenarios_v1", ["run_scenario"]),
    "run_scenario",
    "{}",
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  |> should.equal(Error(review.ContentHashMismatch))
}

pub fn replay_reapplies_duplicate_review_identity_laws_test() {
  let packet = review_packet()
  let assert Ok(digest) = hash.text(packet)
  let assert Ok(#(state, _, _)) =
    journal.append(
      journal.empty(),
      0,
      "event-1",
      "key-1",
      packet,
      identity.sha256_value(digest),
    )
  let invalid =
    journal.encode_state(state) <> invalid_duplicate_review_event() <> "\n"
  journal.decode_jsonl(invalid)
  |> should.equal(Error(journal.InvalidJournal(2)))
}

fn review_packet() -> String {
  "{\"schemaVersion\":1,\"contractId\":\"portfolio_review_v1\",\"reviewId\":\"review-1\",\"snapshotId\":\"snapshot-1\",\"reviewAsOf\":\"2026-08-12\",\"reviewerKind\":\"user\",\"reviewerId\":\"owner-1\",\"priorReviewId\":null,\"supersedes\":null,\"changedSections\":[\"positions\"],\"receiptLinks\":[{\"section\":\"positions\",\"receipt\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}],\"conclusionRef\":null,\"privacy\":\"review_visible\"}"
}

fn invalid_duplicate_review_event() -> String {
  let semantic = duplicate_review_semantic()
  let assert Ok(digest) = semantic |> json.to_string |> hash.text
  duplicate_review_fields()
  |> list.append([
    #("canonicalContentHash", digest |> identity.sha256_value |> json.string),
  ])
  |> json.object
  |> json.to_string
}

fn duplicate_review_semantic() -> json.Json {
  json.object(duplicate_review_fields())
}

fn duplicate_review_fields() -> List(#(String, json.Json)) {
  [
    #("schemaVersion", json.int(1)),
    #("revision", json.int(2)),
    #("eventId", json.string("event-2")),
    #("idempotencyKey", json.string("key-2")),
    #("reviewId", json.string("review-1")),
    #("snapshotId", json.string("snapshot-1")),
    #("reviewAsOf", json.string("2026-08-12")),
    #("reviewerKind", json.string("user")),
    #("reviewerId", json.string("owner-1")),
    #("priorReviewId", json.null()),
    #("supersedes", json.null()),
    #("changedSections", json.array(["positions"], json.string)),
    #(
      "receiptLinks",
      json.array(
        [
          json.object([
            #("section", json.string("positions")),
            #(
              "receipt",
              json.string(
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              ),
            ),
          ]),
        ],
        fn(value) { value },
      ),
    ),
    #("conclusionRef", json.null()),
    #("privacy", json.string("review_visible")),
  ]
}
