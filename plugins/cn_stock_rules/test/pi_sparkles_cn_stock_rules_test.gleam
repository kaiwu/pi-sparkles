import finance_cn_rules/official
import finance_core/decimal
import finance_core/time
import gleeunit
import gleeunit/should
import pi_sparkles_cn_stock_rules/query

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_listing_context_selects_reviewed_profile_test() {
  let assert Ok(plan) =
    query.plan(
      "cn",
      "300750",
      "szse",
      "chinext",
      "a_share",
      "common_stock",
      "listed_normal",
      "established_normal_equity",
      "evidence:listing:300750",
      date(2026, 8, 11),
    )
  let assert Ok(profile) = query.run(plan)
  profile
  |> official.daily_price_limit
  |> decimal.to_string
  |> should.equal("0.2")
  query.identity_evidence_id(plan) |> should.equal("evidence:listing:300750")
}

pub fn exceptional_or_conflicting_context_fails_closed_test() {
  query.plan(
    "cn",
    "300750",
    "sse",
    "chinext",
    "a_share",
    "common_stock",
    "listed_normal",
    "established_normal_equity",
    "evidence",
    date(2026, 8, 11),
  )
  |> should.be_error
  query.plan(
    "cn",
    "300750",
    "szse",
    "chinext",
    "a_share",
    "common_stock",
    "st",
    "established_normal_equity",
    "evidence",
    date(2026, 8, 11),
  )
  |> should.equal(Error(query.UnsupportedStatus))
  query.plan(
    "cn",
    "300750",
    "szse",
    "chinext",
    "a_share",
    "common_stock",
    "listed_normal",
    "ipo_first_five",
    "evidence",
    date(2026, 8, 11),
  )
  |> should.equal(Error(query.UnsupportedRegime))
}

fn date(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
