import finance_cache_contract as cache
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_finance_cache/domain

pub fn main() {
  gleeunit.main()
}

pub fn provider_filter_is_exact_and_bounded_test() {
  let entries = [
    fixture("a", "eastmoney"),
    fixture("b", "tushare"),
    fixture("c", "eastmoney"),
  ]
  domain.select(entries, Some("eastmoney"), 1)
  |> list.map(cache.provider)
  |> should.equal(["eastmoney"])
}

pub fn no_provider_filter_preserves_bounded_order_test() {
  let entries = [fixture("a", "eastmoney"), fixture("b", "tushare")]
  domain.select(entries, None, 2) |> should.equal(entries)
}

fn fixture(seed: String, provider: String) -> cache.Entry {
  let assert Ok(value) =
    cache.entry(
      string.repeat(seed, 64),
      provider,
      "https://example.com/data",
      string.repeat("d", 64),
      1000,
      2000,
      3000,
      2,
      "local_analysis",
      "provider_terms",
      "daily:000001.SZ",
      string.repeat("e", 64),
      "schema_validated",
      "{}",
    )
  value
}
