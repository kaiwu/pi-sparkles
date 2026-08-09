import finance_core/decimal.{type Decimal}
import finance_core/identifier
import finance_core/time
import finance_table/json as table_json
import finance_table/markdown
import finance_table/table
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dict.{type Dict}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_finance_charts/decode

const image_width = 960

const image_height = 640

const plot_left = 54

const plot_right = 930

pub type Response {
  Response(fallback: String, details: Json, plan_json: String)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  InvalidSeries(index: Int, reason: String)
  InvalidIndicator(indicator_id: String, reason: String)
  InvalidTrade(trade_id: String, reason: String)
  InvalidGap(index: Int, reason: String)
  TableFailure(reason: String)
}

type ValidatedContext {
  ValidatedContext(input: decode.ContextInput, shared: track_context.Context)
}

type ParsedBar {
  ParsedBar(
    input: decode.BarInput,
    open: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    volume: Decimal,
  )
}

type ParsedIndicatorPoint {
  PlottedPoint(date: String, value: Decimal, raw: String)
  SkippedPoint(date: String, reason: String)
}

type ParsedIndicator {
  ParsedIndicator(
    input: decode.IndicatorInput,
    points: List(ParsedIndicatorPoint),
  )
}

type ParsedTrade {
  ParsedTrade(input: decode.TradeInput, price: Decimal)
}

type Bounds {
  Bounds(minimum: Decimal, maximum: Decimal)
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid explicit finance-chart field " <> field <> ": " <> reason
    InvalidSeries(index, reason) ->
      "Invalid OHLCV bar at index " <> int.to_string(index) <> ": " <> reason
    InvalidIndicator(indicator_id, reason) ->
      "Invalid indicator " <> indicator_id <> ": " <> reason
    InvalidTrade(trade_id, reason) ->
      "Invalid trade marker " <> trade_id <> ": " <> reason
    InvalidGap(index, reason) ->
      "Invalid gap at index " <> int.to_string(index) <> ": " <> reason
    TableFailure(reason) ->
      "The exact structured fallback could not be rendered: " <> reason
  }
}

pub fn run(input: decode.Input) -> Result(Response, DomainError) {
  use context <- result.try(validate_context(input.context))
  use bars <- result.try(parse_bars(input.series))
  let date_indexes =
    bars
    |> list.index_map(fn(bar, index) { #(bar.input.date, index) })
    |> dict.from_list
  use indicators <- result.try(parse_indicators(
    input.indicators,
    context.input.price_unit,
    list.length(bars),
  ))
  use trades <- result.try(parse_trades(input.trades))
  use _ <- result.try(validate_gaps(input.gaps))
  use _ <- result.try(validate_omissions(input.input_omissions, []))
  use _ <- result.try(validate_fallback_limit(input.fallback_maximum_rows))
  let price_bounds = price_bounds(bars, indicators, trades, date_indexes)
  let lower_bounds = lower_bounds(indicators, date_indexes)
  use #(fallback_table, omitted_rows) <- result.try(fallback_table(
    context,
    bars,
    input.fallback_maximum_rows,
  ))
  let plan =
    render_plan(
      bars,
      indicators,
      trades,
      input.gaps,
      date_indexes,
      price_bounds,
      lower_bounds,
    )
  let details =
    details_json(
      context,
      bars,
      indicators,
      trades,
      input.gaps,
      input.input_omissions,
      date_indexes,
      price_bounds,
      lower_bounds,
      fallback_table,
      omitted_rows,
    )
  let summary =
    context.input.track
    <> " | "
    <> context.input.instrument_id
    <> " | "
    <> int.to_string(list.length(bars))
    <> " completed-daily bars | "
    <> int.to_string(list.length(indicators))
    <> " indicator series | "
    <> int.to_string(list.length(trades))
    <> " trade markers"
  Ok(Response(
    summary
      <> "\n\n"
      <> markdown.render(fallback_table)
      <> "\n\nA deterministic 960×640 PNG view follows. Exact structured decimal strings remain controlling.",
    details,
    json.to_string(plan),
  ))
}

fn validate_context(
  input: decode.ContextInput,
) -> Result(ValidatedContext, DomainError) {
  use _ <- result.try(require_hash(
    "context.instructionRef",
    input.instruction_ref,
  ))
  use track <- result.try(
    finance_track.from_name(input.track)
    |> result.map_error(fn(_) {
      InvalidField("context.track", "expected exact cn, hk, or us")
    }),
  )
  use mic <- result.try(
    identifier.mic(input.mic)
    |> result.map_error(fn(_) { InvalidField("context.mic", "invalid MIC") }),
  )
  use timezone <- result.try(
    time.timezone(input.timezone)
    |> result.map_error(fn(_) {
      InvalidField("context.timezone", "invalid IANA timezone")
    }),
  )
  use _ <- result.try(track_market_match(input.track, input.mic, input.timezone))
  use _ <- result.try(require_text("context.instrumentId", input.instrument_id))
  use _ <- result.try(require_text("context.priceUnit", input.price_unit))
  use _ <- result.try(require_text("context.volumeUnit", input.volume_unit))
  use _ <- result.try(validate_adjustment(input.adjustment))
  use _ <- result.try(validate_source(input.source))
  use shared <- result.try(
    track_context.new(
      track: track,
      market_scope: input.track <> "_finance_chart",
      venue_mic: Some(mic),
      board: None,
      timezone: Some(timezone),
      source_language: input.source_language,
      providers: [input.source.provider],
      entitlement: input.source.entitlement,
      limitations: input.limitations,
    )
    |> result.map_error(fn(error) {
      InvalidField("context.trackContext", string.inspect(error))
    }),
  )
  Ok(ValidatedContext(input, shared))
}

fn track_market_match(
  track: String,
  mic: String,
  timezone: String,
) -> Result(Nil, DomainError) {
  case track, mic, timezone {
    "cn", "XSHG", "Asia/Shanghai"
    | "cn", "XSHE", "Asia/Shanghai"
    | "cn", "XBSE", "Asia/Shanghai"
    | "hk", "XHKG", "Asia/Hong_Kong"
    | "us", "XNYS", "America/New_York"
    | "us", "XNAS", "America/New_York"
    -> Ok(Nil)
    _, _, _ ->
      Error(InvalidField(
        "context.track/mic/timezone",
        "the exact market combination is not supported and no fallback was used",
      ))
  }
}

fn validate_adjustment(
  input: decode.AdjustmentInput,
) -> Result(Nil, DomainError) {
  case input.kind, input.label {
    "provider_adjusted", Some(label) ->
      require_text("context.adjustment.label", label)
    "provider_adjusted", None ->
      Error(InvalidField(
        "context.adjustment.label",
        "provider_adjusted requires its exact provider basis label",
      ))
    "raw", None
    | "split_adjusted", None
    | "dividend_adjusted", None
    | "total_return_adjusted", None
    -> Ok(Nil)
    "raw", Some(_)
    | "split_adjusted", Some(_)
    | "dividend_adjusted", Some(_)
    | "total_return_adjusted", Some(_)
    ->
      Error(InvalidField(
        "context.adjustment.label",
        "only provider_adjusted accepts a label",
      ))
    _, _ ->
      Error(InvalidField(
        "context.adjustment.kind",
        "unsupported adjustment basis",
      ))
  }
}

fn validate_source(input: decode.SourceInput) -> Result(Nil, DomainError) {
  use _ <- result.try(require_text("context.source.provider", input.provider))
  use _ <- result.try(require_text(
    "context.source.sourceReference",
    input.source_reference,
  ))
  use _ <- result.try(require_hash(
    "context.source.acquisitionReceipt",
    input.acquisition_receipt,
  ))
  use retrieved <- result.try(
    time.instant(input.retrieved_at_unix_milliseconds)
    |> result.map_error(fn(_) {
      InvalidField(
        "context.source.retrievedAtUnixMilliseconds",
        "outside the supported instant range",
      )
    }),
  )
  case input.source_cutoff_unix_milliseconds {
    None -> Ok(Nil)
    Some(value) -> {
      use cutoff <- result.try(
        time.instant(value)
        |> result.map_error(fn(_) {
          InvalidField(
            "context.source.sourceCutoffUnixMilliseconds",
            "outside the supported instant range",
          )
        }),
      )
      case time.unix_milliseconds(cutoff) <= time.unix_milliseconds(retrieved) {
        True -> Ok(Nil)
        False ->
          Error(InvalidField(
            "context.source.sourceCutoffUnixMilliseconds",
            "cannot be later than retrieval time",
          ))
      }
    }
  }
}

fn parse_bars(
  values: List(decode.BarInput),
) -> Result(List(ParsedBar), DomainError) {
  case list.length(values) >= 1 && list.length(values) <= 240 {
    False -> Error(InvalidField("series", "expected 1 through 240 bars"))
    True -> parse_bars_loop(values, 0, None, [])
  }
}

fn parse_bars_loop(
  values: List(decode.BarInput),
  index: Int,
  previous_date: Option(String),
  reversed: List(ParsedBar),
) -> Result(List(ParsedBar), DomainError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use _ <- result.try(
        parse_date("series[" <> int.to_string(index) <> "].date", value.date)
        |> result.map_error(fn(_) {
          InvalidSeries(
            index,
            "invalid canonical Gregorian date " <> value.date,
          )
        }),
      )
      use _ <- result.try(case previous_date {
        Some(previous) ->
          case string.compare(value.date, previous) == Gt {
            True -> Ok(Nil)
            False ->
              Error(InvalidSeries(
                index,
                "dates must be strictly increasing and unique",
              ))
          }
        None -> Ok(Nil)
      })
      use _ <- result.try(case value.session_type {
        "regular" | "half_day" | "unknown" -> Ok(Nil)
        _ -> Error(InvalidSeries(index, "unsupported sessionType"))
      })
      use open <- result.try(parse_bar_decimal(index, "open", value.open))
      use high <- result.try(parse_bar_decimal(index, "high", value.high))
      use low <- result.try(parse_bar_decimal(index, "low", value.low))
      use close <- result.try(parse_bar_decimal(index, "close", value.close))
      use volume <- result.try(parse_bar_decimal(index, "volume", value.volume))
      use _ <- result.try(
        case
          decimal.compare(high, open) != Lt
          && decimal.compare(high, close) != Lt
          && decimal.compare(high, low) != Lt
          && decimal.compare(low, open) != Gt
          && decimal.compare(low, close) != Gt
          && decimal.compare(volume, decimal.zero()) != Lt
        {
          True -> Ok(Nil)
          False ->
            Error(InvalidSeries(
              index,
              "high/low OHLC ordering or non-negative volume invariant failed",
            ))
        },
      )
      parse_bars_loop(rest, index + 1, Some(value.date), [
        ParsedBar(value, open, high, low, close, volume),
        ..reversed
      ])
    }
  }
}

fn parse_bar_decimal(
  index: Int,
  field: String,
  value: String,
) -> Result(Decimal, DomainError) {
  decimal.parse(value)
  |> result.map_error(fn(_) {
    InvalidSeries(index, field <> " is not an exact decimal lexeme")
  })
}

fn parse_indicators(
  values: List(decode.IndicatorInput),
  price_unit: String,
  bar_count: Int,
) -> Result(List(ParsedIndicator), DomainError) {
  case list.length(values) <= 4 {
    False ->
      Error(InvalidField("indicators", "at most four series are rendered"))
    True -> parse_indicators_loop(values, price_unit, bar_count, [], None, [])
  }
}

fn parse_indicators_loop(
  values: List(decode.IndicatorInput),
  price_unit: String,
  bar_count: Int,
  seen_ids: List(String),
  lower_unit: Option(String),
  reversed: List(ParsedIndicator),
) -> Result(List(ParsedIndicator), DomainError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use _ <- result.try(
        require_text("indicators.indicatorId", value.indicator_id)
        |> result.map_error(fn(_) {
          InvalidIndicator(value.indicator_id, "empty or padded indicatorId")
        }),
      )
      use _ <- result.try(case list.contains(seen_ids, value.indicator_id) {
        True ->
          Error(InvalidIndicator(value.indicator_id, "duplicate indicatorId"))
        False -> Ok(Nil)
      })
      use _ <- result.try(
        require_text("indicators.label", value.label)
        |> result.map_error(fn(_) {
          InvalidIndicator(value.indicator_id, "empty or padded label")
        }),
      )
      use _ <- result.try(
        require_text("indicators.unit", value.unit)
        |> result.map_error(fn(_) {
          InvalidIndicator(value.indicator_id, "empty or padded unit")
        }),
      )
      use next_lower_unit <- result.try(case value.panel, lower_unit {
        "price_overlay", _ if value.unit == price_unit -> Ok(lower_unit)
        "price_overlay", _ ->
          Error(InvalidIndicator(
            value.indicator_id,
            "price_overlay unit must exactly equal context.priceUnit",
          ))
        "lower_panel", None -> Ok(Some(value.unit))
        "lower_panel", Some(unit) if unit == value.unit -> Ok(lower_unit)
        "lower_panel", Some(_) ->
          Error(InvalidIndicator(
            value.indicator_id,
            "all lower_panel indicators must share one exact unit",
          ))
        _, _ -> Error(InvalidIndicator(value.indicator_id, "unsupported panel"))
      })
      use _ <- result.try(
        case value.warmup_sessions >= 0 && value.warmup_sessions < bar_count {
          True -> Ok(Nil)
          False ->
            Error(InvalidIndicator(
              value.indicator_id,
              "warmupSessions must be non-negative and smaller than the bar count",
            ))
        },
      )
      use _ <- result.try(
        require_hash("indicators.calculationReceipt", value.calculation_receipt)
        |> result.map_error(fn(_) {
          InvalidIndicator(value.indicator_id, "invalid calculationReceipt")
        }),
      )
      use points <- result.try(parse_indicator_points(value))
      parse_indicators_loop(
        rest,
        price_unit,
        bar_count,
        [value.indicator_id, ..seen_ids],
        next_lower_unit,
        [ParsedIndicator(value, points), ..reversed],
      )
    }
  }
}

fn parse_indicator_points(
  indicator: decode.IndicatorInput,
) -> Result(List(ParsedIndicatorPoint), DomainError) {
  case
    list.length(indicator.points) >= 1 && list.length(indicator.points) <= 240
  {
    False ->
      Error(InvalidIndicator(
        indicator.indicator_id,
        "expected 1 through 240 points",
      ))
    True -> parse_indicator_points_loop(indicator, indicator.points, None, [])
  }
}

fn parse_indicator_points_loop(
  indicator: decode.IndicatorInput,
  values: List(decode.IndicatorPointInput),
  previous_date: Option(String),
  reversed: List(ParsedIndicatorPoint),
) -> Result(List(ParsedIndicatorPoint), DomainError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      let #(date, parsed) = case value {
        decode.Calculated(date, raw) -> {
          let parsed = case decimal.parse(raw) {
            Ok(value) -> Ok(PlottedPoint(date, value, raw))
            Error(_) ->
              Error(InvalidIndicator(
                indicator.indicator_id,
                "calculated point on "
                  <> date
                  <> " is not an exact decimal lexeme",
              ))
          }
          #(date, parsed)
        }
        decode.Unperformed(date, reason) -> {
          let parsed = case valid_text(reason) {
            True -> Ok(SkippedPoint(date, reason))
            False ->
              Error(InvalidIndicator(
                indicator.indicator_id,
                "unperformed point reason is empty or padded",
              ))
          }
          #(date, parsed)
        }
      }
      use point <- result.try(parsed)
      use _ <- result.try(
        parse_date("indicator point date", date)
        |> result.map_error(fn(_) {
          InvalidIndicator(
            indicator.indicator_id,
            "invalid canonical Gregorian point date " <> date,
          )
        }),
      )
      use _ <- result.try(case previous_date {
        Some(previous) ->
          case string.compare(date, previous) == Gt {
            True -> Ok(Nil)
            False ->
              Error(InvalidIndicator(
                indicator.indicator_id,
                "point dates must be strictly increasing and unique",
              ))
          }
        None -> Ok(Nil)
      })
      parse_indicator_points_loop(indicator, rest, Some(date), [
        point,
        ..reversed
      ])
    }
  }
}

fn parse_trades(
  values: List(decode.TradeInput),
) -> Result(List(ParsedTrade), DomainError) {
  case list.length(values) <= 240 {
    False -> Error(InvalidField("trades", "at most 240 markers are rendered"))
    True -> parse_trades_loop(values, [], [])
  }
}

fn parse_trades_loop(
  values: List(decode.TradeInput),
  seen_ids: List(String),
  reversed: List(ParsedTrade),
) -> Result(List(ParsedTrade), DomainError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use _ <- result.try(
        case
          valid_text(value.trade_id),
          list.contains(seen_ids, value.trade_id)
        {
          False, _ ->
            Error(InvalidTrade(value.trade_id, "empty or padded tradeId"))
          _, True -> Error(InvalidTrade(value.trade_id, "duplicate tradeId"))
          True, False -> Ok(Nil)
        },
      )
      use _ <- result.try(
        parse_date("trade.date", value.date)
        |> result.map_error(fn(_) {
          InvalidTrade(value.trade_id, "invalid canonical Gregorian date")
        }),
      )
      use _ <- result.try(case value.side {
        "buy" | "sell" -> Ok(Nil)
        _ -> Error(InvalidTrade(value.trade_id, "unsupported side"))
      })
      use _ <- result.try(case value.status {
        "proposed" | "simulated" | "observed" -> Ok(Nil)
        _ -> Error(InvalidTrade(value.trade_id, "unsupported status"))
      })
      use price <- result.try(
        decimal.parse(value.price)
        |> result.map_error(fn(_) {
          InvalidTrade(value.trade_id, "price is not an exact decimal lexeme")
        }),
      )
      use quantity <- result.try(
        decimal.parse(value.quantity)
        |> result.map_error(fn(_) {
          InvalidTrade(
            value.trade_id,
            "quantity is not an exact decimal lexeme",
          )
        }),
      )
      use _ <- result.try(
        case
          decimal.compare(price, decimal.zero()) == Gt
          && decimal.compare(quantity, decimal.zero()) == Gt
        {
          True -> Ok(Nil)
          False ->
            Error(InvalidTrade(
              value.trade_id,
              "price and quantity must be positive",
            ))
        },
      )
      use _ <- result.try(
        require_hash("trade.evidenceReceipt", value.evidence_receipt)
        |> result.map_error(fn(_) {
          InvalidTrade(value.trade_id, "invalid evidenceReceipt")
        }),
      )
      parse_trades_loop(rest, [value.trade_id, ..seen_ids], [
        ParsedTrade(value, price),
        ..reversed
      ])
    }
  }
}

fn validate_gaps(values: List(decode.GapInput)) -> Result(Nil, DomainError) {
  case list.length(values) <= 240 {
    False -> Error(InvalidField("gaps", "at most 240 gap facts are accepted"))
    True -> validate_gaps_loop(values, 0, [])
  }
}

fn validate_gaps_loop(
  values: List(decode.GapInput),
  index: Int,
  seen_dates: List(String),
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(
        parse_date("gap.date", value.date)
        |> result.map_error(fn(_) {
          InvalidGap(index, "invalid canonical date")
        }),
      )
      use _ <- result.try(case list.contains(seen_dates, value.date) {
        True -> Error(InvalidGap(index, "duplicate gap date"))
        False -> Ok(Nil)
      })
      use _ <- result.try(case value.state {
        "market_closure"
        | "suspension"
        | "provider_omission"
        | "unavailable_history"
        | "unknown" -> Ok(Nil)
        _ -> Error(InvalidGap(index, "unsupported gap state"))
      })
      use _ <- result.try(case valid_text(value.reason) {
        True -> Ok(Nil)
        False -> Error(InvalidGap(index, "reason is empty or padded"))
      })
      use _ <- result.try(validate_gap_hashes(value.evidence_roots, index))
      validate_gaps_loop(rest, index + 1, [value.date, ..seen_dates])
    }
  }
}

fn validate_gap_hashes(
  values: List(String),
  index: Int,
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case is_sha256(value) {
        True -> validate_gap_hashes(rest, index)
        False -> Error(InvalidGap(index, "invalid evidence root"))
      }
  }
}

fn validate_omissions(
  values: List(String),
  seen: List(String),
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case valid_text(value), list.contains(seen, value) {
        False, _ ->
          Error(InvalidField(
            "inputOmissions",
            "entries must be non-empty and unpadded",
          ))
        _, True -> Error(InvalidField("inputOmissions", "duplicate omission"))
        True, False -> validate_omissions(rest, [value, ..seen])
      }
  }
}

fn validate_fallback_limit(value: Int) -> Result(Nil, DomainError) {
  case value >= 1 && value <= 50 {
    True -> Ok(Nil)
    False -> Error(InvalidField("fallbackMaximumRows", "expected 1 through 50"))
  }
}

fn parse_date(field: String, value: String) -> Result(time.Date, DomainError) {
  case string.split(value, "-") {
    [year, month, day] ->
      case int.parse(year), int.parse(month), int.parse(day) {
        Ok(year), Ok(month), Ok(day) ->
          case time.date(year, month, day) {
            Ok(parsed) -> {
              let #(year, month, day) = time.date_parts(parsed)
              let canonical =
                int.to_string(year)
                <> "-"
                <> pad_two(month)
                <> "-"
                <> pad_two(day)
              case canonical == value {
                True -> Ok(parsed)
                False -> Error(InvalidField(field, "non-canonical date"))
              }
            }
            Error(_) -> Error(InvalidField(field, "invalid Gregorian date"))
          }
        _, _, _ -> Error(InvalidField(field, "invalid Gregorian date"))
      }
    _ -> Error(InvalidField(field, "invalid Gregorian date"))
  }
}

fn pad_two(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn price_bounds(
  bars: List(ParsedBar),
  indicators: List(ParsedIndicator),
  trades: List(ParsedTrade),
  date_indexes: Dict(String, Int),
) -> Bounds {
  let bar_values =
    bars
    |> list.flat_map(fn(bar) { [bar.low, bar.high] })
  let overlay_values =
    indicators
    |> list.flat_map(fn(indicator) {
      case indicator.input.panel {
        "price_overlay" ->
          matched_indicator_values(indicator.points, date_indexes)
        _ -> []
      }
    })
  let trade_values =
    trades
    |> list.filter_map(fn(trade) {
      case dict.has_key(date_indexes, trade.input.date) {
        True -> Ok(trade.price)
        False -> Error(Nil)
      }
    })
  bounds(list.flatten([bar_values, overlay_values, trade_values]))
}

fn lower_bounds(
  indicators: List(ParsedIndicator),
  date_indexes: Dict(String, Int),
) -> Option(Bounds) {
  let values =
    indicators
    |> list.flat_map(fn(indicator) {
      case indicator.input.panel {
        "lower_panel" ->
          matched_indicator_values(indicator.points, date_indexes)
        _ -> []
      }
    })
  case values {
    [] -> None
    _ -> Some(bounds(values))
  }
}

fn matched_indicator_values(
  points: List(ParsedIndicatorPoint),
  date_indexes: Dict(String, Int),
) -> List(Decimal) {
  points
  |> list.filter_map(fn(point) {
    case point {
      PlottedPoint(date, value, _) ->
        case dict.has_key(date_indexes, date) {
          True -> Ok(value)
          False -> Error(Nil)
        }
      SkippedPoint(_, _) -> Error(Nil)
    }
  })
}

fn bounds(values: List(Decimal)) -> Bounds {
  let assert [first, ..rest] = values
  let #(minimum, maximum) =
    rest
    |> list.fold(#(first, first), fn(current, value) {
      let #(minimum, maximum) = current
      #(
        case decimal.compare(value, minimum) == Lt {
          True -> value
          False -> minimum
        },
        case decimal.compare(value, maximum) == Gt {
          True -> value
          False -> maximum
        },
      )
    })
  Bounds(minimum, maximum)
}

fn fallback_table(
  context: ValidatedContext,
  bars: List(ParsedBar),
  maximum_rows: Int,
) -> Result(#(table.Table, Int), DomainError) {
  use complete <- result.try(
    table.new(
      caption: Some(
        context.input.instrument_id
        <> " OHLCV ("
        <> context.input.price_unit
        <> "; volume "
        <> context.input.volume_unit
        <> ")",
      ),
      columns: [
        table.Column("date", "Date", table.TextColumn, table.Left, None),
        table.Column("session", "Session", table.TextColumn, table.Left, None),
        table.Column("open", "Open", table.DecimalColumn, table.Right, None),
        table.Column("high", "High", table.DecimalColumn, table.Right, None),
        table.Column("low", "Low", table.DecimalColumn, table.Right, None),
        table.Column("close", "Close", table.DecimalColumn, table.Right, None),
        table.Column("volume", "Volume", table.DecimalColumn, table.Right, None),
      ],
      rows: bars
        |> list.map(fn(bar) {
          table.Row(Some(bar.input.date), [
            table.TextCell(bar.input.date),
            table.TextCell(bar.input.session_type),
            table.DecimalCell(bar.open),
            table.DecimalCell(bar.high),
            table.DecimalCell(bar.low),
            table.DecimalCell(bar.close),
            table.DecimalCell(bar.volume),
          ])
        }),
      notes: [
        "Track/MIC/timezone: "
          <> context.input.track
          <> "/"
          <> context.input.mic
          <> "/"
          <> context.input.timezone,
        "Adjustment: " <> adjustment_text(context.input.adjustment),
        "Source cutoff: "
          <> optional_instant_text(
          context.input.source.source_cutoff_unix_milliseconds,
        ),
      ],
    )
    |> result.map_error(fn(error) { TableFailure(string.inspect(error)) }),
  )
  use #(truncated, omission) <- result.try(
    table.truncate_rows(complete, maximum_rows)
    |> result.map_error(fn(error) { TableFailure(string.inspect(error)) }),
  )
  let table.Omission(omitted_rows) = omission
  Ok(#(truncated, omitted_rows))
}

fn render_plan(
  bars: List(ParsedBar),
  indicators: List(ParsedIndicator),
  trades: List(ParsedTrade),
  gaps: List(decode.GapInput),
  date_indexes: Dict(String, Int),
  price_bounds: Bounds,
  lower_bounds: Option(Bounds),
) -> Json {
  let has_lower =
    indicators
    |> list.any(fn(indicator) { indicator.input.panel == "lower_panel" })
  let price_bottom = case has_lower {
    True -> 352
    False -> 438
  }
  let volume_top = price_bottom + 20
  let volume_bottom = case has_lower {
    True -> 458
    False -> 590
  }
  let base = [
    line_json(plot_left, 28, plot_left, volume_bottom, 1, "#54627a"),
    line_json(plot_right, 28, plot_right, volume_bottom, 1, "#54627a"),
    line_json(plot_left, price_bottom, plot_right, price_bottom, 1, "#54627a"),
    line_json(plot_left, volume_top, plot_right, volume_top, 1, "#354157"),
    line_json(plot_left, volume_bottom, plot_right, volume_bottom, 1, "#54627a"),
    ..grid_primitives(28, price_bottom)
  ]
  let lower_grid = case has_lower {
    True -> [
      line_json(plot_left, 478, plot_right, 478, 1, "#54627a"),
      line_json(plot_left, 610, plot_right, 610, 1, "#54627a"),
      ..grid_primitives(478, 610)
    ]
    False -> []
  }
  let gap_lines =
    gaps
    |> list.map(fn(gap) {
      let x = gap_x(gap.date, bars)
      line_json(
        x,
        28,
        x,
        case has_lower {
          True -> 610
          False -> volume_bottom
        },
        2,
        gap_color(gap.state),
      )
    })
  let volume_max =
    bars
    |> list.map(fn(bar) { bar.volume })
    |> bounds
  let candles =
    bars
    |> list.index_map(fn(bar, index) {
      candle_primitives(
        bar,
        index,
        list.length(bars),
        price_bounds,
        28,
        price_bottom,
        volume_max.maximum,
        volume_top,
        volume_bottom,
      )
    })
    |> list.flatten
  let indicator_lines =
    indicators
    |> list.index_map(fn(indicator, index) {
      let panel_bounds = case indicator.input.panel, lower_bounds {
        "price_overlay", _ -> price_bounds
        "lower_panel", Some(value) -> value
        "lower_panel", None -> Bounds(decimal.zero(), decimal.zero())
        _, _ -> price_bounds
      }
      let #(top, bottom) = case indicator.input.panel {
        "lower_panel" -> #(478, 610)
        _ -> #(28, price_bottom)
      }
      indicator_primitives(
        indicator.points,
        date_indexes,
        list.length(bars),
        panel_bounds,
        top,
        bottom,
        indicator_color(index),
        None,
        [],
      )
    })
    |> list.flatten
  let trade_markers =
    trades
    |> list.flat_map(fn(trade) {
      trade_primitives(
        trade,
        date_indexes,
        list.length(bars),
        price_bounds,
        28,
        price_bottom,
      )
    })
  json.object([
    #("width", json.int(image_width)),
    #("height", json.int(image_height)),
    #("background", json.string("#0b1220")),
    #(
      "primitives",
      json.array(
        list.flatten([
          base,
          lower_grid,
          gap_lines,
          candles,
          indicator_lines,
          trade_markers,
        ]),
        fn(value) { value },
      ),
    ),
  ])
}

fn grid_primitives(top: Int, bottom: Int) -> List(Json) {
  [0, 1, 2, 3, 4]
  |> list.map(fn(step) {
    let y = top + step * { bottom - top } / 4
    line_json(plot_left, y, plot_right, y, 1, "#253047")
  })
}

fn candle_primitives(
  bar: ParsedBar,
  index: Int,
  count: Int,
  price_bounds: Bounds,
  price_top: Int,
  price_bottom: Int,
  volume_maximum: Decimal,
  volume_top: Int,
  volume_bottom: Int,
) -> List(Json) {
  let x = x_coordinate(index, count)
  let spacing = case count > 1 {
    True -> { plot_right - plot_left } / count
    False -> 20
  }
  let half_width = int.max(2, int.min(7, spacing / 3))
  let open_y = y_coordinate(bar.open, price_bounds, price_top, price_bottom)
  let high_y = y_coordinate(bar.high, price_bounds, price_top, price_bottom)
  let low_y = y_coordinate(bar.low, price_bounds, price_top, price_bottom)
  let close_y = y_coordinate(bar.close, price_bounds, price_top, price_bottom)
  let body_top = int.min(open_y, close_y)
  let body_height = int.max(int.absolute_value(close_y - open_y), 1)
  let color = case decimal.compare(bar.close, bar.open) {
    Gt -> "#20b486"
    Lt -> "#ef5b5b"
    Eq -> "#9aa7bd"
  }
  let volume_height =
    scaled_height(bar.volume, volume_maximum, volume_bottom - volume_top)
    |> int.max(1)
  [
    line_json(x, high_y, x, low_y, 1, color),
    rect_json(x - half_width, body_top, half_width * 2 + 1, body_height, color),
    rect_json(
      x - half_width,
      volume_bottom - volume_height,
      half_width * 2 + 1,
      volume_height,
      session_volume_color(bar.input.session_type),
    ),
  ]
}

fn gap_x(date: String, bars: List(ParsedBar)) -> Int {
  let before =
    bars
    |> list.take_while(fn(bar) { string.compare(bar.input.date, date) == Lt })
    |> list.length
  case before >= list.length(bars), before {
    _, 0 -> plot_left
    True, _ -> plot_right
    False, value ->
      {
        x_coordinate(value - 1, list.length(bars))
        + x_coordinate(value, list.length(bars))
      }
      / 2
  }
}

fn indicator_primitives(
  points: List(ParsedIndicatorPoint),
  date_indexes: Dict(String, Int),
  bar_count: Int,
  value_bounds: Bounds,
  top: Int,
  bottom: Int,
  color: String,
  previous: Option(#(Int, Int)),
  reversed: List(Json),
) -> List(Json) {
  case points {
    [] -> list.reverse(reversed)
    [point, ..rest] ->
      case point {
        SkippedPoint(_, _) ->
          indicator_primitives(
            rest,
            date_indexes,
            bar_count,
            value_bounds,
            top,
            bottom,
            color,
            None,
            reversed,
          )
        PlottedPoint(date, value, _) ->
          case dict.get(date_indexes, date) {
            Error(_) ->
              indicator_primitives(
                rest,
                date_indexes,
                bar_count,
                value_bounds,
                top,
                bottom,
                color,
                None,
                reversed,
              )
            Ok(index) -> {
              let current = #(
                x_coordinate(index, bar_count),
                y_coordinate(value, value_bounds, top, bottom),
              )
              let next_reversed = case previous {
                Some(#(x, y)) -> [
                  line_json(x, y, current.0, current.1, 2, color),
                  ..reversed
                ]
                None -> [
                  rect_json(current.0 - 1, current.1 - 1, 3, 3, color),
                  ..reversed
                ]
              }
              indicator_primitives(
                rest,
                date_indexes,
                bar_count,
                value_bounds,
                top,
                bottom,
                color,
                Some(current),
                next_reversed,
              )
            }
          }
      }
  }
}

fn trade_primitives(
  trade: ParsedTrade,
  date_indexes: Dict(String, Int),
  bar_count: Int,
  price_bounds: Bounds,
  top: Int,
  bottom: Int,
) -> List(Json) {
  case dict.get(date_indexes, trade.input.date) {
    Error(_) -> []
    Ok(index) -> {
      let x = x_coordinate(index, bar_count)
      let y = y_coordinate(trade.price, price_bounds, top, bottom)
      case trade.input.side {
        "buy" -> [
          triangle_json(
            x,
            int.min(y + 3, bottom),
            x - 7,
            int.min(y + 14, bottom),
            x + 7,
            int.min(y + 14, bottom),
            "#59a5ff",
          ),
        ]
        _ -> [
          triangle_json(
            x,
            int.max(y - 3, top),
            x - 7,
            int.max(y - 14, top),
            x + 7,
            int.max(y - 14, top),
            "#f5b942",
          ),
        ]
      }
    }
  }
}

fn x_coordinate(index: Int, count: Int) -> Int {
  case count <= 1 {
    True -> { plot_left + plot_right } / 2
    False -> plot_left + index * { plot_right - plot_left } / { count - 1 }
  }
}

fn y_coordinate(
  value: Decimal,
  value_bounds: Bounds,
  top: Int,
  bottom: Int,
) -> Int {
  case decimal.compare(value_bounds.minimum, value_bounds.maximum) == Eq {
    True -> { top + bottom } / 2
    False -> {
      let numerator = decimal.subtract(value, value_bounds.minimum)
      let range = decimal.subtract(value_bounds.maximum, value_bounds.minimum)
      let assert Ok(height) = decimal.parse(int.to_string(bottom - top))
      let assert Ok(projected) =
        decimal.divide(
          decimal.multiply(numerator, height),
          by: range,
          scale: 0,
          rounding: decimal.HalfEven,
        )
      let assert Ok(offset) = int.parse(decimal.coefficient(projected))
      bottom - offset
    }
  }
}

fn scaled_height(value: Decimal, maximum: Decimal, height: Int) -> Int {
  case decimal.compare(maximum, decimal.zero()) == Eq {
    True -> 0
    False -> {
      let assert Ok(height_decimal) = decimal.parse(int.to_string(height))
      let assert Ok(projected) =
        decimal.divide(
          decimal.multiply(value, height_decimal),
          by: maximum,
          scale: 0,
          rounding: decimal.HalfEven,
        )
      let assert Ok(result) = int.parse(decimal.coefficient(projected))
      result
    }
  }
}

fn indicator_color(index: Int) -> String {
  case index % 4 {
    0 -> "#f5cb5c"
    1 -> "#a78bfa"
    2 -> "#22d3ee"
    _ -> "#f472b6"
  }
}

fn session_volume_color(session_type: String) -> String {
  case session_type {
    "regular" -> "#486581"
    "half_day" -> "#8b5cf6"
    _ -> "#64748b"
  }
}

fn gap_color(state: String) -> String {
  case state {
    "market_closure" -> "#475569"
    "suspension" -> "#f97316"
    "provider_omission" -> "#dc2626"
    "unavailable_history" -> "#a855f7"
    _ -> "#94a3b8"
  }
}

fn line_json(
  x1: Int,
  y1: Int,
  x2: Int,
  y2: Int,
  width: Int,
  color: String,
) -> Json {
  json.object([
    #("kind", json.string("line")),
    #("x1", json.int(x1)),
    #("y1", json.int(y1)),
    #("x2", json.int(x2)),
    #("y2", json.int(y2)),
    #("width", json.int(width)),
    #("color", json.string(color)),
  ])
}

fn rect_json(x: Int, y: Int, width: Int, height: Int, color: String) -> Json {
  json.object([
    #("kind", json.string("rect")),
    #("x", json.int(x)),
    #("y", json.int(y)),
    #("width", json.int(width)),
    #("height", json.int(height)),
    #("color", json.string(color)),
  ])
}

fn triangle_json(
  x1: Int,
  y1: Int,
  x2: Int,
  y2: Int,
  x3: Int,
  y3: Int,
  color: String,
) -> Json {
  json.object([
    #("kind", json.string("triangle")),
    #("x1", json.int(x1)),
    #("y1", json.int(y1)),
    #("x2", json.int(x2)),
    #("y2", json.int(y2)),
    #("x3", json.int(x3)),
    #("y3", json.int(y3)),
    #("color", json.string(color)),
  ])
}

fn details_json(
  context: ValidatedContext,
  bars: List(ParsedBar),
  indicators: List(ParsedIndicator),
  trades: List(ParsedTrade),
  gaps: List(decode.GapInput),
  input_omissions: List(String),
  date_indexes: Dict(String, Int),
  price_bounds: Bounds,
  lower_bounds: Option(Bounds),
  fallback_table: table.Table,
  omitted_rows: Int,
) -> Json {
  json.object([
    #("schema", json.string("pi-sparkles/finance-chart-result")),
    #("schemaVersion", json.int(1)),
    #("track", json.string(context.input.track)),
    #("trackContext", track_json.to_json(context.shared)),
    #("instrumentId", json.string(context.input.instrument_id)),
    #("mic", json.string(context.input.mic)),
    #("timezone", json.string(context.input.timezone)),
    #("priceUnit", json.string(context.input.price_unit)),
    #("volumeUnit", json.string(context.input.volume_unit)),
    #("adjustment", adjustment_json(context.input.adjustment)),
    #("source", source_json(context.input.source)),
    #("bars", json.array(bars, bar_json)),
    #(
      "indicators",
      json.array(indicators, fn(indicator) {
        indicator_json(indicator, date_indexes)
      }),
    ),
    #(
      "trades",
      json.array(trades, fn(trade) { trade_json(trade, date_indexes) }),
    ),
    #("gaps", json.array(gaps, gap_json)),
    #("inputOmissions", json.array(input_omissions, json.string)),
    #(
      "projection",
      json.object([
        #("kind", json.string("integer_pixel_projection_only")),
        #("width", json.int(image_width)),
        #("height", json.int(image_height)),
        #("mimeType", json.string("image/png")),
        #("priceBounds", bounds_json(price_bounds)),
        #("lowerPanelBounds", json.nullable(lower_bounds, bounds_json)),
        #(
          "indicatorColors",
          json.array(
            indicators
              |> list.index_map(fn(indicator, index) {
                json.object([
                  #("indicatorId", json.string(indicator.input.indicator_id)),
                  #("color", json.string(indicator_color(index))),
                ])
              }),
            fn(value) { value },
          ),
        ),
        #(
          "visualLegend",
          json.object([
            #(
              "candles",
              json.object([
                #("up", json.string("#20b486")),
                #("down", json.string("#ef5b5b")),
                #("flat", json.string("#9aa7bd")),
              ]),
            ),
            #(
              "volumeSessions",
              json.object([
                #("regular", json.string("#486581")),
                #("halfDay", json.string("#8b5cf6")),
                #("unknown", json.string("#64748b")),
              ]),
            ),
            #(
              "tradeMarkers",
              json.object([
                #("buy", json.string("up_triangle_#59a5ff")),
                #("sell", json.string("down_triangle_#f5b942")),
              ]),
            ),
            #(
              "gapLines",
              json.object([
                #("marketClosure", json.string("#475569")),
                #("suspension", json.string("#f97316")),
                #("providerOmission", json.string("#dc2626")),
                #("unavailableHistory", json.string("#a855f7")),
                #("unknown", json.string("#94a3b8")),
              ]),
            ),
          ]),
        ),
      ]),
    ),
    #(
      "structuredFallback",
      json.object([
        #("format", json.string("finance_table_v1")),
        #("table", table_json.to_json(fallback_table)),
        #("omittedRows", json.int(omitted_rows)),
        #("allExactRowsRetainedInDetails", json.bool(True)),
      ]),
    ),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], json.string)),
    #(
      "limitations",
      json.array(
        [
          "view_only_no_analytics",
          "completed_daily_inputs_only",
          "pixel_projection_is_not_source_evidence",
          "no_interpolation_or_gap_inference",
          "no_provider_or_track_fallback",
        ],
        json.string,
      ),
    ),
  ])
}

fn bar_json(bar: ParsedBar) -> Json {
  json.object([
    #("date", json.string(bar.input.date)),
    #("sessionType", json.string(bar.input.session_type)),
    #("open", json.string(bar.input.open)),
    #("high", json.string(bar.input.high)),
    #("low", json.string(bar.input.low)),
    #("close", json.string(bar.input.close)),
    #("volume", json.string(bar.input.volume)),
  ])
}

fn indicator_json(
  indicator: ParsedIndicator,
  date_indexes: Dict(String, Int),
) -> Json {
  json.object([
    #("indicatorId", json.string(indicator.input.indicator_id)),
    #("label", json.string(indicator.input.label)),
    #("panel", json.string(indicator.input.panel)),
    #("unit", json.string(indicator.input.unit)),
    #("warmupSessions", json.int(indicator.input.warmup_sessions)),
    #("calculationReceipt", json.string(indicator.input.calculation_receipt)),
    #(
      "points",
      json.array(indicator.points, fn(point) {
        case point {
          PlottedPoint(date, _, raw) ->
            json.object([
              #("state", json.string("calculated")),
              #("date", json.string(date)),
              #("value", json.string(raw)),
              #("rendered", json.bool(dict.has_key(date_indexes, date))),
              #("renderOmission", case dict.has_key(date_indexes, date) {
                True -> json.null()
                False -> json.string("no_matching_bar_date")
              }),
            ])
          SkippedPoint(date, reason) ->
            json.object([
              #("state", json.string("unperformed")),
              #("date", json.string(date)),
              #("reason", json.string(reason)),
              #("rendered", json.bool(False)),
              #("renderOmission", json.string("unperformed")),
            ])
        }
      }),
    ),
  ])
}

fn trade_json(trade: ParsedTrade, date_indexes: Dict(String, Int)) -> Json {
  let rendered = dict.has_key(date_indexes, trade.input.date)
  json.object([
    #("tradeId", json.string(trade.input.trade_id)),
    #("date", json.string(trade.input.date)),
    #("side", json.string(trade.input.side)),
    #("price", json.string(trade.input.price)),
    #("quantity", json.string(trade.input.quantity)),
    #("status", json.string(trade.input.status)),
    #("evidenceReceipt", json.string(trade.input.evidence_receipt)),
    #("rendered", json.bool(rendered)),
    #("renderOmission", case rendered {
      True -> json.null()
      False -> json.string("no_matching_bar_date")
    }),
  ])
}

fn gap_json(gap: decode.GapInput) -> Json {
  json.object([
    #("date", json.string(gap.date)),
    #("state", json.string(gap.state)),
    #("reason", json.string(gap.reason)),
    #("evidenceRoots", json.array(gap.evidence_roots, json.string)),
  ])
}

fn source_json(source: decode.SourceInput) -> Json {
  json.object([
    #("provider", json.string(source.provider)),
    #("sourceReference", json.string(source.source_reference)),
    #("acquisitionReceipt", json.string(source.acquisition_receipt)),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(source.retrieved_at_unix_milliseconds),
    ),
    #(
      "sourceCutoffUnixMilliseconds",
      json.nullable(source.source_cutoff_unix_milliseconds, json.int),
    ),
    #("entitlement", json.string(source.entitlement)),
  ])
}

fn adjustment_json(adjustment: decode.AdjustmentInput) -> Json {
  json.object([
    #("kind", json.string(adjustment.kind)),
    #("label", json.nullable(adjustment.label, json.string)),
  ])
}

fn bounds_json(value: Bounds) -> Json {
  json.object([
    #("minimum", json.string(decimal.to_string(value.minimum))),
    #("maximum", json.string(decimal.to_string(value.maximum))),
  ])
}

fn adjustment_text(value: decode.AdjustmentInput) -> String {
  case value.label {
    Some(label) -> value.kind <> " (" <> label <> ")"
    None -> value.kind
  }
}

fn optional_instant_text(value: Option(Int)) -> String {
  case value {
    Some(value) -> int.to_string(value)
    None -> "unknown"
  }
}

fn require_hash(field: String, value: String) -> Result(Nil, DomainError) {
  case is_sha256(value) {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "expected lowercase SHA-256"))
  }
}

fn is_sha256(value: String) -> Bool {
  string.length(value) == 64
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) { string.contains("0123456789abcdef", character) })
  }
}

fn require_text(field: String, value: String) -> Result(Nil, DomainError) {
  case valid_text(value) {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "must be non-empty and unpadded"))
  }
}

fn valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
