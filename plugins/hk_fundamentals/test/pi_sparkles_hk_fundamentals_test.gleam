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
      finance_track.Hk,
      fundamentals.NetIncomeAttributableToParent,
    )
  value.accepted_line_codes |> should.equal(["004025002"])
  value.accepted_labels |> should.equal(["股东应占溢利"])
}
