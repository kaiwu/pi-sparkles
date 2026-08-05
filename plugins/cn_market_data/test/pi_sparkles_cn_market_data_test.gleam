import finance_eastmoney/query
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn provider_market_names_remain_cn_scoped_test() {
  query.market_name(query.CnSse) |> should.equal("cn_sse")
  query.market_name(query.CnSzse) |> should.equal("cn_szse")
  query.market_name(query.CnBse) |> should.equal("cn_bse")
}
