import finance_broker_review
import finance_broker_review/decode.{
  type ExplicitCapabilityInput, type FactInput, EventInput,
  ExplicitCapabilityInput, FactInput, ReviewInput,
}
import gleam/json
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_cn_broker_readonly/domain

const hash_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const hash_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const hash_c = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

pub fn main() {
  gleeunit.main()
}

pub fn explicit_provider_packet_is_complete_and_non_executing_test() {
  let assert Ok(value) = domain.run(input("futu_opend"))
  let details = finance_broker_review.details(value) |> json.to_string
  details |> string.contains("\"maturity\":\"experimental\"") |> should.be_true
  details |> string.contains("\"provider\":\"futu_opend\"") |> should.be_true
  details
  |> string.contains("\"mode\":\"explicit_external_capability\"")
  |> should.be_true
  details |> string.contains("\"adapterBundled\":false") |> should.be_true
  details |> string.contains("\"networkPerformed\":false") |> should.be_true
  details |> string.contains("\"executable\":false") |> should.be_true
}

pub fn provider_fact_must_match_selected_dependency_test() {
  domain.run(input("another_provider")) |> should.be_error
}

pub fn cn_identity_does_not_cross_tracks_test() {
  let ExplicitCapabilityInput(provider, review) = input("futu_opend")
  domain.run(ExplicitCapabilityInput(
    provider,
    ReviewInput(
      review.operation_id,
      review.mode,
      review.environment,
      review.account_reference,
      "hk",
      review.listing_id,
      "XHKG",
      review.source_content_hash,
      review.facts,
      review.events,
      review.missing_capabilities,
    ),
  ))
  |> should.be_error
}

pub fn write_capable_mode_fails_closed_test() {
  let ExplicitCapabilityInput(provider, review) = input("futu_opend")
  domain.run(ExplicitCapabilityInput(
    provider,
    ReviewInput(
      review.operation_id,
      "live_order",
      review.environment,
      review.account_reference,
      review.track,
      review.listing_id,
      review.mic,
      review.source_content_hash,
      review.facts,
      review.events,
      review.missing_capabilities,
    ),
  ))
  |> should.be_error
}

fn input(provider: String) -> ExplicitCapabilityInput {
  ExplicitCapabilityInput(
    provider,
    ReviewInput(
      "cn-readonly-test",
      "read_only_capability",
      "external_live",
      hash_a,
      "cn",
      "listing:600000:XSHG",
      "XSHG",
      hash_b,
      [
        fact("broker_provider", "futu_opend", "provider_identifier"),
        fact("listing_board", "main_board", "exchange_board"),
        fact("share_class", "a_share", "share_class"),
        fact("native_currency", "CNY", "iso_4217"),
        fact("settlement_cycle", "T+1", "provider_observation"),
        fact(
          "capability_scope",
          "account,position,order,fill",
          "capability_set",
        ),
        fact(
          "entitlement_scope",
          "caller_owned_read_only",
          "entitlement_declaration",
        ),
        fact("read_only_authority", "read_only", "authority_scope"),
      ],
      [EventInput(hash_c, "filled", 1_786_656_000_000, hash_b)],
      [],
    ),
  )
}

fn fact(name: String, value: String, unit: String) -> FactInput {
  FactInput(name, "known", Some(value), Some(unit), hash_c)
}
