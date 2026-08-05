import finance_eastmoney/query
import finance_track
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn provider_market_remains_hk_scoped_test() {
  query.quote(finance_track.Hk, query.Hk, "00700") |> should.be_ok
  query.quote(finance_track.Cn, query.Hk, "00700") |> should.be_error
}
