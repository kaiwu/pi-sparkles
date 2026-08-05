import finance_core/source
import finance_http/cache
import finance_provider_strategy
import finance_provider_strategy/strategy
import finance_track
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_provider_strategy.status()
  |> should.equal(finance_provider_strategy.Experimental)
}

pub fn first_compatible_success_preserves_origin_and_route_test() {
  let contract = document_contract("SSE:2026-001")
  let origin = exchange_source("SSE", "SSE:2026-001")
  let direct =
    approved_channel(
      finance_track.Cn,
      "cn_sse_direct",
      origin,
      strategy.Direct,
      contract,
    )
  let mirrored =
    approved_channel(
      finance_track.Cn,
      "cn_sse_via_cninfo",
      origin,
      strategy.Via("CNINFO"),
      contract,
    )
  let assert Ok(plan) =
    strategy.plan(finance_track.Cn, contract, strategy.CacheFirst, [
      direct,
      mirrored,
    ])
  let assert Ok(miss) = strategy.unavailable(direct, "origin unavailable")
  let hit = strategy.succeeded(mirrored, contract, "raw-document")
  let assert Ok(strategy.Selected(record, trace)) =
    strategy.resolve(plan, [miss, hit])

  trace |> list.length |> should.equal(2)
  strategy.record_value(record) |> should.equal("raw-document")
  strategy.record_channel(record)
  |> strategy.channel_origin
  |> source.provider
  |> should.equal("SSE")
  strategy.record_channel(record)
  |> strategy.channel_route
  |> should.equal(strategy.Via("CNINFO"))
  strategy.http_cache_mode(strategy.cache_policy(plan))
  |> should.equal(cache.ReadThrough)
}

pub fn incompatible_success_stops_instead_of_silently_falling_back_test() {
  let expected = document_contract("SSE:2026-001")
  let wrong = document_contract("SSE:2026-002")
  let origin = exchange_source("SSE", "SSE:2026-001")
  let direct =
    approved_channel(
      finance_track.Cn,
      "cn_sse_direct",
      origin,
      strategy.Direct,
      expected,
    )
  let assert Ok(plan) =
    strategy.plan(finance_track.Cn, expected, strategy.CacheFirst, [direct])

  strategy.resolve(plan, [strategy.succeeded(direct, wrong, "wrong")])
  |> should.equal(Error(strategy.IncompatibleSuccess("cn_sse_direct")))
}

pub fn candidate_and_cross_track_channels_cannot_enter_a_plan_test() {
  let contract = quote_contract()
  let assert Ok(vendor) =
    source.new("Eastmoney", "A-share realtime", source.LicensedVendor)
  let assert Ok(candidate) =
    strategy.channel(
      finance_track.Cn,
      "cn_eastmoney_via_akshare",
      vendor,
      strategy.Via("AKShare"),
      strategy.SecondaryObservation,
      strategy.Candidate("terms and realtime semantics require review"),
      strategy.LocalAnalysisOnly,
      contract,
    )
  strategy.plan(finance_track.Cn, contract, strategy.CacheFirst, [candidate])
  |> should.equal(Error(strategy.UnapprovedChannel("cn_eastmoney_via_akshare")))

  let hk_origin = exchange_source("HKEX", "quote")
  let hk =
    approved_channel(
      finance_track.Hk,
      "hk_hkex_quote",
      hk_origin,
      strategy.Direct,
      contract,
    )
  strategy.plan(finance_track.Cn, contract, strategy.CacheFirst, [hk])
  |> should.equal(Error(strategy.TrackMismatch("hk_hkex_quote")))
}

pub fn attempt_order_is_exact_and_selected_records_are_isolated_test() {
  let contract = quote_contract()
  let origin = exchange_source("SSE", "quote")
  let first =
    approved_observation_channel(
      "cn_primary",
      origin,
      strategy.PrimaryObservation,
      contract,
    )
  let second =
    approved_observation_channel(
      "cn_secondary",
      origin,
      strategy.SecondaryObservation,
      contract,
    )
  let assert Ok(plan) =
    strategy.plan(finance_track.Cn, contract, strategy.RevalidateCache, [
      first,
      second,
    ])
  let assert Ok(second_miss) = strategy.failed(second, "timeout")
  strategy.resolve(plan, [second_miss])
  |> should.equal(
    Error(strategy.UnexpectedAttempt("cn_primary", "cn_secondary")),
  )

  let hit = strategy.succeeded(first, contract, 42)
  let assert Ok(extra) = strategy.unavailable(second, "not needed")
  strategy.resolve(plan, [hit, extra])
  |> should.equal(Error(strategy.AttemptsAfterSelection("cn_primary")))
}

fn document_contract(identity: String) -> strategy.Contract {
  let assert Ok(value) =
    strategy.contract(
      family: "issuer_disclosure",
      identity: identity,
      freshness: "published_artifact",
      unit_basis: "source_document",
      adjustment_basis: "not_applicable",
    )
  value
}

fn quote_contract() -> strategy.Contract {
  let assert Ok(value) =
    strategy.contract(
      family: "equity_quote",
      identity: "XSHG:600000",
      freshness: "realtime_provider_timestamp",
      unit_basis: "price_cny_volume_shares",
      adjustment_basis: "unadjusted",
    )
  value
}

fn exchange_source(provider: String, reference: String) -> source.SourceRef {
  let assert Ok(value) = source.new(provider, reference, source.Exchange)
  value
}

fn approved_channel(
  track: finance_track.Track,
  id: String,
  origin: source.SourceRef,
  route: strategy.Route,
  contract: strategy.Contract,
) -> strategy.Channel {
  let assert Ok(value) =
    strategy.channel(
      track,
      id,
      origin,
      route,
      strategy.CanonicalEvidence,
      strategy.VerifiedReadOnly,
      strategy.LocalAnalysisOnly,
      contract,
    )
  value
}

fn approved_observation_channel(
  id: String,
  origin: source.SourceRef,
  role: strategy.Role,
  contract: strategy.Contract,
) -> strategy.Channel {
  let assert Ok(value) =
    strategy.channel(
      finance_track.Cn,
      id,
      origin,
      strategy.Direct,
      role,
      strategy.Contracted,
      strategy.ContractControlled,
      contract,
    )
  value
}
