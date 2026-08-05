import finance_market_authorities/authority
import finance_track
import finance_track_capabilities/capability
import gleam/list
import gleeunit
import gleeunit/should
import pi_sparkles_hk_setup/authorities

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn provider_policy_remains_hk_owned_test() {
  capability.provider_health(finance_track.Hk, "unapproved", [], [
    "cn_stock_rules",
  ])
  |> fn(result) {
    let assert Ok(value) = result
    value.state
  }
  |> should.equal(capability.Unknown)
}

pub fn official_authority_registry_is_hk_scoped_and_separates_feeds_test() {
  let values = authorities.all()
  values |> list.length |> should.equal(7)
  values
  |> list.all(fn(value) { authority.track(value) == finance_track.Hk })
  |> should.be_true

  let assert Ok(hkexnews) =
    list.find(values, fn(value) { authority.id(value) == "hk_hkexnews" })
  authority.roles(hkexnews)
  |> should.equal([authority.IssuerDisclosureRepository])
  authority.access(hkexnews)
  |> should.equal(authority.PublicSearchAccessUnreviewed)

  let assert Ok(iis) =
    list.find(values, fn(value) { authority.id(value) == "hk_hkex_iis" })
  authority.access(iis) |> should.equal(authority.ProductionContractRequired)
  authority.redistribution(iis)
  |> should.equal(authority.ContractControlled)
}
