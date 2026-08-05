import finance_track
import gleeunit
import gleeunit/should
import pi_sparkles_finance_track_status/readiness
import pi_sparkles_finance_track_status/state

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn switching_is_explicit_and_idempotent_test() {
  let initial = state.new(finance_track.Us)
  let #(cn, first) = state.switch(initial, to: finance_track.Cn)
  let #(same, second) = state.switch(cn, to: finance_track.Cn)

  first |> should.equal(state.Switched(finance_track.Us, finance_track.Cn))
  second |> should.equal(state.Unchanged(finance_track.Cn))
  state.active_track(same) |> should.equal(finance_track.Cn)
}

pub fn readiness_receipts_expose_current_track_gaps_test() {
  let cn =
    readiness.inspect(finance_track.Cn, [
      "cn_authorities",
      "cn_security_search",
      "cn_market_calendar",
      "cn_trading_rules",
      "cn_disclosure_search",
      "cn_stock_quote",
      "cn_stock_history",
      "cn_financial_statement",
      "cn_stock_fundamental",
      "cn_stock_fundamental_metric",
    ])
  let hk =
    readiness.inspect(finance_track.Hk, [
      "hk_capabilities",
      "hk_security_search",
      "hk_market_calendar",
      "hk_trading_rules",
      "hk_disclosure_search",
      "hk_stock_quote",
      "hk_stock_history",
      "hk_financial_statement",
      "hk_stock_fundamental",
      "hk_stock_fundamental_metric",
    ])
  let us =
    readiness.inspect(finance_track.Us, [
      "finance_capabilities",
      "security_resolve",
      "sec_company_submissions",
      "sec_xbrl_facts",
      "stock_fundamental",
      "stock_fundamental_metric",
    ])

  readiness.source_percentage(cn) |> should.equal(65)
  readiness.feature_percentage(cn) |> should.equal(100)
  readiness.source_percentage(hk) |> should.equal(70)
  readiness.feature_percentage(hk) |> should.equal(100)
  readiness.source_percentage(us) |> should.equal(80)
  readiness.feature_percentage(us) |> should.equal(70)
}

pub fn sibling_track_tools_cannot_inflate_feature_coverage_test() {
  let cn =
    readiness.inspect(finance_track.Cn, [
      "finance_capabilities",
      "security_resolve",
      "sec_company_submissions",
      "sec_xbrl_facts",
      "stock_fundamental",
      "stock_fundamental_metric",
    ])

  readiness.feature_percentage(cn) |> should.equal(10)
  readiness.feature_gaps(cn)
  |> should.equal([
    "source_registry",
    "security_identity",
    "market_calendar",
    "effective_rules",
    "quotes_history",
    "disclosure_discovery",
    "raw_fundamentals",
    "normalized_fundamentals",
    "reproducible_derivations",
  ])
}
