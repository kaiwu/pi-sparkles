import finance_market_authorities
import finance_market_authorities/authority
import finance_track
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_market_authorities.status()
  |> should.equal(finance_market_authorities.Experimental)
}

pub fn authority_keeps_official_ownership_separate_from_access_test() {
  let assert Ok(value) = valid_authority()
  authority.track(value) |> should.equal(finance_track.Cn)
  authority.access(value)
  |> should.equal(authority.PublicSearchAccessUnreviewed)
  authority.redistribution(value)
  |> should.equal(authority.UnreviewedRedistribution)
}

pub fn cross_track_id_and_unsafe_url_fail_closed_test() {
  authority.new(
    track: finance_track.Cn,
    id: "hk_wrong",
    name: "Wrong",
    roles: [authority.SecuritiesRegulator],
    official_url: "https://example.test",
    scope: "test",
    access: authority.VerifiedReference,
    redistribution: authority.ReferenceLinkOnly,
    limitations: [],
  )
  |> should.equal(Error(authority.WrongTrackId("cn_", "hk_wrong")))

  authority.new(
    track: finance_track.Cn,
    id: "cn_unsafe",
    name: "Unsafe",
    roles: [authority.SecuritiesRegulator],
    official_url: "http://example.test",
    scope: "test",
    access: authority.VerifiedReference,
    redistribution: authority.ReferenceLinkOnly,
    limitations: [],
  )
  |> should.equal(Error(authority.InvalidOfficialUrl))
}

pub fn duplicate_roles_and_limitations_fail_closed_test() {
  authority.new(
    track: finance_track.Cn,
    id: "cn_duplicate",
    name: "Duplicate",
    roles: [authority.SecuritiesRegulator, authority.SecuritiesRegulator],
    official_url: "https://example.test",
    scope: "test",
    access: authority.VerifiedReference,
    redistribution: authority.ReferenceLinkOnly,
    limitations: [],
  )
  |> should.equal(Error(authority.DuplicateRole(authority.SecuritiesRegulator)))

  authority.new(
    track: finance_track.Cn,
    id: "cn_duplicate",
    name: "Duplicate",
    roles: [authority.SecuritiesRegulator],
    official_url: "https://example.test",
    scope: "test",
    access: authority.VerifiedReference,
    redistribution: authority.ReferenceLinkOnly,
    limitations: ["review", "review"],
  )
  |> should.equal(Error(authority.DuplicateLimitation("review")))
}

pub fn registry_rejects_mixed_tracks_and_duplicate_ids_test() {
  let assert Ok(cn) = valid_authority()
  let assert Ok(hk) =
    authority.new(
      track: finance_track.Hk,
      id: "hk_exchange",
      name: "HK Exchange",
      roles: [authority.IssuerDisclosureRepository],
      official_url: "https://example.test/hk",
      scope: "synthetic test authority",
      access: authority.PublicSearchAccessUnreviewed,
      redistribution: authority.UnreviewedRedistribution,
      limitations: [],
    )

  authority.registry(finance_track.Cn, [cn, hk])
  |> should.equal(
    Error(authority.AuthorityTrackMismatch(
      "hk_exchange",
      finance_track.Cn,
      finance_track.Hk,
    )),
  )
  authority.registry(finance_track.Cn, [cn, cn])
  |> should.equal(Error(authority.DuplicateAuthority("cn_exchange")))
  authority.registry(finance_track.Cn, [])
  |> should.equal(Error(authority.EmptyRegistry))
}

fn valid_authority() {
  authority.new(
    track: finance_track.Cn,
    id: "cn_exchange",
    name: "CN Exchange",
    roles: [authority.IssuerDisclosureRepository],
    official_url: "https://example.test",
    scope: "synthetic test authority",
    access: authority.PublicSearchAccessUnreviewed,
    redistribution: authority.UnreviewedRedistribution,
    limitations: ["automation_not_approved"],
  )
}
