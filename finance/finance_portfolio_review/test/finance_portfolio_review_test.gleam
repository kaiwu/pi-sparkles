import finance_portfolio_review as review
import finance_provenance/hash
import finance_provenance/identity
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
