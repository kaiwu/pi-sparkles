import finance_core/decimal
import finance_journal/receipt.{type Envelope}
import finance_provenance/identity.{type Sha256}
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type CashFlowRole {
  Entry
  Exit
}

pub type FillInput {
  FillInput(
    fill_id: String,
    role: CashFlowRole,
    quantity_lexeme: String,
    price_lexeme: String,
    source_receipt: Sha256,
  )
}

pub type CostInput {
  CostInput(cost_id: String, amount_lexeme: String, source_receipt: Sha256)
}

pub opaque type NetPnl {
  NetPnl(
    instruction_receipt: Sha256,
    currency: String,
    scale: Int,
    rounding: decimal.RoundingMode,
    fills: List(FillInput),
    costs: List(CostInput),
    entry_notional: decimal.Decimal,
    exit_notional: decimal.Decimal,
    total_costs: decimal.Decimal,
    gross_pnl: decimal.Decimal,
    net_pnl: decimal.Decimal,
  )
}

pub type MetricError {
  EmptyFills
  MissingEntry
  MissingExit
  InvalidText(field: String)
  InvalidDecimal(field: String, lexeme: String)
  NegativeScale
  DuplicateInputId(id: String)
}

pub fn long_cash_realized_net_pnl(
  instruction_receipt instruction: Sha256,
  currency currency_value: String,
  scale scale_value: Int,
  rounding rounding_value: decimal.RoundingMode,
  fills fill_values: List(FillInput),
  costs cost_values: List(CostInput),
) -> Result(NetPnl, MetricError) {
  use _ <- result.try(validate_text(currency_value, "currency"))
  case scale_value < 0, fill_values {
    True, _ -> Error(NegativeScale)
    _, [] -> Error(EmptyFills)
    False, _ -> {
      use _ <- result.try(validate_ids(fill_values, cost_values, []))
      use parsed_fills <- result.try(parse_fills(fill_values, []))
      use parsed_costs <- result.try(parse_costs(cost_values, []))
      let entries =
        parsed_fills
        |> list.filter(fn(value) { value.0 == Entry })
        |> list.map(fn(value) { value.1 })
      let exits =
        parsed_fills
        |> list.filter(fn(value) { value.0 == Exit })
        |> list.map(fn(value) { value.1 })
      case entries, exits {
        [], _ -> Error(MissingEntry)
        _, [] -> Error(MissingExit)
        _, _ -> {
          let entry_notional = sum(entries)
          let exit_notional = sum(exits)
          let total_costs =
            parsed_costs |> list.map(fn(value) { value.1 }) |> sum
          let gross = decimal.subtract(exit_notional, entry_notional)
          let net = decimal.subtract(gross, total_costs)
          let assert Ok(entry_rounded) =
            decimal.quantize(entry_notional, scale_value, rounding_value)
          let assert Ok(exit_rounded) =
            decimal.quantize(exit_notional, scale_value, rounding_value)
          let assert Ok(costs_rounded) =
            decimal.quantize(total_costs, scale_value, rounding_value)
          let assert Ok(gross_rounded) =
            decimal.quantize(gross, scale_value, rounding_value)
          let assert Ok(net_rounded) =
            decimal.quantize(net, scale_value, rounding_value)
          Ok(NetPnl(
            instruction,
            currency_value,
            scale_value,
            rounding_value,
            fill_values,
            cost_values,
            entry_rounded,
            exit_rounded,
            costs_rounded,
            gross_rounded,
            net_rounded,
          ))
        }
      }
    }
  }
}

fn parse_fills(
  values: List(FillInput),
  reversed: List(#(CashFlowRole, decimal.Decimal)),
) -> Result(List(#(CashFlowRole, decimal.Decimal)), MetricError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [FillInput(id, role, quantity, price, _), ..rest] ->
      case decimal.parse(quantity), decimal.parse(price) {
        Error(_), _ -> Error(InvalidDecimal("fill_quantity:" <> id, quantity))
        _, Error(_) -> Error(InvalidDecimal("fill_price:" <> id, price))
        Ok(quantity), Ok(price) ->
          parse_fills(rest, [
            #(role, decimal.multiply(quantity, price)),
            ..reversed
          ])
      }
  }
}

fn parse_costs(
  values: List(CostInput),
  reversed: List(#(String, decimal.Decimal)),
) -> Result(List(#(String, decimal.Decimal)), MetricError) {
  case values {
    [] -> Ok(list.reverse(reversed))
    [CostInput(id, amount, _), ..rest] ->
      case decimal.parse(amount) {
        Error(_) -> Error(InvalidDecimal("cost:" <> id, amount))
        Ok(value) -> parse_costs(rest, [#(id, value), ..reversed])
      }
  }
}

fn validate_ids(
  fills: List(FillInput),
  costs: List(CostInput),
  seen: List(String),
) -> Result(Nil, MetricError) {
  case fills {
    [FillInput(id, _, _, _, _), ..rest] -> {
      use _ <- result.try(validate_text(id, "fill_id"))
      case list.contains(seen, id) {
        True -> Error(DuplicateInputId(id))
        False -> validate_ids(rest, costs, [id, ..seen])
      }
    }
    [] -> validate_cost_ids(costs, seen)
  }
}

fn validate_cost_ids(
  values: List(CostInput),
  seen: List(String),
) -> Result(Nil, MetricError) {
  case values {
    [] -> Ok(Nil)
    [CostInput(id, _, _), ..rest] -> {
      use _ <- result.try(validate_text(id, "cost_id"))
      case list.contains(seen, id) {
        True -> Error(DuplicateInputId(id))
        False -> validate_cost_ids(rest, [id, ..seen])
      }
    }
  }
}

fn sum(values: List(decimal.Decimal)) -> decimal.Decimal {
  list.fold(values, decimal.zero(), decimal.add)
}

pub fn receipt(value: NetPnl) -> Envelope {
  json.object([
    #("schema", json.string("pi-sparkles/journal-metric-result")),
    #("schema_version", json.int(1)),
    #("metric", json.string("long_cash_realized_net_pnl_v1")),
    #("decision_owner", json.string("llm")),
    #(
      "instruction_receipt",
      value.instruction_receipt |> identity.sha256_value |> json.string,
    ),
    #("currency", json.string(value.currency)),
    #("scale", json.int(value.scale)),
    #("rounding", value.rounding |> rounding_name |> json.string),
    #("fills", json.array(value.fills, fill_json)),
    #("costs", json.array(value.costs, cost_json)),
    #(
      "components",
      json.object([
        #(
          "entry_notional",
          value.entry_notional |> format_scale(value.scale) |> json.string,
        ),
        #(
          "exit_notional",
          value.exit_notional |> format_scale(value.scale) |> json.string,
        ),
        #(
          "gross_pnl",
          value.gross_pnl |> format_scale(value.scale) |> json.string,
        ),
        #(
          "total_costs",
          value.total_costs |> format_scale(value.scale) |> json.string,
        ),
        #("net_pnl", value.net_pnl |> format_scale(value.scale) |> json.string),
      ]),
    ),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
    #(
      "available_operations",
      json.array(
        [
          "inspect_fill_receipt",
          "inspect_cost_receipt",
          "request_different_metric",
          "attach_review_conclusion",
        ],
        json.string,
      ),
    ),
  ])
  |> receipt.envelope
}

fn fill_json(value: FillInput) -> json.Json {
  let FillInput(id, role, quantity, price, source) = value
  json.object([
    #("fill_id", json.string(id)),
    #("role", role |> role_name |> json.string),
    #("quantity_lexeme", json.string(quantity)),
    #("price_lexeme", json.string(price)),
    #("source_receipt", source |> identity.sha256_value |> json.string),
  ])
}

fn cost_json(value: CostInput) -> json.Json {
  let CostInput(id, amount, source) = value
  json.object([
    #("cost_id", json.string(id)),
    #("amount_lexeme", json.string(amount)),
    #("source_receipt", source |> identity.sha256_value |> json.string),
  ])
}

fn role_name(value: CashFlowRole) -> String {
  case value {
    Entry -> "entry"
    Exit -> "exit"
  }
}

fn rounding_name(value: decimal.RoundingMode) -> String {
  case value {
    decimal.TowardZero -> "toward_zero"
    decimal.AwayFromZero -> "away_from_zero"
    decimal.HalfUp -> "half_up"
    decimal.HalfEven -> "half_even"
  }
}

fn format_scale(value: decimal.Decimal, scale: Int) -> String {
  let rendered = decimal.to_string(value)
  let current = decimal.scale(value)
  case scale - current {
    missing if missing <= 0 -> rendered
    missing ->
      case current {
        0 -> rendered <> "." <> string.repeat("0", missing)
        _ -> rendered <> string.repeat("0", missing)
      }
  }
}

fn validate_text(value: String, field: String) -> Result(Nil, MetricError) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

pub fn net_pnl(value: NetPnl) -> decimal.Decimal {
  value.net_pnl
}

pub fn gross_pnl(value: NetPnl) -> decimal.Decimal {
  value.gross_pnl
}

pub fn total_costs(value: NetPnl) -> decimal.Decimal {
  value.total_costs
}
