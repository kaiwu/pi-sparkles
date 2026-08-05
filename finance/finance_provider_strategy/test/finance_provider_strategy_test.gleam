import finance_core/source
import finance_http/cache
import finance_provider_strategy
import finance_provider_strategy/coverage
import finance_provider_strategy/credibility
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

pub fn operational_coverage_uses_the_multichannel_union_once_test() {
  let assert Ok(policy) =
    coverage.operational_policy(finance_track.Cn, "market_picture", 2)
  let authority =
    contribution(
      finance_track.Cn,
      "cn_authority",
      "SSE",
      list.take(requirement_ids(), 10),
    )
  let vendor =
    contribution(
      finance_track.Cn,
      "cn_vendor",
      "licensed_vendor",
      requirement_ids() |> list.drop(8) |> list.take(9),
    )
  let assert Ok(assessment) =
    coverage.assess(policy, coverage_requirements(), [authority, vendor])

  coverage.coverage_basis_points(assessment) |> should.equal(8500)
  coverage.assessment_readiness(assessment)
  |> should.equal(coverage.OperationallyReady)
  coverage.source_groups(assessment) |> should.equal(["SSE", "licensed_vendor"])
  coverage.assessment_contributions(assessment)
  |> list.map(coverage.contribution_channel_id)
  |> should.equal(["cn_authority", "cn_vendor"])
  coverage.missing_requirements(assessment)
  |> should.equal([
    "analyst_estimates",
    "social_sentiment",
    "peer_classification",
  ])
}

pub fn mirrors_do_not_manufacture_independent_source_groups_test() {
  let assert Ok(policy) =
    coverage.operational_policy(finance_track.Cn, "issuer_disclosures", 2)
  let direct =
    contribution(finance_track.Cn, "cn_sse_direct", "SSE", requirement_ids())
  let mirror =
    contribution(
      finance_track.Cn,
      "cn_sse_via_cninfo",
      "SSE",
      requirement_ids(),
    )
  let assert Ok(assessment) =
    coverage.assess(policy, coverage_requirements(), [direct, mirror])

  coverage.coverage_basis_points(assessment) |> should.equal(10_000)
  coverage.source_groups(assessment) |> should.equal(["SSE"])
  coverage.assessment_readiness(assessment)
  |> should.equal(coverage.BelowThreshold)
}

pub fn critical_requirements_remain_mandatory_above_85_percent_test() {
  let assert Ok(policy) =
    coverage.operational_policy(finance_track.Hk, "market_picture", 1)
  let without_identity = requirement_ids() |> list.drop(1)
  let provider =
    contribution(finance_track.Hk, "hk_provider", "HKEX", without_identity)
  let assert Ok(assessment) =
    coverage.assess(policy, coverage_requirements(), [provider])

  coverage.coverage_basis_points(assessment) |> should.equal(9500)
  coverage.missing_critical_requirements(assessment)
  |> should.equal(["identity"])
  coverage.assessment_readiness(assessment)
  |> should.equal(coverage.BelowThreshold)
}

pub fn a_track_picture_cannot_average_away_a_weak_family_test() {
  let assert Ok(ready_policy) =
    coverage.operational_policy(finance_track.Cn, "identity", 1)
  let assert Ok(weak_policy) =
    coverage.operational_policy(finance_track.Cn, "disclosures", 1)
  let all =
    contribution(finance_track.Cn, "cn_identity", "SSE", requirement_ids())
  let weak =
    contribution(
      finance_track.Cn,
      "cn_disclosures",
      "CNINFO",
      list.take(requirement_ids(), 16),
    )
  let assert Ok(ready) =
    coverage.assess(ready_policy, coverage_requirements(), [all])
  let assert Ok(below) =
    coverage.assess(weak_policy, coverage_requirements(), [weak])
  let assert Ok(picture) = coverage.picture(finance_track.Cn, [ready, below])

  coverage.coverage_basis_points(ready) |> should.equal(10_000)
  coverage.coverage_basis_points(below) |> should.equal(8000)
  coverage.picture_readiness(picture)
  |> should.equal(coverage.IncompletePicture)
}

pub fn coverage_rejects_cross_track_and_unknown_requirements_test() {
  let assert Ok(policy) =
    coverage.operational_policy(finance_track.Cn, "market_picture", 1)
  let hk = contribution(finance_track.Hk, "hk_hkex", "HKEX", ["identity"])
  coverage.assess(policy, coverage_requirements(), [hk])
  |> should.equal(Error(coverage.ContributionTrackMismatch("hk_hkex")))

  let unknown =
    contribution(finance_track.Cn, "cn_vendor", "vendor", ["invented"])
  coverage.assess(policy, coverage_requirements(), [unknown])
  |> should.equal(Error(coverage.UnknownRequirement("cn_vendor", "invented")))
}

pub fn credibility_is_an_auditable_maturity_score_not_a_truth_probability_test() {
  let criteria = [
    credibility_criterion(
      "official_origin",
      credibility.Critical,
      credibility.Verified,
    ),
    credibility_criterion(
      "exact_identity",
      credibility.Critical,
      credibility.Verified,
    ),
    credibility_criterion(
      "raw_receipt",
      credibility.Critical,
      credibility.Verified,
    ),
    credibility_criterion(
      "semantic_decoder",
      credibility.Critical,
      credibility.Partial,
    ),
    credibility_criterion(
      "independent_check",
      credibility.Standard,
      credibility.Missing,
    ),
  ]
  let assert Ok(assessment) =
    credibility.operational_assessment(
      finance_track.Cn,
      "cn_authority_stack",
      criteria,
    )

  credibility.score_basis_points(assessment) |> should.equal(7000)
  credibility.score_percentage(assessment) |> should.equal(70)
  credibility.critical_gaps(assessment)
  |> should.equal(["semantic_decoder"])
  credibility.readiness(assessment)
  |> should.equal(credibility.LimitedCredibility)
}

pub fn credibility_rejects_duplicate_criteria_test() {
  let first =
    credibility_criterion(
      "official_origin",
      credibility.Critical,
      credibility.Verified,
    )
  credibility.operational_assessment(finance_track.Hk, "hk_authority_stack", [
    first,
    first,
  ])
  |> should.equal(Error(credibility.DuplicateCriterion("official_origin")))
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

fn requirement_ids() -> List(String) {
  [
    "identity",
    "track_venue",
    "currency_unit",
    "as_of_time",
    "source_provenance",
    "entitlement",
    "adjustment_basis",
    "price_history",
    "volume_history",
    "corporate_actions",
    "issuer_disclosures",
    "statement_facts",
    "regulatory_notices",
    "calendar_rules",
    "market_structure",
    "company_news",
    "macro_context",
    "analyst_estimates",
    "social_sentiment",
    "peer_classification",
  ]
}

fn coverage_requirements() -> List(coverage.Requirement) {
  requirement_ids()
  |> list.map(fn(id) {
    let importance = case id {
      "identity"
      | "track_venue"
      | "currency_unit"
      | "as_of_time"
      | "source_provenance"
      | "entitlement"
      | "adjustment_basis" -> coverage.Critical
      _ -> coverage.Standard
    }
    let assert Ok(value) = coverage.requirement(id, importance)
    value
  })
}

fn contribution(
  track: finance_track.Track,
  channel_id: String,
  source_group: String,
  covered_requirements: List(String),
) -> coverage.Contribution {
  let assert Ok(value) =
    coverage.contribution(track, channel_id, source_group, covered_requirements)
  value
}

fn credibility_criterion(
  id: String,
  importance: credibility.Importance,
  level: credibility.Level,
) -> credibility.Criterion {
  let assert Ok(value) =
    credibility.criterion(id, importance, level, "deterministic test evidence")
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
