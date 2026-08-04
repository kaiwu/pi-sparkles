import finance_core/decimal.{type Decimal}
import finance_core/observation.{type MissingReason}
import finance_series/series.{type Datum}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt, Lt}

pub type Trade {
  Trade(price: Decimal, quantity: Decimal)
}

pub type Bar {
  Bar(
    open: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    volume: Decimal,
    observations: Int,
  )
}

pub type MissingPolicy {
  PropagateMissing
  SkipMissing
  RejectMissing
}

pub type BarError {
  EmptyBucket
  MissingTrade(reason: MissingReason)
  NegativeQuantity
}

pub fn aggregate(
  values: List(Datum(Trade)),
  missing missing_policy: MissingPolicy,
) -> Result(Datum(Bar), BarError) {
  collect(values, missing_policy, None, [])
}

fn collect(
  values: List(Datum(Trade)),
  policy: MissingPolicy,
  first_missing: Option(MissingReason),
  trades_reversed: List(Trade),
) -> Result(Datum(Bar), BarError) {
  case values {
    [] -> finish(policy, first_missing, trades_reversed)
    [series.Missing(reason), ..rest] ->
      case policy {
        RejectMissing -> Error(MissingTrade(reason))
        _ ->
          collect(
            rest,
            policy,
            case first_missing {
              None -> Some(reason)
              existing -> existing
            },
            trades_reversed,
          )
      }
    [series.Present(trade), ..rest] ->
      case decimal.compare(trade.quantity, decimal.zero()) == Lt {
        True -> Error(NegativeQuantity)
        False ->
          collect(rest, policy, first_missing, [trade, ..trades_reversed])
      }
  }
}

fn finish(
  policy: MissingPolicy,
  missing: Option(MissingReason),
  reversed: List(Trade),
) -> Result(Datum(Bar), BarError) {
  case policy, missing, list.reverse(reversed) {
    PropagateMissing, Some(reason), _ -> Ok(series.Missing(reason))
    _, Some(reason), [] -> Ok(series.Missing(reason))
    _, None, [] -> Error(EmptyBucket)
    _, _, [first, ..rest] -> {
      let #(high, low, close, volume, count) =
        list.fold(
          rest,
          #(first.price, first.price, first.price, first.quantity, 1),
          fn(state, trade) {
            let #(high, low, _, volume, count) = state
            #(
              case decimal.compare(trade.price, high) {
                Gt -> trade.price
                _ -> high
              },
              case decimal.compare(trade.price, low) {
                Lt -> trade.price
                _ -> low
              },
              trade.price,
              decimal.add(volume, trade.quantity),
              count + 1,
            )
          },
        )
      Ok(series.Present(Bar(first.price, high, low, close, volume, count)))
    }
  }
}
