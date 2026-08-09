import finance_core/decimal.{type Decimal}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_day_workbench/decode.{type EventFilter}
import pi_sparkles_day_workbench/packet.{
  type DepthLevel, type Event, type Packet,
}

type Operand {
  Operand(event_id: String, name: String, lexeme: String)
}

type ValueResult {
  Calculated(
    value: Decimal,
    unit: String,
    formula: String,
    source_event_ids: List(String),
    operands: List(Operand),
  )
  Unperformed(reason: String, source_event_ids: List(String))
}

pub fn run(
  packet_value: Packet,
  calculation: String,
  window_start_unix_ms: Int,
  window_end_unix_ms: Int,
  scale: Int,
  rounding: String,
  filter: EventFilter,
) -> Result(Json, String) {
  use _ <- result.try(validate_request(
    calculation,
    window_start_unix_ms,
    window_end_unix_ms,
    scale,
    rounding,
    filter,
  ))
  let events =
    packet.calculation_events(packet_value)
    |> list.filter(fn(event) {
      packet.event_in_window(event, window_start_unix_ms, window_end_unix_ms)
      && filter_event(event, filter)
    })
    |> remove_cancelled_events(packet_value.events)
  let value = case packet_value.declared_complete, packet.issues(packet_value) {
    False, _ -> Unperformed("packet_declared_incomplete", [])
    True, [_first, ..] -> Unperformed("packet_integrity_issues_present", [])
    True, [] ->
      case corrected_sources(events, packet_value.events) {
        [] ->
          calculate(
            calculation,
            events,
            packet_value.currency,
            packet_value.size_unit,
            scale,
            rounding_mode(rounding),
          )
        ids ->
          Unperformed(
            "correction_values_require_explicit_replacement_events",
            ids,
          )
      }
  }
  Ok(result_json(
    packet_value,
    calculation,
    window_start_unix_ms,
    window_end_unix_ms,
    scale,
    rounding,
    filter,
    events,
    value,
  ))
}

fn validate_request(
  calculation: String,
  start: Int,
  finish: Int,
  scale: Int,
  rounding: String,
  filter: EventFilter,
) -> Result(Nil, String) {
  use _ <- result.try(
    case list.contains(supported_calculations(), calculation) {
      True -> Ok(Nil)
      False -> Error("unsupported intraday calculation")
    },
  )
  use _ <- result.try(case start <= finish {
    True -> Ok(Nil)
    False -> Error("calculation window start must not follow end")
  })
  use _ <- result.try(case scale >= 0 && scale <= 18 {
    True -> Ok(Nil)
    False -> Error("scale must be between 0 and 18")
  })
  use _ <- result.try(
    case
      list.contains(
        [
          "toward_zero",
          "away_from_zero",
          "half_up",
          "half_even",
        ],
        rounding,
      )
    {
      True -> Ok(Nil)
      False -> Error("unsupported rounding policy")
    },
  )
  let decode.EventFilter(_, _, conditions) = filter
  case
    list.length(conditions) <= packet.maximum_condition_codes,
    list.all(conditions, fn(value) {
      value != "" && string.byte_size(value) <= 200
    })
  {
    True, True -> Ok(Nil)
    False, _ -> Error("included condition code count exceeds 100")
    _, False -> Error("included condition codes must be 1-200 bytes")
  }
}

fn calculate(
  name: String,
  events: List(Event),
  currency: String,
  size_unit: String,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  case name {
    "quoted_spread" ->
      quote_binary(
        events,
        currency,
        "ask - bid",
        fn(bid, ask) { Ok(decimal.subtract(ask, bid)) },
        scale,
        rounding,
      )
    "quoted_spread_percent" ->
      quote_binary(
        events,
        "percent",
        "((ask - bid) / ((bid + ask) / 2)) * 100",
        fn(bid, ask) {
          let spread = decimal.subtract(ask, bid)
          use midpoint <- result.try(decimal.divide(
            decimal.add(bid, ask),
            by: decimal_from_int(2),
            scale: scale + 8,
            rounding: rounding,
          ))
          use ratio <- result.try(decimal.divide(
            spread,
            by: midpoint,
            scale: scale + 8,
            rounding: rounding,
          ))
          Ok(decimal.multiply(ratio, decimal_from_int(100)))
        },
        scale,
        rounding,
      )
    "midpoint" ->
      quote_binary(
        events,
        currency,
        "(bid + ask) / 2",
        fn(bid, ask) {
          decimal.divide(
            decimal.add(bid, ask),
            by: decimal_from_int(2),
            scale: scale,
            rounding: rounding,
          )
        },
        scale,
        rounding,
      )
    "displayed_bid_notional" ->
      quote_notional(
        events,
        currency <> "*" <> size_unit,
        True,
        scale,
        rounding,
      )
    "displayed_ask_notional" ->
      quote_notional(
        events,
        currency <> "*" <> size_unit,
        False,
        scale,
        rounding,
      )
    "quote_change" -> quote_change(events, currency, scale, rounding)
    "trade_change" -> trade_change(events, currency, scale, rounding)
    "opening_range" ->
      trade_extreme_difference(
        events,
        currency,
        "high(trade_price) - low(trade_price) over caller window",
        scale,
        rounding,
      )
    "session_high" -> trade_extreme(events, currency, True, scale, rounding)
    "session_low" -> trade_extreme(events, currency, False, scale, rounding)
    "cumulative_volume" -> trade_sum(events, size_unit, False, scale, rounding)
    "cumulative_turnover" ->
      trade_sum(events, currency <> "*" <> size_unit, True, scale, rounding)
    "vwap" -> vwap(events, currency, scale, rounding)
    "session_range_percent" -> session_range_percent(events, scale, rounding)
    "depth_imbalance" -> depth_imbalance(events, scale, rounding)
    "depth_weighted_bid" ->
      depth_weighted(events, currency, packet.Bid, scale, rounding)
    "depth_weighted_ask" ->
      depth_weighted(events, currency, packet.Ask, scale, rounding)
    _ -> Unperformed("unsupported_intraday_calculation", [])
  }
}

fn quote_binary(
  events: List(Event),
  unit: String,
  formula: String,
  operation: fn(Decimal, Decimal) -> Result(Decimal, decimal.ArithmeticError),
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  case latest_quote(events) {
    Error(reason) -> Unperformed(reason, [])
    Ok(#(event, bid_lexeme, _, ask_lexeme, _)) ->
      case decimal.parse(bid_lexeme), decimal.parse(ask_lexeme) {
        Ok(bid), Ok(ask) ->
          case operation(bid, ask) {
            Error(_) ->
              Unperformed("division_by_zero_or_invalid_scale", [
                packet.event_id(event),
              ])
            Ok(value) ->
              calculated(
                value,
                unit,
                formula,
                [packet.event_id(event)],
                [
                  Operand(packet.event_id(event), "bid", bid_lexeme),
                  Operand(packet.event_id(event), "ask", ask_lexeme),
                ],
                scale,
                rounding,
              )
          }
        _, _ ->
          Unperformed("quote_decimal_decode_failure", [packet.event_id(event)])
      }
  }
}

fn quote_notional(
  events: List(Event),
  unit: String,
  bid_side: Bool,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  case latest_quote(events) {
    Error(reason) -> Unperformed(reason, [])
    Ok(#(event, bid_price, bid_size, ask_price, ask_size)) -> {
      let #(price_name, size_name, price_lexeme, size_lexeme) = case bid_side {
        True -> #("bid_price", "bid_size", bid_price, bid_size)
        False -> #("ask_price", "ask_size", ask_price, ask_size)
      }
      case decimal.parse(price_lexeme), decimal.parse(size_lexeme) {
        Ok(price), Ok(size) ->
          calculated(
            decimal.multiply(price, size),
            unit,
            price_name <> " * " <> size_name,
            [packet.event_id(event)],
            [
              Operand(packet.event_id(event), price_name, price_lexeme),
              Operand(packet.event_id(event), size_name, size_lexeme),
            ],
            scale,
            rounding,
          )
        _, _ ->
          Unperformed("quote_decimal_decode_failure", [packet.event_id(event)])
      }
    }
  }
}

fn quote_change(
  events: List(Event),
  unit: String,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  let quotes = quote_events(events)
  case last_two(quotes) {
    Error(_) ->
      Unperformed(
        "at_least_two_quotes_required",
        list.map(quotes, packet.event_id),
      )
    Ok(#(prior, current)) ->
      case
        midpoint_of(prior, scale + 8, rounding),
        midpoint_of(current, scale + 8, rounding)
      {
        Ok(prior_value), Ok(current_value) ->
          calculated(
            decimal.subtract(current_value, prior_value),
            unit,
            "current_midpoint - prior_midpoint",
            [packet.event_id(prior), packet.event_id(current)],
            quote_operands(prior, "prior")
              |> list.append(quote_operands(current, "current")),
            scale,
            rounding,
          )
        _, _ ->
          Unperformed("quote_decimal_decode_failure", [
            packet.event_id(prior),
            packet.event_id(current),
          ])
      }
  }
}

fn trade_change(
  events: List(Event),
  unit: String,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  let trades = trade_events(events)
  case last_two(trades) {
    Error(_) ->
      Unperformed(
        "at_least_two_trades_required",
        list.map(trades, packet.event_id),
      )
    Ok(#(prior, current)) ->
      case trade_values(prior), trade_values(current) {
        Ok(#(prior_price, _, prior_price_lexeme, _)),
          Ok(#(current_price, _, current_price_lexeme, _))
        ->
          calculated(
            decimal.subtract(current_price, prior_price),
            unit,
            "current_trade_price - prior_trade_price",
            [packet.event_id(prior), packet.event_id(current)],
            [
              Operand(
                packet.event_id(prior),
                "prior_trade_price",
                prior_price_lexeme,
              ),
              Operand(
                packet.event_id(current),
                "current_trade_price",
                current_price_lexeme,
              ),
            ],
            scale,
            rounding,
          )
        _, _ ->
          Unperformed("trade_decimal_decode_failure", [
            packet.event_id(prior),
            packet.event_id(current),
          ])
      }
  }
}

fn trade_sum(
  events: List(Event),
  unit: String,
  turnover: Bool,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  let trades = trade_events(events)
  case parsed_trades(trades) {
    Error(reason) -> Unperformed(reason, list.map(trades, packet.event_id))
    Ok(values) -> {
      let value =
        values
        |> list.fold(decimal.zero(), fn(total, value) {
          let #(_, price, size, _, _) = value
          decimal.add(total, case turnover {
            True -> decimal.multiply(price, size)
            False -> size
          })
        })
      let formula = case turnover {
        True -> "sum(trade_price * trade_size) over caller window and filter"
        False -> "sum(trade_size) over caller window and filter"
      }
      calculated(
        value,
        unit,
        formula,
        list.map(trades, packet.event_id),
        trade_operands(values),
        scale,
        rounding,
      )
    }
  }
}

fn vwap(
  events: List(Event),
  unit: String,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  let trades = trade_events(events)
  case parsed_trades(trades) {
    Error(reason) -> Unperformed(reason, list.map(trades, packet.event_id))
    Ok(values) -> {
      let #(turnover, volume) =
        values
        |> list.fold(#(decimal.zero(), decimal.zero()), fn(acc, value) {
          let #(turnover, volume) = acc
          let #(_, price, size, _, _) = value
          #(
            decimal.add(turnover, decimal.multiply(price, size)),
            decimal.add(volume, size),
          )
        })
      case
        decimal.divide(turnover, by: volume, scale: scale, rounding: rounding)
      {
        Error(_) ->
          Unperformed("zero_trade_volume", list.map(trades, packet.event_id))
        Ok(value) ->
          calculated(
            value,
            unit,
            "sum(trade_price * trade_size) / sum(trade_size)",
            list.map(trades, packet.event_id),
            trade_operands(values),
            scale,
            rounding,
          )
      }
    }
  }
}

fn trade_extreme(
  events: List(Event),
  unit: String,
  high: Bool,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  let trades = trade_events(events)
  case parsed_trades(trades) {
    Error(reason) -> Unperformed(reason, list.map(trades, packet.event_id))
    Ok([first, ..] as values) -> {
      let #(_, initial, _, _, _) = first
      let value =
        values
        |> list.fold(initial, fn(current, entry) {
          let #(_, price, _, _, _) = entry
          case decimal.compare(price, current), high {
            Gt, True | Lt, False -> price
            _, _ -> current
          }
        })
      calculated(
        value,
        unit,
        case high {
          True -> "max(trade_price)"
          False -> "min(trade_price)"
        },
        list.map(trades, packet.event_id),
        trade_operands(values),
        scale,
        rounding,
      )
    }
    Ok([]) -> Unperformed("trade_events_required", [])
  }
}

fn trade_extreme_difference(
  events: List(Event),
  unit: String,
  formula: String,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  let trades = trade_events(events)
  case price_extremes(trades) {
    Error(reason) -> Unperformed(reason, list.map(trades, packet.event_id))
    Ok(#(high, low, values)) ->
      calculated(
        decimal.subtract(high, low),
        unit,
        formula,
        list.map(trades, packet.event_id),
        trade_operands(values),
        scale,
        rounding,
      )
  }
}

fn session_range_percent(
  events: List(Event),
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  let trades = trade_events(events)
  case price_extremes(trades), list.first(trades) {
    Ok(#(high, low, values)), Ok(open_event) ->
      case trade_values(open_event) {
        Error(_) ->
          Unperformed("trade_decimal_decode_failure", [
            packet.event_id(open_event),
          ])
        Ok(#(open, _, open_lexeme, _)) ->
          case
            decimal.divide(
              decimal.subtract(high, low),
              by: open,
              scale: scale + 8,
              rounding: rounding,
            )
          {
            Error(_) ->
              Unperformed("zero_open_trade_price", [packet.event_id(open_event)])
            Ok(ratio) ->
              calculated(
                decimal.multiply(ratio, decimal_from_int(100)),
                "percent",
                "((high(trade_price) - low(trade_price)) / first_trade_price) * 100",
                list.map(trades, packet.event_id),
                [
                  Operand(
                    packet.event_id(open_event),
                    "first_trade_price",
                    open_lexeme,
                  ),
                ]
                  |> list.append(trade_operands(values)),
                scale,
                rounding,
              )
          }
      }
    Error(reason), _ -> Unperformed(reason, list.map(trades, packet.event_id))
    _, Error(_) -> Unperformed("trade_events_required", [])
  }
}

fn depth_imbalance(
  events: List(Event),
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  case latest_depth(events) {
    Error(reason) -> Unperformed(reason, [])
    Ok(#(event, levels)) ->
      case depth_totals(levels, packet.event_id(event)) {
        Error(reason) -> Unperformed(reason, [packet.event_id(event)])
        Ok(#(bids, asks, operands)) ->
          case
            decimal.divide(
              bids,
              by: decimal.add(bids, asks),
              scale: scale,
              rounding: rounding,
            )
          {
            Error(_) ->
              Unperformed("zero_total_visible_depth", [packet.event_id(event)])
            Ok(value) ->
              Calculated(
                value,
                "ratio",
                "sum(bid_visible_size) / (sum(bid_visible_size) + sum(ask_visible_size))",
                [packet.event_id(event)],
                operands,
              )
          }
      }
  }
}

fn depth_weighted(
  events: List(Event),
  unit: String,
  side: packet.DepthSide,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  case latest_depth(events) {
    Error(reason) -> Unperformed(reason, [])
    Ok(#(event, levels)) -> {
      let selected = list.filter(levels, fn(level) { level.side == side })
      case parsed_depth(selected, packet.event_id(event)) {
        Error(reason) -> Unperformed(reason, [packet.event_id(event)])
        Ok(values) -> {
          let #(notional, size) =
            values
            |> list.fold(#(decimal.zero(), decimal.zero()), fn(acc, value) {
              let #(notional, size) = acc
              let #(price, visible_size, _) = value
              #(
                decimal.add(notional, decimal.multiply(price, visible_size)),
                decimal.add(size, visible_size),
              )
            })
          case
            decimal.divide(notional, by: size, scale: scale, rounding: rounding)
          {
            Error(_) ->
              Unperformed("zero_visible_depth_for_selected_side", [
                packet.event_id(event),
              ])
            Ok(value) ->
              Calculated(
                value,
                unit,
                "sum(price * visible_size) / sum(visible_size) for selected depth side",
                [packet.event_id(event)],
                list.map(values, fn(value) {
                  let #(_, _, operand) = value
                  operand
                }),
              )
          }
        }
      }
    }
  }
}

fn calculated(
  value: Decimal,
  unit: String,
  formula: String,
  ids: List(String),
  operands: List(Operand),
  scale: Int,
  rounding: decimal.RoundingMode,
) -> ValueResult {
  case decimal.quantize(value, scale: scale, rounding: rounding) {
    Ok(value) -> Calculated(value, unit, formula, ids, operands)
    Error(_) -> Unperformed("invalid_result_scale", ids)
  }
}

fn quote_events(events: List(Event)) -> List(Event) {
  list.filter(events, fn(event) {
    case packet.body(event) {
      packet.Quote(..) -> True
      _ -> False
    }
  })
}

fn trade_events(events: List(Event)) -> List(Event) {
  list.filter(events, fn(event) {
    case packet.body(event) {
      packet.Trade(..) -> True
      _ -> False
    }
  })
}

fn latest_quote(
  events: List(Event),
) -> Result(#(Event, String, String, String, String), String) {
  case quote_events(events) |> list.last {
    Error(_) -> Error("quote_event_required")
    Ok(event) ->
      case packet.body(event) {
        packet.Quote(bid_price, bid_size, ask_price, ask_size) ->
          Ok(#(event, bid_price, bid_size, ask_price, ask_size))
        _ -> Error("quote_event_required")
      }
  }
}

fn latest_depth(
  events: List(Event),
) -> Result(#(Event, List(DepthLevel)), String) {
  let depths =
    list.filter(events, fn(event) {
      case packet.body(event) {
        packet.DepthSnapshot(..) -> True
        _ -> False
      }
    })
  case list.last(depths) {
    Error(_) -> Error("depth_snapshot_required")
    Ok(event) ->
      case packet.body(event) {
        packet.DepthSnapshot(levels) -> Ok(#(event, levels))
        _ -> Error("depth_snapshot_required")
      }
  }
}

fn midpoint_of(
  event: Event,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> Result(Decimal, Nil) {
  case packet.body(event) {
    packet.Quote(bid, _, ask, _) ->
      case decimal.parse(bid), decimal.parse(ask) {
        Ok(bid), Ok(ask) ->
          decimal.divide(
            decimal.add(bid, ask),
            by: decimal_from_int(2),
            scale: scale,
            rounding: rounding,
          )
          |> result.map_error(fn(_) { Nil })
        _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn quote_operands(event: Event, prefix: String) -> List(Operand) {
  case packet.body(event) {
    packet.Quote(bid, _, ask, _) -> [
      Operand(packet.event_id(event), prefix <> "_bid", bid),
      Operand(packet.event_id(event), prefix <> "_ask", ask),
    ]
    _ -> []
  }
}

fn trade_values(
  event: Event,
) -> Result(#(Decimal, Decimal, String, String), Nil) {
  case packet.body(event) {
    packet.Trade(price, size, _) ->
      case decimal.parse(price), decimal.parse(size) {
        Ok(parsed_price), Ok(parsed_size) ->
          Ok(#(parsed_price, parsed_size, price, size))
        _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn parsed_trades(
  trades: List(Event),
) -> Result(List(#(Event, Decimal, Decimal, String, String)), String) {
  case trades {
    [] -> Error("trade_events_required")
    _ ->
      trades
      |> list.try_map(fn(event) {
        trade_values(event)
        |> result.map(fn(value) {
          let #(price, size, price_lexeme, size_lexeme) = value
          #(event, price, size, price_lexeme, size_lexeme)
        })
        |> result.map_error(fn(_) { "trade_decimal_decode_failure" })
      })
  }
}

fn price_extremes(
  trades: List(Event),
) -> Result(
  #(Decimal, Decimal, List(#(Event, Decimal, Decimal, String, String))),
  String,
) {
  use values <- result.try(parsed_trades(trades))
  case values {
    [] -> Error("trade_events_required")
    [first, ..] -> {
      let #(_, first_price, _, _, _) = first
      let #(high, low) =
        values
        |> list.fold(#(first_price, first_price), fn(acc, value) {
          let #(high, low) = acc
          let #(_, price, _, _, _) = value
          #(
            case decimal.compare(price, high) {
              Gt -> price
              _ -> high
            },
            case decimal.compare(price, low) {
              Lt -> price
              _ -> low
            },
          )
        })
      Ok(#(high, low, values))
    }
  }
}

fn trade_operands(
  values: List(#(Event, Decimal, Decimal, String, String)),
) -> List(Operand) {
  values
  |> list.flat_map(fn(value) {
    let #(event, _, _, price, size) = value
    [
      Operand(packet.event_id(event), "trade_price", price),
      Operand(packet.event_id(event), "trade_size", size),
    ]
  })
}

fn depth_totals(
  levels: List(DepthLevel),
  event_id: String,
) -> Result(#(Decimal, Decimal, List(Operand)), String) {
  use values <- result.try(parsed_depth(levels, event_id))
  let #(bids, asks) =
    values
    |> list.fold(#(decimal.zero(), decimal.zero()), fn(acc, value) {
      let #(bids, asks) = acc
      let #(_, size, Operand(_, name, _)) = value
      case string.starts_with(name, "bid_") {
        True -> #(decimal.add(bids, size), asks)
        False -> #(bids, decimal.add(asks, size))
      }
    })
  Ok(#(
    bids,
    asks,
    list.map(values, fn(value) {
      let #(_, _, operand) = value
      operand
    }),
  ))
}

fn parsed_depth(
  levels: List(DepthLevel),
  event_id: String,
) -> Result(List(#(Decimal, Decimal, Operand)), String) {
  case levels {
    [] -> Error("selected_depth_levels_required")
    _ ->
      levels
      |> list.try_map(fn(level) {
        case decimal.parse(level.price), decimal.parse(level.visible_size) {
          Ok(price), Ok(size) ->
            Ok(#(
              price,
              size,
              Operand(
                event_id,
                case level.side {
                  packet.Bid -> "bid_visible_size"
                  packet.Ask -> "ask_visible_size"
                },
                level.visible_size,
              ),
            ))
          _, _ -> Error("depth_decimal_decode_failure")
        }
      })
  }
}

fn last_two(values: List(value)) -> Result(#(value, value), Nil) {
  case list.reverse(values) {
    [current, prior, ..] -> Ok(#(prior, current))
    _ -> Error(Nil)
  }
}

fn corrected_sources(
  selected: List(Event),
  all_events: List(Event),
) -> List(String) {
  let selected_ids = list.map(selected, packet.event_id)
  all_events
  |> list.filter_map(fn(event) {
    case packet.body(event) {
      packet.Correction(original, _) ->
        case list.contains(selected_ids, original) {
          True -> Ok(original)
          False -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
}

fn remove_cancelled_events(
  events: List(Event),
  all_events: List(Event),
) -> List(Event) {
  let cancelled =
    all_events
    |> list.filter_map(fn(event) {
      case packet.body(event) {
        packet.CancelBust(original, _) -> Ok(original)
        _ -> Error(Nil)
      }
    })
  list.filter(events, fn(event) {
    !list.contains(cancelled, packet.event_id(event))
  })
}

fn filter_event(event: Event, filter: EventFilter) -> Bool {
  let decode.EventFilter(include_odd_lots, include_off_exchange, allowed) =
    filter
  let common = packet.common(event)
  let conditions_match = case allowed {
    [] -> True
    _ ->
      list.all(common.conditions, fn(condition) {
        list.contains(allowed, condition)
      })
  }
  { include_odd_lots || !common.odd_lot }
  && { include_off_exchange || !common.off_exchange }
  && conditions_match
}

fn rounding_mode(value: String) -> decimal.RoundingMode {
  case value {
    "toward_zero" -> decimal.TowardZero
    "away_from_zero" -> decimal.AwayFromZero
    "half_up" -> decimal.HalfUp
    _ -> decimal.HalfEven
  }
}

fn decimal_from_int(value: Int) -> Decimal {
  let assert Ok(value) = decimal.parse(int.to_string(value))
  value
}

fn supported_calculations() -> List(String) {
  [
    "quoted_spread",
    "quoted_spread_percent",
    "midpoint",
    "displayed_bid_notional",
    "displayed_ask_notional",
    "quote_change",
    "trade_change",
    "opening_range",
    "session_high",
    "session_low",
    "cumulative_volume",
    "cumulative_turnover",
    "vwap",
    "session_range_percent",
    "depth_imbalance",
    "depth_weighted_bid",
    "depth_weighted_ask",
  ]
}

fn result_json(
  packet_value: Packet,
  calculation: String,
  start: Int,
  finish: Int,
  scale: Int,
  rounding: String,
  filter: EventFilter,
  selected_events: List(Event),
  value: ValueResult,
) -> Json {
  json.object([
    #("schemaVersion", json.string("pi_day_calculation_v1")),
    #("packetId", json.string(packet_value.packet_id)),
    #("packetHash", json.string(packet_value.packet_hash)),
    #("track", json.string(packet_value.track)),
    #("listingId", json.string(packet_value.listing_id)),
    #("mic", json.string(packet_value.mic)),
    #("provider", json.string(packet_value.provider)),
    #("feed", json.string(packet_value.feed)),
    #("claimVerification", json.string("caller_attested_not_verified")),
    #("calculation", json.string(calculation)),
    #(
      "window",
      json.object([
        #("startUnixMilliseconds", json.int(start)),
        #("endUnixMilliseconds", json.int(finish)),
      ]),
    ),
    #("eventFilter", filter_json(filter)),
    #("scale", json.int(scale)),
    #("rounding", json.string(rounding)),
    #("selectedEventCount", json.int(list.length(selected_events))),
    #("result", value_json(value)),
    #("decisionOwner", json.string("llm_or_user")),
    #(
      "meaning",
      json.string(
        "explicit mechanical calculation only; not a signal, setup, sufficiency verdict, recommendation, authorization, fill claim, or next action",
      ),
    ),
  ])
}

fn value_json(value: ValueResult) -> Json {
  case value {
    Calculated(value, unit, formula, ids, operands) ->
      json.object([
        #("state", json.string("calculated")),
        #("exactValue", json.string(decimal.to_string(value))),
        #("unit", json.string(unit)),
        #("formula", json.string(formula)),
        #("sourceEventIds", json.array(ids, json.string)),
        #("operands", json.array(operands, operand_json)),
      ])
    Unperformed(reason, ids) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
        #("sourceEventIds", json.array(ids, json.string)),
      ])
  }
}

fn operand_json(value: Operand) -> Json {
  let Operand(event_id, name, lexeme) = value
  json.object([
    #("eventId", json.string(event_id)),
    #("name", json.string(name)),
    #("sourceLexeme", json.string(lexeme)),
  ])
}

fn filter_json(filter: EventFilter) -> Json {
  let decode.EventFilter(odd_lots, off_exchange, conditions) = filter
  json.object([
    #("includeOddLots", json.bool(odd_lots)),
    #("includeOffExchange", json.bool(off_exchange)),
    #("includedConditionCodes", json.array(conditions, json.string)),
    #(
      "conditionRule",
      json.string(
        "empty allows all; otherwise every event condition must be in caller allowlist",
      ),
    ),
  ])
}
