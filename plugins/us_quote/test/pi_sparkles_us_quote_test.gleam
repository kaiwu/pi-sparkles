import finance_core/time
import finance_market_alpaca/query
import finance_market_alpaca/quotes
import finance_quote
import gleeunit
import gleeunit/should
import pi_sparkles_us_quote/normalization

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn alpaca_latest_quote_normalizes_into_exact_observation_test() {
  let assert Ok(plan) = query.latest_quote("AAPL", query.Iex)
  let assert Ok(raw) = quotes.decode(fixture(), for: plan)
  let assert Ok(observed) =
    normalization.quote(plan, raw, instant(1_800_000_000_000))
  finance_quote.raw(finance_quote.price(finance_quote.bid(observed.value)))
  |> should.equal("189.1000")
  finance_quote.raw(finance_quote.size(finance_quote.ask(observed.value)))
  |> should.equal("4")
  finance_quote.conditions(observed.value) |> should.equal(["R"])
  finance_quote.tape(observed.value) |> should.equal("C")
}

fn instant(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}

fn fixture() -> String {
  "{\"quotes\":{\"AAPL\":{\"ap\":189.1200,\"as\":4,\"ax\":\"V\",\"bp\":189.1000,\"bs\":7,\"bx\":\"V\",\"c\":[\"R\"],\"t\":\"2024-08-06T19:59:59.123456789Z\",\"z\":\"C\"}}}"
}
