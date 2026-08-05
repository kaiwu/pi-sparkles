import finance_core/time
import finance_track
import finance_track/context
import finance_track_capabilities
import finance_track_capabilities/capability
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_track_capabilities.status()
  |> should.equal(finance_track_capabilities.Experimental)
}

pub fn sibling_or_us_tools_cannot_satisfy_cn_capabilities_test() {
  let specs = [
    capability.RequiresTool(
      "identity",
      "cn_stock_symbols",
      "provider-backed mainland identity",
    ),
  ]
  let assert Ok(report) =
    capability.inspect(finance_track.Cn, context(finance_track.Cn), specs, [
      "hk_stock_symbols",
      "sec_company_search",
    ])
  report.capabilities
  |> should.equal([
    capability.Capability(
      "identity",
      capability.MissingDependency,
      "provider-backed mainland identity; required active tool is not installed: cn_stock_symbols",
      Some("cn_stock_symbols"),
    ),
  ])
}

pub fn wrong_track_requirement_is_a_policy_error_test() {
  capability.inspect(
    finance_track.Hk,
    context(finance_track.Hk),
    [capability.RequiresTool("rules", "cn_stock_rules", "wrong track")],
    ["cn_stock_rules"],
  )
  |> should.equal(Error(capability.WrongTrackTool("hk_", "cn_stock_rules")))
}

pub fn unknown_provider_never_claims_health_test() {
  capability.provider_health(finance_track.Cn, "unapproved", [], [])
  |> should.equal(
    Ok(capability.Capability(
      "unapproved",
      capability.Unknown,
      "no provider health contract is approved for this track",
      None,
    )),
  )
}

fn context(track: finance_track.Track) -> context.Context {
  let timezone_name = case track {
    finance_track.Cn -> "Asia/Shanghai"
    finance_track.Hk -> "Asia/Hong_Kong"
    finance_track.Us -> "America/New_York"
  }
  let assert Ok(zone) = time.timezone(timezone_name)
  let assert Ok(value) =
    context.new(
      track: track,
      market_scope: finance_track.name(track) <> "_setup",
      venue_mic: None,
      board: None,
      timezone: Some(zone),
      source_language: "en",
      providers: ["setup policy"],
      entitlement: "configuration_only",
      limitations: [],
    )
  value
}
