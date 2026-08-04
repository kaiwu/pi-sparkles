import finance_core/identifier
import finance_openfigi/response
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import pi_sparkles_finance_symbols/symbols

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn no_candidates_is_an_explicit_no_match_test() {
  symbols.resolve([])
  |> should.equal(identifier.NoMatch)
}

pub fn one_candidate_is_unique_test() {
  let value = candidate("BBG000000001", Some("XYZ"))
  symbols.resolve([value])
  |> should.equal(identifier.Unique(value))
}

pub fn ambiguity_is_stable_independent_of_provider_order_test() {
  let first = candidate("BBG000000002", Some("XYZ"))
  let second = candidate("BBG000000001", Some("XYZ"))
  symbols.resolve([first, second])
  |> should.equal(identifier.Ambiguous(second, first, []))
}

pub fn candidate_label_preserves_provider_unknowns_test() {
  response.Candidate(
    figi: "BBG000000001",
    name: None,
    ticker: None,
    exchange_code: None,
    security_type: None,
    market_sector: None,
    composite_figi: None,
    share_class_figi: None,
  )
  |> symbols.candidate_label
  |> should.equal(
    "ticker unavailable | name unavailable | FIGI BBG000000001 | exchange unavailable | type unavailable",
  )
}

fn candidate(figi: String, ticker: Option(String)) -> response.Candidate {
  response.Candidate(
    figi:,
    name: Some("Example"),
    ticker:,
    exchange_code: Some("US"),
    security_type: Some("Common Stock"),
    market_sector: Some("Equity"),
    composite_figi: None,
    share_class_figi: None,
  )
}
