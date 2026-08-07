import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/fact.{type Fact, Known}
import finance_replay/wire
import gleam/json
import gleam/list
import gleam/order.{Eq, Gt, Lt}
import gleam/result

pub type Metadata {
  Metadata(
    request_id: String,
    formula: String,
    version: String,
    unit: String,
    scale: Int,
    rounding: RoundingMode,
    missing_conflict_policy: String,
    sample_population: String,
    ordering: String,
    benchmark: Fact(Sha256),
    source_receipts: List(Sha256),
  )
}

pub type DecimalInput {
  DecimalInput(name: String, exact_lexeme: String, source_receipt: Sha256)
}

pub type CalculationValue {
  ExactDecimal(exact_lexeme: String)
  Counts(win: Int, loss: Int, tie: Int)
  DrawdownSeries(points: List(DrawdownPoint))
  TradeList(trades: List(Trade))
  Unperformed(reason: String, operands: List(String))
}

pub type DrawdownPoint {
  DrawdownPoint(
    label: String,
    equity_lexeme: String,
    running_peak_lexeme: String,
    drawdown_lexeme: String,
    source_receipt: Sha256,
  )
}

pub type TradePnl {
  TradePnl(trade_id: String, net_pnl_lexeme: String, source_receipt: Sha256)
}

pub type Trade {
  Trade(
    trade_id: String,
    instruction_receipt: Sha256,
    lifecycle_receipts: List(Sha256),
    exact_payload: String,
  )
}

pub opaque type Calculation {
  Calculation(
    metadata: Metadata,
    ordered_inputs: List(DecimalInput),
    value: CalculationValue,
    digest: Sha256,
  )
}

pub type MetricError {
  InvalidText(field: String)
  InvalidScale
  InvalidDecimal(field: String, lexeme: String)
  DuplicateInput(String)
  DuplicateReceipt(String)
  EmptyInput
}

pub fn net_return(
  metadata: Metadata,
  denominator: Fact(DecimalInput),
  ending_value: Fact(DecimalInput),
) -> Result(Calculation, MetricError) {
  use _ <- result.try(validate_metadata(metadata))
  case denominator, ending_value {
    Known(denominator), Known(ending) -> {
      use denominator_decimal <- result.try(parse_input(denominator))
      use ending_decimal <- result.try(parse_input(ending))
      let Metadata(_, _, _, _, scale, rounding, ..) = metadata
      case
        denominator_decimal
        |> decimal.subtract(ending_decimal)
        |> decimal.negate
        |> decimal.divide(denominator_decimal, scale, rounding)
      {
        Error(_) ->
          calculation(
            metadata,
            [denominator, ending],
            Unperformed("denominator is zero", [denominator.name]),
          )
        Ok(value) ->
          calculation(
            metadata,
            [denominator, ending],
            ExactDecimal(decimal.to_string(value)),
          )
      }
    }
    _, _ ->
      calculation(
        metadata,
        known_inputs([denominator, ending_value]),
        Unperformed("one or more requested net-return operands are not known", [
          "denominator",
          "ending_value",
        ]),
      )
  }
}

pub fn win_loss_counts(
  metadata: Metadata,
  trades: List(TradePnl),
  zero_policy: String,
) -> Result(Calculation, MetricError) {
  use _ <- result.try(validate_metadata(metadata))
  use _ <- result.try(validate_text(zero_policy, "zero_policy"))
  case trades {
    [] -> Error(EmptyInput)
    _ -> {
      use inputs <- result.try(parse_trade_pnls(trades, [], []))
      let #(ordered_inputs, values) = inputs
      let #(wins, losses, ties) = count_signs(values, 0, 0, 0)
      calculation(metadata, ordered_inputs, Counts(wins, losses, ties))
    }
  }
}

pub fn drawdown_series(
  metadata: Metadata,
  equity_points: List(#(String, DecimalInput)),
  peak_convention: String,
) -> Result(Calculation, MetricError) {
  use _ <- result.try(validate_metadata(metadata))
  use _ <- result.try(validate_text(peak_convention, "peak_convention"))
  case equity_points {
    [] -> Error(EmptyInput)
    [#(first_label, first_input), ..rest] -> {
      use _ <- result.try(validate_text(first_label, "point_label"))
      use first_value <- result.try(parse_input(first_input))
      let Metadata(_, _, _, _, scale, rounding, ..) = metadata
      use points <- result.try(
        drawdown_loop(rest, first_value, scale, rounding, [
          DrawdownPoint(
            first_label,
            first_input.exact_lexeme,
            decimal.to_string(first_value),
            decimal.to_string(decimal.zero()),
            first_input.source_receipt,
          ),
        ]),
      )
      calculation(
        metadata,
        equity_points |> list.map(fn(value) { value.1 }),
        DrawdownSeries(points),
      )
    }
  }
}

pub fn trade_list(
  metadata: Metadata,
  trades: List(Trade),
) -> Result(Calculation, MetricError) {
  use _ <- result.try(validate_metadata(metadata))
  use _ <- result.try(validate_trades(trades, []))
  calculation(metadata, [], TradeList(trades))
}

fn calculation(
  metadata: Metadata,
  ordered_inputs: List(DecimalInput),
  value: CalculationValue,
) -> Result(Calculation, MetricError) {
  use _ <- result.try(validate_inputs(ordered_inputs, []))
  let payload = payload(metadata, ordered_inputs, value)
  let assert Ok(digest) = payload |> json.to_string |> hash.text
  Ok(Calculation(metadata, ordered_inputs, value, digest))
}

fn drawdown_loop(
  remaining: List(#(String, DecimalInput)),
  peak: Decimal,
  scale: Int,
  rounding: RoundingMode,
  reversed: List(DrawdownPoint),
) -> Result(List(DrawdownPoint), MetricError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [#(label, input), ..rest] -> {
      use _ <- result.try(validate_text(label, "point_label"))
      use value <- result.try(parse_input(input))
      let next_peak = case decimal.compare(value, peak) {
        Gt -> value
        _ -> peak
      }
      case
        decimal.divide(
          decimal.subtract(next_peak, value),
          next_peak,
          scale,
          rounding,
        )
      {
        Error(_) ->
          Error(InvalidDecimal("running_peak", decimal.to_string(next_peak)))
        Ok(drawdown) ->
          drawdown_loop(rest, next_peak, scale, rounding, [
            DrawdownPoint(
              label,
              input.exact_lexeme,
              decimal.to_string(next_peak),
              decimal.to_string(drawdown),
              input.source_receipt,
            ),
            ..reversed
          ])
      }
    }
  }
}

fn parse_trade_pnls(
  values: List(TradePnl),
  reversed_inputs: List(DecimalInput),
  reversed_values: List(Decimal),
) -> Result(#(List(DecimalInput), List(Decimal)), MetricError) {
  case values {
    [] -> Ok(#(list.reverse(reversed_inputs), list.reverse(reversed_values)))
    [TradePnl(id, lexeme, source), ..rest] -> {
      use _ <- result.try(validate_text(id, "trade_id"))
      let input = DecimalInput(id, lexeme, source)
      use parsed <- result.try(parse_input(input))
      parse_trade_pnls(rest, [input, ..reversed_inputs], [
        parsed,
        ..reversed_values
      ])
    }
  }
}

fn count_signs(
  values: List(Decimal),
  wins: Int,
  losses: Int,
  ties: Int,
) -> #(Int, Int, Int) {
  case values {
    [] -> #(wins, losses, ties)
    [value, ..rest] ->
      case decimal.compare(value, decimal.zero()) {
        Gt -> count_signs(rest, wins + 1, losses, ties)
        Lt -> count_signs(rest, wins, losses + 1, ties)
        Eq -> count_signs(rest, wins, losses, ties + 1)
      }
  }
}

fn known_inputs(values: List(Fact(DecimalInput))) -> List(DecimalInput) {
  values
  |> list.filter_map(fn(value) {
    case value {
      Known(value) -> Ok(value)
      _ -> Error(Nil)
    }
  })
}

fn parse_input(value: DecimalInput) -> Result(Decimal, MetricError) {
  case decimal.parse(value.exact_lexeme) {
    Ok(parsed) -> Ok(parsed)
    Error(_) -> Error(InvalidDecimal(value.name, value.exact_lexeme))
  }
}

fn validate_metadata(value: Metadata) -> Result(Nil, MetricError) {
  let Metadata(
    request_id,
    formula,
    version,
    unit,
    scale,
    _,
    missing_policy,
    sample,
    ordering,
    _,
    receipts,
  ) = value
  use _ <- result.try(validate_text(request_id, "request_id"))
  use _ <- result.try(validate_text(formula, "formula"))
  use _ <- result.try(validate_text(version, "version"))
  use _ <- result.try(validate_text(unit, "unit"))
  use _ <- result.try(validate_text(missing_policy, "missing_conflict_policy"))
  use _ <- result.try(validate_text(sample, "sample_population"))
  use _ <- result.try(validate_text(ordering, "ordering"))
  use _ <- result.try(validate_receipts(receipts, []))
  case scale < 0 {
    True -> Error(InvalidScale)
    False -> Ok(Nil)
  }
}

fn validate_inputs(
  values: List(DecimalInput),
  seen: List(String),
) -> Result(Nil, MetricError) {
  case values {
    [] -> Ok(Nil)
    [DecimalInput(name, lexeme, _), ..rest] -> {
      use _ <- result.try(validate_text(name, "input_name"))
      use _ <- result.try(
        parse_input(DecimalInput(name, lexeme, wire.placeholder_sha())),
      )
      case list.contains(seen, name) {
        True -> Error(DuplicateInput(name))
        False -> validate_inputs(rest, [name, ..seen])
      }
    }
  }
}

fn validate_trades(
  values: List(Trade),
  seen: List(String),
) -> Result(Nil, MetricError) {
  case values {
    [] -> Ok(Nil)
    [Trade(id, _, lifecycle, payload), ..rest] -> {
      use _ <- result.try(validate_text(id, "trade_id"))
      use _ <- result.try(validate_text(payload, "trade_payload"))
      use _ <- result.try(validate_receipts(lifecycle, []))
      case list.contains(seen, id) {
        True -> Error(DuplicateInput(id))
        False -> validate_trades(rest, [id, ..seen])
      }
    }
  }
}

fn validate_receipts(
  values: List(Sha256),
  seen: List(String),
) -> Result(Nil, MetricError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      let text = identity.sha256_value(value)
      case list.contains(seen, text) {
        True -> Error(DuplicateReceipt(text))
        False -> validate_receipts(rest, [text, ..seen])
      }
    }
  }
}

fn validate_text(value: String, field: String) -> Result(Nil, MetricError) {
  case wire.valid_text(value, 65_536) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

pub fn as_json(value: Calculation) -> json.Json {
  json.object([
    #("payload", payload(value.metadata, value.ordered_inputs, value.value)),
    #("canonical_content_hash", wire.sha_json(value.digest)),
  ])
}

fn payload(
  metadata: Metadata,
  ordered_inputs: List(DecimalInput),
  value: CalculationValue,
) -> json.Json {
  let Metadata(
    request_id,
    formula,
    version,
    unit,
    scale,
    rounding,
    missing_policy,
    sample,
    ordering,
    benchmark,
    source_receipts,
  ) = metadata
  json.object([
    #("schema", json.string("finance_replay_requested_calculation")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("request_id", json.string(request_id)),
    #("formula", json.string(formula)),
    #("formula_version", json.string(version)),
    #("unit", json.string(unit)),
    #("scale", json.int(scale)),
    #("rounding", rounding |> rounding_name |> json.string),
    #("missing_conflict_policy", json.string(missing_policy)),
    #("sample_population", json.string(sample)),
    #("ordering", json.string(ordering)),
    #("benchmark", fact.to_json(benchmark, wire.sha_json)),
    #("source_receipts", json.array(source_receipts, wire.sha_json)),
    #("ordered_inputs", json.array(ordered_inputs, input_json)),
    #("result", value_json(value)),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

fn input_json(value: DecimalInput) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #("exact_lexeme", json.string(value.exact_lexeme)),
    #("source_receipt", wire.sha_json(value.source_receipt)),
  ])
}

fn value_json(value: CalculationValue) -> json.Json {
  case value {
    ExactDecimal(value) ->
      json.object([
        #("state", json.string("calculated")),
        #("exact_decimal", json.string(value)),
      ])
    Counts(win, loss, tie) ->
      json.object([
        #("state", json.string("calculated")),
        #("win", json.int(win)),
        #("loss", json.int(loss)),
        #("tie", json.int(tie)),
      ])
    DrawdownSeries(points) ->
      json.object([
        #("state", json.string("calculated")),
        #("points", json.array(points, drawdown_json)),
      ])
    TradeList(trades) ->
      json.object([
        #("state", json.string("calculated")),
        #("trades", json.array(trades, trade_json)),
      ])
    Unperformed(reason, operands) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
        #("operands", json.array(operands, json.string)),
      ])
  }
}

fn drawdown_json(value: DrawdownPoint) -> json.Json {
  json.object([
    #("label", json.string(value.label)),
    #("equity", json.string(value.equity_lexeme)),
    #("running_peak", json.string(value.running_peak_lexeme)),
    #("drawdown", json.string(value.drawdown_lexeme)),
    #("source_receipt", wire.sha_json(value.source_receipt)),
  ])
}

fn trade_json(value: Trade) -> json.Json {
  json.object([
    #("trade_id", json.string(value.trade_id)),
    #("instruction_receipt", wire.sha_json(value.instruction_receipt)),
    #("lifecycle_receipts", json.array(value.lifecycle_receipts, wire.sha_json)),
    #("exact_payload", json.string(value.exact_payload)),
  ])
}

fn rounding_name(value: RoundingMode) -> String {
  case value {
    decimal.TowardZero -> "toward_zero"
    decimal.AwayFromZero -> "away_from_zero"
    decimal.HalfUp -> "half_up"
    decimal.HalfEven -> "half_even"
  }
}

pub fn value(value: Calculation) -> CalculationValue {
  value.value
}

pub fn content_hash(value: Calculation) -> Sha256 {
  value.digest
}
