import gleam/list
import gleeunit
import gleeunit/should
import pi_sparkles_finance_setup/capability

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn valid_defaults_and_active_tools_are_reported_test() {
  let report =
    capability.inspect("usd", "America/New_York", [
      "finance_validate_evidence",
      "security_resolve",
    ])
  report.configuration_valid |> should.be_true
  report.currency |> should.equal("USD")
  report.capabilities |> list.length |> should.equal(5)
}

pub fn invalid_defaults_are_data_not_panics_test() {
  capability.inspect("US", "local", [])
  |> fn(report) { report.configuration_valid }
  |> should.be_false
}

pub fn provider_health_never_claims_an_unchecked_connection_test() {
  capability.provider_health("openfigi", [])
  |> fn(value) { value.state }
  |> should.equal(capability.MissingDependency)

  capability.provider_health("alpaca", ["us_stock_quote"])
  |> fn(value) { value.state }
  |> should.equal(capability.Available)
}
