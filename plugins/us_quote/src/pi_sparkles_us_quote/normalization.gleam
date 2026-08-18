import finance_core/currency
import finance_core/observation.{type Observation}
import finance_core/source
import finance_core/time.{type Instant}
import finance_market_alpaca/query.{type LatestQuoteQuery}
import finance_market_alpaca/quotes as alpaca_quotes
import finance_quote
import gleam/result

pub type NormalizationError {
  InvalidBidPrice
  InvalidBidSize
  InvalidAskPrice
  InvalidAskSize
  InvalidBidSide(finance_quote.SideAvailabilityError)
  InvalidAskSide(finance_quote.SideAvailabilityError)
  InvalidQuote(finance_quote.QuoteError)
  InvalidSource(source.SourceError)
  InvalidObservation(finance_quote.ObservationError)
}

pub fn quote(
  plan: LatestQuoteQuery,
  value: alpaca_quotes.RawQuote,
  retrieved_at: Instant,
) -> Result(Observation(finance_quote.Snapshot), NormalizationError) {
  use bid_price <- result.try(
    finance_quote.exact(alpaca_quotes.bid_price(value))
    |> result.map_error(fn(_) { InvalidBidPrice }),
  )
  use bid_size <- result.try(
    finance_quote.exact(alpaca_quotes.bid_size(value))
    |> result.map_error(fn(_) { InvalidBidSize }),
  )
  use ask_price <- result.try(
    finance_quote.exact(alpaca_quotes.ask_price(value))
    |> result.map_error(fn(_) { InvalidAskPrice }),
  )
  use ask_size <- result.try(
    finance_quote.exact(alpaca_quotes.ask_size(value))
    |> result.map_error(fn(_) { InvalidAskSize }),
  )
  use bid <- result.try(
    finance_quote.side_availability(
      alpaca_quotes.bid_exchange(value),
      bid_price,
      bid_size,
    )
    |> result.map_error(InvalidBidSide),
  )
  use ask <- result.try(
    finance_quote.side_availability(
      alpaca_quotes.ask_exchange(value),
      ask_price,
      ask_size,
    )
    |> result.map_error(InvalidAskSide),
  )
  let assert Ok(usd) = currency.from_code("USD")
  use normalized <- result.try(
    finance_quote.snapshot(
      alpaca_quotes.timestamp(value),
      alpaca_quotes.at(value),
      usd,
      bid,
      ask,
      alpaca_quotes.conditions(value),
      alpaca_quotes.tape(value),
      finance_quote.ProviderReportedSize,
    )
    |> result.map_error(InvalidQuote),
  )
  use source_ref <- result.try(
    source.new("alpaca", source_reference(plan), source.LicensedVendor)
    |> result.map_error(InvalidSource),
  )
  let assert Ok(zone) = time.timezone("America/New_York")
  finance_quote.observe_snapshot(
    normalized,
    retrieved_at: retrieved_at,
    timezone: zone,
    source: source_ref,
    expected_provider: "alpaca",
  )
  |> result.map_error(InvalidObservation)
}

fn source_reference(plan: LatestQuoteQuery) -> String {
  "https://data.alpaca.markets/v2/stocks/quotes/latest?symbols="
  <> query.quote_symbol(plan)
  <> "&feed="
  <> query.feed_name(query.quote_feed(plan))
  <> "&currency=USD"
}
