import finance_broker_review
import finance_broker_review/decode.{
  type EventInput, type ReviewInput, EventInput, FactInput, ReviewInput,
}
import finance_broker_review/field
import gleam/json
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should

const hash_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const hash_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const hash_c = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

pub fn main() {
  gleeunit.main()
}

pub fn review_is_partial_and_non_executable_test() {
  let assert Ok(value) =
    finance_broker_review.review(
      input([]),
      "fixture_provider",
      "cn",
      [#("activity_import", "paper")],
      ["provider_network_observation"],
    )
  let details = finance_broker_review.details(value) |> json.to_string
  details |> string.contains("\"maturity\":\"track_partial\"") |> should.be_true
  details |> string.contains("\"networkPerformed\":false") |> should.be_true
  details
  |> string.contains("\"brokerAuthorityAccepted\":false")
  |> should.be_true
  details |> string.contains("\"executable\":false") |> should.be_true
}

pub fn conflicts_are_not_silently_resolved_test() {
  let first = EventInput(hash_b, "working", 1, hash_c)
  let changed = EventInput(hash_b, "filled", 2, hash_c)
  let assert Ok(value) =
    finance_broker_review.review(
      input([first, changed]),
      "fixture_provider",
      "cn",
      [#("activity_import", "paper")],
      ["provider_network_observation"],
    )
  finance_broker_review.details(value)
  |> json.to_string
  |> string.contains("\"state\":\"conflicting\"")
  |> should.be_true
}

pub fn mismatched_track_fails_closed_test() {
  finance_broker_review.review(
    ReviewInput(
      "test",
      "activity_import",
      "paper",
      hash_a,
      "us",
      "600000",
      "XSHG",
      hash_b,
      [],
      [],
      [],
    ),
    "fixture_provider",
    "cn",
    [#("activity_import", "paper")],
    ["provider_network_observation"],
  )
  |> should.be_error
}

pub fn mismatched_mode_and_environment_fail_closed_test() {
  let value = input([])
  finance_broker_review.review(
    ReviewInput(
      value.operation_id,
      "activity_import",
      "live",
      value.account_reference,
      value.track,
      value.listing_id,
      value.mic,
      value.source_content_hash,
      value.facts,
      value.events,
      value.missing_capabilities,
    ),
    "fixture_provider",
    "cn",
    [#("activity_import", "paper")],
    ["provider_network_observation"],
  )
  |> should.be_error
}

pub fn market_depth_fact_names_fail_closed_test() {
  let value = input([])
  finance_broker_review.review(
    ReviewInput(
      value.operation_id,
      value.mode,
      value.environment,
      value.account_reference,
      value.track,
      value.listing_id,
      value.mic,
      value.source_content_hash,
      [FactInput("bestBidPrice", "known", Some("10"), Some("CNY"), hash_c)],
      value.events,
      value.missing_capabilities,
    ),
    "fixture_provider",
    "cn",
    [#("activity_import", "paper")],
    ["provider_network_observation"],
  )
  |> should.be_error
}

pub fn empty_evidence_fails_closed_test() {
  finance_broker_review.review(
    ReviewInput(
      "test",
      "activity_import",
      "paper",
      hash_a,
      "cn",
      "600000",
      "XSHG",
      hash_b,
      [],
      [],
      [],
    ),
    "fixture_provider",
    "cn",
    [#("activity_import", "paper")],
    ["provider_network_observation"],
  )
  |> should.be_error
}

pub fn market_depth_name_guard_avoids_unrelated_task_names_test() {
  field.is_market_depth_name("review_task") |> should.be_false
  field.is_market_depth_name("currentBidPrice") |> should.be_true
  field.is_market_depth_name("best_offer_size") |> should.be_true
}

pub fn missing_scope_changes_the_semantic_receipt_test() {
  let base = input([])
  let changed =
    ReviewInput(
      base.operation_id,
      base.mode,
      base.environment,
      base.account_reference,
      base.track,
      base.listing_id,
      base.mic,
      base.source_content_hash,
      base.facts,
      base.events,
      ["additional_partial_scope"],
    )
  let assert Ok(first) =
    finance_broker_review.review(
      base,
      "fixture_provider",
      "cn",
      [#("activity_import", "paper")],
      ["provider_network_observation"],
    )
  let assert Ok(second) =
    finance_broker_review.review(
      changed,
      "fixture_provider",
      "cn",
      [#("activity_import", "paper")],
      ["provider_network_observation"],
    )
  finance_broker_review.receipt(first)
  |> should.not_equal(finance_broker_review.receipt(second))
}

fn input(events: List(EventInput)) -> ReviewInput {
  ReviewInput(
    "test",
    "activity_import",
    "paper",
    hash_a,
    "cn",
    "600000",
    "XSHG",
    hash_b,
    [FactInput("cash", "known", Some("1000.00"), Some("CNY"), hash_c)],
    events,
    [],
  )
}
