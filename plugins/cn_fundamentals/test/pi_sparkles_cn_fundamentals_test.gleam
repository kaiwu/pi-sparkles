import finance_eastmoney/fundamentals
import finance_track
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn mapping_is_track_owned_and_attribution_explicit_test() {
  let value =
    fundamentals.mapping(
      finance_track.Cn,
      fundamentals.NetIncomeAttributableToParent,
    )
  value.accepted_line_codes |> should.equal(["PARENT_NETPROFIT"])
  fundamentals.metric_name(value.metric)
  |> should.equal("net_income_attributable_to_parent")
}
