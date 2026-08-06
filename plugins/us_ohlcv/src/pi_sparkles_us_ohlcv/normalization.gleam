import finance_core/adjustment
import finance_core/currency
import finance_core/market
import finance_core/source
import finance_core/time.{type Instant}
import finance_market_alpaca/bars as alpaca_bars
import finance_market_alpaca/query.{type DailyBarsQuery}
import finance_ohlcv
import gleam/list
import gleam/option.{Some}
import gleam/result

pub type NormalizationError {
  InvalidSource(source.SourceError)
  InvalidOpen(index: Int)
  InvalidHigh(index: Int)
  InvalidLow(index: Int)
  InvalidClose(index: Int)
  InvalidVolume(index: Int)
  InvalidTradeCount(index: Int)
  InvalidVwap(index: Int)
  InvalidBar(index: Int, reason: finance_ohlcv.BarError)
  InvalidBatch(finance_ohlcv.BatchError)
}

pub fn batch(
  plan: DailyBarsQuery,
  values: List(alpaca_bars.RawBar),
  retrieved_at: Instant,
  pagination: finance_ohlcv.Pagination,
) -> Result(finance_ohlcv.Batch, NormalizationError) {
  use normalized <- result.try(normalize_bars(values, 0, []))
  use source_ref <- result.try(
    source.new("alpaca", source_reference(plan), source.LicensedVendor)
    |> result.map_error(InvalidSource),
  )
  let assert Ok(zone) = time.timezone("America/New_York")
  let assert Ok(usd) = currency.from_code("USD")
  let assert Ok(provider_day) =
    market.other_session("alpaca_1day_provider_aggregation")
  finance_ohlcv.batch(
    normalized,
    retrieved_at: retrieved_at,
    timezone: zone,
    currency: usd,
    volume_unit: finance_ohlcv.Shares,
    adjustment: adjustment.Raw,
    session: provider_day,
    source: source_ref,
    expected_provider: "alpaca",
    pagination: pagination,
    calendar: finance_ohlcv.CalendarNotAssessed(
      "reviewed_us_calendar_and_status_source_not_composed",
    ),
  )
  |> result.map_error(InvalidBatch)
}

fn normalize_bars(
  values: List(alpaca_bars.RawBar),
  index: Int,
  reversed: List(finance_ohlcv.Bar),
) -> Result(List(finance_ohlcv.Bar), NormalizationError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use open <- result.try(
        finance_ohlcv.exact(alpaca_bars.open(value))
        |> result.map_error(fn(_) { InvalidOpen(index) }),
      )
      use high <- result.try(
        finance_ohlcv.exact(alpaca_bars.high(value))
        |> result.map_error(fn(_) { InvalidHigh(index) }),
      )
      use low <- result.try(
        finance_ohlcv.exact(alpaca_bars.low(value))
        |> result.map_error(fn(_) { InvalidLow(index) }),
      )
      use close <- result.try(
        finance_ohlcv.exact(alpaca_bars.close(value))
        |> result.map_error(fn(_) { InvalidClose(index) }),
      )
      use volume <- result.try(
        finance_ohlcv.exact(alpaca_bars.volume(value))
        |> result.map_error(fn(_) { InvalidVolume(index) }),
      )
      use trade_count <- result.try(
        finance_ohlcv.exact_count(alpaca_bars.trade_count(value))
        |> result.map_error(fn(_) { InvalidTradeCount(index) }),
      )
      use vwap <- result.try(
        finance_ohlcv.exact(alpaca_bars.vwap(value))
        |> result.map_error(fn(_) { InvalidVwap(index) }),
      )
      use normalized <- result.try(
        finance_ohlcv.bar(
          alpaca_bars.timestamp(value),
          alpaca_bars.at(value),
          alpaca_bars.session_date(value),
          open,
          high,
          low,
          close,
          volume,
          Some(trade_count),
          Some(vwap),
        )
        |> result.map_error(fn(reason) { InvalidBar(index, reason) }),
      )
      normalize_bars(rest, index + 1, [normalized, ..reversed])
    }
  }
}

fn source_reference(plan: DailyBarsQuery) -> String {
  "https://data.alpaca.markets/v2/stocks/bars?symbols="
  <> query.symbol(plan)
  <> "&timeframe=1Day&start="
  <> query.date_text(query.start_date(plan))
  <> "&end="
  <> query.date_text(query.end_date(plan))
  <> "&adjustment=raw&feed="
  <> query.feed_name(query.feed(plan))
  <> "&currency=USD&sort=asc&asof="
  <> query.date_text(query.as_of_date(plan))
}
