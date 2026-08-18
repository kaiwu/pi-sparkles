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
  let assert finance_quote.AvailableSide(bid) =
    finance_quote.snapshot_bid(observed.value)
  let assert finance_quote.AvailableSide(ask) =
    finance_quote.snapshot_ask(observed.value)
  finance_quote.raw(finance_quote.price(bid))
  |> should.equal("189.1000")
  finance_quote.raw(finance_quote.size(ask))
  |> should.equal("4")
  finance_quote.snapshot_conditions(observed.value) |> should.equal(["R"])
  finance_quote.snapshot_tape(observed.value) |> should.equal("C")
}

pub fn alpaca_no_ask_sentinel_remains_unavailable_test() {
  let assert Ok(plan) = query.latest_quote("AAPL", query.Iex)
  let assert Ok(raw) = quotes.decode(no_ask_fixture(), for: plan)
  let assert Ok(observed) =
    normalization.quote(plan, raw, instant(1_800_000_000_000))
  let assert finance_quote.AvailableSide(bid) =
    finance_quote.snapshot_bid(observed.value)
  finance_quote.raw(finance_quote.price(bid)) |> should.equal("290.54")
  let assert finance_quote.UnavailableSide(exchange, price, size) =
    finance_quote.snapshot_ask(observed.value)
  exchange |> should.equal(" ")
  finance_quote.raw(price) |> should.equal("0")
  finance_quote.raw(size) |> should.equal("0")
}

fn instant(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}

fn fixture() -> String {
  "{\"quotes\":{\"AAPL\":{\"ap\":189.1200,\"as\":4,\"ax\":\"V\",\"bp\":189.1000,\"bs\":7,\"bx\":\"V\",\"c\":[\"R\"],\"t\":\"2024-08-06T19:59:59.123456789Z\",\"z\":\"C\"}}}"
}

fn no_ask_fixture() -> String {
  "{\"quotes\":{\"AAPL\":{\"ap\":0,\"as\":0,\"ax\":\" \",\"bp\":290.54,\"bs\":40,\"bx\":\"V\",\"c\":[\"R\"],\"t\":\"2026-08-17T20:00:02.436902433Z\",\"z\":\"C\"}}}"
}
