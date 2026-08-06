import finance_core/currency
import finance_core/decimal
import finance_core/observation
import finance_core/source
import finance_core/time
import finance_quote
import gleam/option.{None}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_quote_observation_preserves_source_facts_test() {
  let value = quote("189.1000", "7", "189.1200", "4")
  let assert Ok(source_ref) =
    source.new(
      "alpaca",
      "https://data.alpaca.markets/v2/stocks/quotes/latest?symbols=AAPL&feed=iex&currency=USD",
      source.LicensedVendor,
    )
  let assert Ok(zone) = time.timezone("America/New_York")
  let assert Ok(observed) =
    finance_quote.observe(
      value,
      retrieved_at: instant(1_800_000_000_000),
      timezone: zone,
      source: source_ref,
      expected_provider: "alpaca",
    )
  finance_quote.raw(finance_quote.price(finance_quote.bid(observed.value)))
  |> should.equal("189.1000")
  finance_quote.normalized(
    finance_quote.price(finance_quote.ask(observed.value)),
  )
  |> decimal.to_string
  |> should.equal("189.12")
  observed.freshness |> should.equal(observation.UnknownFreshness)
  observed.entitlement |> should.equal(observation.UnknownEntitlement)
  observed.adjustment |> should.equal(None)
  observed.session |> should.equal(None)
}

pub fn negative_values_fail_and_crossed_quotes_are_retained_test() {
  finance_quote.side("V", exact("-1"), exact("1"))
  |> should.equal(Error(finance_quote.NegativePrice))
  finance_quote.side("V", exact("1"), exact("-1"))
  |> should.equal(Error(finance_quote.NegativeSize))
  quote("190", "1", "189", "1")
  |> finance_quote.bid
  |> finance_quote.price
  |> finance_quote.raw
  |> should.equal("190")
}

pub fn provider_mismatch_and_future_quote_fail_closed_test() {
  let value = quote("189.10", "7", "189.12", "4")
  let assert Ok(source_ref) =
    source.new("other", "https://example.test/quote", source.LicensedVendor)
  let assert Ok(zone) = time.timezone("America/New_York")
  finance_quote.observe(
    value,
    retrieved_at: instant(1_700_000_000_000),
    timezone: zone,
    source: source_ref,
    expected_provider: "alpaca",
  )
  |> should.equal(
    Error(finance_quote.SourceProviderMismatch("alpaca", "other")),
  )

  let assert Ok(alpaca) =
    source.new("alpaca", "https://example.test/quote", source.LicensedVendor)
  finance_quote.observe(
    value,
    retrieved_at: instant(1000),
    timezone: zone,
    source: alpaca,
    expected_provider: "alpaca",
  )
  |> should.equal(Error(finance_quote.RetrievalBeforeQuote))
}

fn quote(bid_price, bid_size, ask_price, ask_size) -> finance_quote.Quote {
  let assert Ok(usd) = currency.from_code("USD")
  let assert Ok(bid) =
    finance_quote.side("V", exact(bid_price), exact(bid_size))
  let assert Ok(ask) =
    finance_quote.side("V", exact(ask_price), exact(ask_size))
  let assert Ok(value) =
    finance_quote.quote(
      "2024-08-06T19:59:59.123456789Z",
      instant(1_722_974_399_123),
      usd,
      bid,
      ask,
      ["R"],
      "C",
      finance_quote.ProviderReportedSize,
    )
  value
}

fn exact(value: String) -> finance_quote.ExactValue {
  let assert Ok(parsed) = finance_quote.exact(value)
  parsed
}

fn instant(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}
