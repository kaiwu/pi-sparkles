import finance_core/currency
import finance_core/time
import finance_eastmoney/history
import finance_eastmoney/query
import finance_ohlcv
import finance_track
import gleam/list
import gleeunit
import gleeunit/should
import pi_sparkles_hk_ohlcv/normalization

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_date_only_eastmoney_rows_keep_declared_hk_currency_test() {
  let assert Ok(plan) =
    query.history(
      finance_track.Hk,
      query.Hk,
      "00700",
      civil(2024, 8, 1),
      civil(2024, 8, 5),
      10,
    )
  let assert Ok(provider_value) = history.decode(fixture(), for: plan)
  let assert Ok(hkd) = currency.from_code("HKD")
  let assert Ok(retrieved) = time.instant(1_800_000_000_000)
  let assert Ok(batch) =
    normalization.batch(plan, provider_value, retrieved, hkd)
  finance_ohlcv.currency(batch) |> currency.code |> should.equal("HKD")
  finance_ohlcv.volume_unit(batch)
  |> should.equal(finance_ohlcv.UnknownVolumeUnit)
  finance_ohlcv.observations(batch) |> list.length |> should.equal(2)
  let assert [first, ..] = finance_ohlcv.observations(batch)
  finance_ohlcv.raw(finance_ohlcv.close(first.value))
  |> should.equal("372.400")
  finance_ohlcv.time_basis(first.value)
  |> should.equal(finance_ohlcv.SessionDateAnchor)
}

pub fn declared_hk_identity_is_explicit_test() {
  normalization.valid_identity("main", "ordinary_share") |> should.be_true
  normalization.valid_identity("gem", "depositary_receipt") |> should.be_true
  normalization.valid_identity("unknown", "ordinary_share")
  |> should.be_false
}

fn fixture() -> String {
  "{\"rc\":0,\"data\":{\"code\":\"00700\",\"name\":\"腾讯控股\",\"klines\":[\"2024-08-01,370.200,372.400,375.000,368.600,15432100,5743210000.00,1.72,0.59,2.20,0.25\",\"2024-08-02,372.400,368.800,373.600,367.000,17654300,6521000000.00,1.77,-0.97,-3.60,0.29\"]}}"
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
