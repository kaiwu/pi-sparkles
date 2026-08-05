import finance_core/currency
import finance_core/market
import finance_core/observation
import finance_core/source
import finance_core/time
import finance_evidence
import finance_evidence/compatibility
import finance_provenance/evidence
import finance_provenance/identity
import finance_track
import finance_track/context
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_evidence.status()
  |> should.equal(finance_evidence.Experimental)
}

pub fn compatible_same_track_observations_are_validated_test() {
  let inputs = [input(finance_track.Cn, 100, 100, observation.Reported, "a")]
  let assert Ok(validated) =
    compatibility.validate(inputs, under: strict_same_track())

  compatibility.inputs(validated) |> should.equal(inputs)
}

pub fn mixed_tracks_are_rejected_by_default_test() {
  let result =
    compatibility.validate(
      [
        input(finance_track.Cn, 100, 100, observation.Reported, "a"),
        input(finance_track.Hk, 100, 100, observation.Reported, "b"),
      ],
      under: strict_same_track(),
    )
  let assert Error(errors) = result
  errors
  |> list.any(fn(error) {
    case error {
      compatibility.TrackMismatch(1, finance_track.Cn, finance_track.Hk) -> True
      _ -> False
    }
  })
  |> should.be_true
}

pub fn explicit_cross_track_policy_retains_both_legs_test() {
  let inputs = [
    input(finance_track.Cn, 100, 100, observation.Reported, "a"),
    input(finance_track.Hk, 100, 100, observation.Restated, "b"),
  ]
  let policy =
    compatibility.Policy(
      track: compatibility.ExplicitCrossTrack,
      as_of: compatibility.ExactSameAsOf,
      quality: compatibility.ReportedOrRestated,
      intended_use: compatibility.InternalAnalysis,
      require_known_unit: True,
    )
  let assert Ok(validated) = compatibility.validate(inputs, under: policy)

  compatibility.inputs(validated) |> should.equal(inputs)
  compatibility.policy(validated) |> should.equal(policy)
}

pub fn explicit_cross_track_policy_cannot_mask_a_single_track_test() {
  let policy =
    compatibility.Policy(
      ..strict_same_track(),
      track: compatibility.ExplicitCrossTrack,
    )
  compatibility.validate(
    [input(finance_track.Cn, 100, 100, observation.Reported, "a")],
    under: policy,
  )
  |> should.equal(Error([compatibility.CrossTrackRequiresMultipleTracks]))
}

pub fn unit_quality_and_as_of_incompatibilities_accumulate_test() {
  let first = input(finance_track.Cn, 100, 100, observation.Reported, "a")
  let second =
    input(finance_track.Cn, 200, 200, observation.Estimated, "b")
    |> with_unit(market.Shares)
  let assert Error(errors) =
    compatibility.validate([first, second], under: strict_same_track())

  errors |> list.length |> should.equal(3)
}

pub fn time_travel_and_evidence_identity_are_rejected_test() {
  let base = input(finance_track.Us, 200, 200, observation.Reported, "a")
  let compatibility.Input(leg, item) = base
  let bad_observation =
    observation.Observation(
      ..leg.value,
      retrieved_at: instant(100),
      evidence_id: Some(identity.evidence_id_value(id("b"))),
    )
  let bad_evidence = evidence.Evidence(..item, retrieved_at: instant(100))
  let assert Error(errors) =
    compatibility.validate(
      [
        compatibility.Input(
          context.Leg(leg.context, bad_observation),
          bad_evidence,
        ),
      ],
      under: strict_same_track(),
    )

  errors |> list.length |> should.equal(3)
}

pub fn redistribution_fails_closed_for_unknown_rights_test() {
  let compatibility.Input(leg, item) =
    input(finance_track.Hk, 100, 100, observation.Reported, "a")
  let restricted =
    evidence.Evidence(
      ..item,
      licence: evidence.Licence("unknown", evidence.UnknownRedistribution, None),
    )
  let policy =
    compatibility.Policy(
      ..strict_same_track(),
      intended_use: compatibility.RedistributableOutput,
    )

  compatibility.validate([compatibility.Input(leg, restricted)], under: policy)
  |> should.equal(
    Error([
      compatibility.RedistributionRejected(0, evidence.UnknownRedistribution),
    ]),
  )
}

fn strict_same_track() -> compatibility.Policy {
  compatibility.Policy(
    track: compatibility.SameTrackOnly,
    as_of: compatibility.ExactSameAsOf,
    quality: compatibility.ReportedOrRestated,
    intended_use: compatibility.InternalAnalysis,
    require_known_unit: True,
  )
}

fn input(
  track: finance_track.Track,
  as_of: Int,
  retrieved_at: Int,
  quality: observation.Quality,
  character: String,
) -> compatibility.Input(Int) {
  let source = source_ref(character)
  let evidence_id = id(character)
  let observed =
    observation.Observation(
      value: 1,
      as_of: instant(as_of),
      retrieved_at: instant(retrieved_at),
      timezone: None,
      source: source,
      evidence_id: Some(identity.evidence_id_value(evidence_id)),
      freshness: observation.UnknownFreshness,
      entitlement: observation.UnknownEntitlement,
      quality: quality,
      unit: Some(market.Currency(currency("CNY"))),
      adjustment: None,
      session: None,
    )
  compatibility.Input(
    context.leg(track_context(track), observed),
    evidence.Evidence(
      id: evidence_id,
      source_fingerprint: fingerprint("f"),
      source: source,
      licence: evidence.Licence(
        "synthetic-test-data",
        evidence.PublicDomain,
        None,
      ),
      as_of: instant(as_of),
      retrieved_at: instant(retrieved_at),
      media_type: "application/json",
      byte_length: 1,
      content_hash: hash(character),
      parents: [],
      assumptions: [],
      availability: evidence.Available,
    ),
  )
}

fn with_unit(
  input: compatibility.Input(Int),
  unit: market.Unit,
) -> compatibility.Input(Int) {
  let compatibility.Input(leg, evidence) = input
  compatibility.Input(
    context.Leg(
      leg.context,
      observation.Observation(..leg.value, unit: Some(unit)),
    ),
    evidence,
  )
}

fn track_context(track: finance_track.Track) -> context.Context {
  let assert Ok(value) =
    context.new(
      track: track,
      market_scope: finance_track.name(track) <> "_synthetic_evidence",
      venue_mic: None,
      board: None,
      timezone: None,
      source_language: "en",
      providers: ["synthetic-provider"],
      entitlement: "synthetic",
      limitations: ["test_only"],
    )
  value
}

fn source_ref(character: String) -> source.SourceRef {
  let assert Ok(value) =
    source.new(
      provider: "synthetic-provider",
      reference: "fixture/" <> character,
      kind: source.Synthetic,
    )
  value
}

fn currency(code: String) -> currency.Currency {
  let assert Ok(value) = currency.from_code(code)
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}

fn id(character: String) -> identity.EvidenceId {
  character
  |> hash
  |> identity.evidence_id
}

fn fingerprint(character: String) -> identity.SourceFingerprint {
  character
  |> hash
  |> identity.source_fingerprint
}

fn hash(character: String) -> identity.Sha256 {
  let assert Ok(value) = identity.sha256(string.repeat(character, times: 64))
  value
}
