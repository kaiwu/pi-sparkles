import finance_market_authorities/authority
import finance_track
import finance_track_capabilities/capability
import gleam/list
import gleeunit
import gleeunit/should
import pi_sparkles_cn_setup/authorities

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn provider_policy_remains_cn_owned_test() {
  capability.provider_health(finance_track.Cn, "unapproved", [], [
    "sec_company_search",
  ])
  |> fn(result) {
    let assert Ok(value) = result
    value.state
  }
  |> should.equal(capability.Unknown)
}

pub fn official_authority_registry_is_cn_scoped_and_operationally_honest_test() {
  let values = authorities.all()
  values |> list.length |> should.equal(7)
  values
  |> list.all(fn(value) { authority.track(value) == finance_track.Cn })
  |> should.be_true
  let assert Ok(csrc) =
    list.find(values, fn(value) { authority.id(value) == "cn_csrc" })
  authority.roles(csrc) |> should.equal([authority.SecuritiesRegulator])
  authority.access(csrc) |> should.equal(authority.VerifiedReference)

  let assert Ok(cninfo) =
    list.find(values, fn(value) { authority.id(value) == "cn_cninfo" })
  authority.access(cninfo)
  |> should.equal(authority.PublicSearchAccessUnreviewed)
  authority.redistribution(cninfo)
  |> should.equal(authority.UnreviewedRedistribution)
}
