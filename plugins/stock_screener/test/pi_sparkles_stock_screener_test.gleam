import finance_core/time
import finance_market_alpaca/assets
import finance_market_alpaca/query
import finance_provenance/identity
import gleam/json
import gleam/option.{None}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_screener/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn input_keeps_every_provider_filter_caller_selected_test() {
  let assert Ok(input) = domain.input("live", "all", "NYSE", 200)
  let plan = domain.plan(input)
  query.asset_environment(plan) |> should.equal(query.Live)
  query.asset_status(plan) |> should.equal(query.AllStatuses)
  query.asset_exchange(plan) |> should.equal(query.Nyse)
  query.maximum_assets(plan) |> should.equal(200)

  domain.input("automatic", "all", "NYSE", 200)
  |> should.equal(Error(domain.InvalidEnvironment))
  domain.input("live", "eligible", "NYSE", 200)
  |> should.equal(Error(domain.InvalidStatus))
  domain.input("live", "all", "XNAS", 200)
  |> should.equal(Error(domain.InvalidExchange))
  domain.input("live", "all", "NYSE", 0)
  |> should.equal(Error(domain.InvalidMaximumAssets))
}

pub fn result_preserves_provider_rows_without_a_plugin_decision_test() {
  let assert Ok(input) = domain.input("paper", "active", "NASDAQ", 10)
  let plan = domain.plan(input)
  let assert Ok(snapshot) = assets.decode_snapshot(fixture(), for: plan)
  let encoded =
    domain.result_json(plan, snapshot, instant(1000), None, sha("a"), sha("b"))
    |> json.to_string
  encoded |> string.contains("provider_returned_row") |> should.be_true
  encoded |> string.contains("\"status\":\"inactive\"") |> should.be_true
  encoded |> string.contains("\"tradable\":false") |> should.be_true
  encoded |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  encoded |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
  encoded |> string.contains("\"rank\"") |> should.be_false
  encoded |> string.contains("\"qualified\"") |> should.be_false
  encoded |> string.contains("\"selected\"") |> should.be_false
}

fn fixture() -> String {
  "[{\"id\":\"asset-aapl\",\"class\":\"us_equity\",\"exchange\":\"NASDAQ\",\"symbol\":\"AAPL\",\"name\":\"Apple Inc. Common Stock\",\"status\":\"inactive\",\"tradable\":false,\"marginable\":true,\"shortable\":false,\"easy_to_borrow\":false,\"fractionable\":true,\"attributes\":[\"has_options\"]}]"
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}

fn sha(digit: String) -> identity.Sha256 {
  let assert Ok(value) = identity.sha256(string.repeat(digit, 64))
  value
}
