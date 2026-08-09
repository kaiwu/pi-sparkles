import finance_calendar/date
import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/time.{type Date}
import finance_math/formula.{type Formula}
import finance_provenance/hash
import finance_provenance/identity
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt}
import gleam/result
import gleam/string
import pi_sparkles_investor_workbench/decode

pub type Response {
  Response(summary: String, details: Json)
}

pub type Error {
  InvalidField(field: String, reason: String)
  InvalidReceipt(field: String)
  DuplicateOperand(name: String)
  UnexpectedOperand(name: String)
}

type MetricSpec {
  MetricSpec(
    expected: List(#(String, String)),
    expression: Formula,
    denominator: Option(String),
    output_unit: String,
  )
}

pub fn error_message(value: Error) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid dossier metric field " <> field <> ": " <> reason
    InvalidReceipt(field) ->
      "Invalid SHA-256 receipt in dossier metric field " <> field
    DuplicateOperand(name) -> "Dossier metric repeats operand " <> name
    UnexpectedOperand(name) ->
      "Dossier metric received unexpected operand " <> name
  }
}

pub fn calculate(input: decode.MetricInput) -> Result(Response, Error) {
  use _ <- result.try(nonblank("requestId", input.request_id))
  use rounding <- result.try(rounding_mode(input.rounding))
  use _ <- result.try(case input.output_scale >= 0 && input.output_scale <= 18 {
    True -> Ok(Nil)
    False -> Error(InvalidField("outputScale", "must be between 0 and 18"))
  })
  use spec <- result.try(metric_spec(
    input.metric_id,
    input.output_scale,
    rounding,
  ))
  use _ <- result.try(validate_operands(input.operands, spec))
  let MetricSpec(expected, expression, denominator, output_unit) = spec
  let missing =
    expected
    |> list.filter_map(fn(contract) {
      case list.find(input.operands, fn(value) { value.name == contract.0 }) {
        Ok(_) -> Error(Nil)
        Error(_) -> Ok(contract.0)
      }
    })
  case missing {
    [_, ..] ->
      Ok(unperformed(
        input,
        expression,
        output_unit,
        "missing_operands",
        missing,
        None,
      ))
    [] ->
      case context_issue(input.metric_id, input.operands, expected) {
        Some(issue) ->
          Ok(unperformed(input, expression, output_unit, issue, [], None))
        None ->
          case decimal_inputs(input.operands) {
            Error(name) ->
              Ok(unperformed(
                input,
                expression,
                output_unit,
                "invalid_numeric_operand",
                [],
                Some(name),
              ))
            Ok(values) ->
              case denominator_issue(denominator, input.operands) {
                Some(issue) ->
                  Ok(unperformed(
                    input,
                    expression,
                    output_unit,
                    issue,
                    [],
                    denominator,
                  ))
                None ->
                  case formula.evaluate(expression, with: values) {
                    Error(error) ->
                      Ok(unperformed(
                        input,
                        expression,
                        output_unit,
                        "calculation_unperformed:" <> string.inspect(error),
                        [],
                        None,
                      ))
                    Ok(value) ->
                      Ok(calculated(input, expression, output_unit, value))
                  }
              }
          }
      }
  }
}

fn metric_spec(
  metric_id: String,
  scale: Int,
  rounding: RoundingMode,
) -> Result(MetricSpec, Error) {
  let reference = fn(name) { formula.Reference(name) }
  let divide = fn(numerator, denominator) {
    formula.Divide(numerator, denominator, scale, rounding)
  }
  case metric_id {
    "current_ratio" ->
      Ok(MetricSpec(
        [#("current_assets", "currency"), #("current_liabilities", "currency")],
        divide(reference("current_assets"), reference("current_liabilities")),
        Some("current_liabilities"),
        "ratio",
      ))
    "debt_to_equity" ->
      Ok(MetricSpec(
        [#("total_debt", "currency"), #("total_equity", "currency")],
        divide(reference("total_debt"), reference("total_equity")),
        Some("total_equity"),
        "ratio",
      ))
    "gross_margin" ->
      Ok(MetricSpec(
        [#("revenue", "currency"), #("cogs", "currency")],
        divide(
          formula.Subtract(reference("revenue"), reference("cogs")),
          reference("revenue"),
        ),
        Some("revenue"),
        "ratio",
      ))
    "operating_margin" ->
      Ok(MetricSpec(
        [#("operating_income", "currency"), #("revenue", "currency")],
        divide(reference("operating_income"), reference("revenue")),
        Some("revenue"),
        "ratio",
      ))
    "net_margin" ->
      Ok(MetricSpec(
        [#("net_income", "currency"), #("revenue", "currency")],
        divide(reference("net_income"), reference("revenue")),
        Some("revenue"),
        "ratio",
      ))
    "revenue_growth" ->
      Ok(MetricSpec(
        [#("current_revenue", "currency"), #("prior_revenue", "currency")],
        divide(
          formula.Subtract(
            reference("current_revenue"),
            reference("prior_revenue"),
          ),
          formula.Absolute(reference("prior_revenue")),
        ),
        Some("prior_revenue"),
        "ratio",
      ))
    "fcf_conversion" ->
      Ok(MetricSpec(
        [#("operating_cash_flow", "currency"), #("net_income", "currency")],
        divide(reference("operating_cash_flow"), reference("net_income")),
        Some("net_income"),
        "ratio",
      ))
    "interest_coverage" ->
      Ok(MetricSpec(
        [#("operating_income", "currency"), #("interest_expense", "currency")],
        divide(reference("operating_income"), reference("interest_expense")),
        Some("interest_expense"),
        "ratio",
      ))
    "bvps" ->
      Ok(MetricSpec(
        [#("total_equity", "currency"), #("diluted_shares", "shares")],
        divide(reference("total_equity"), reference("diluted_shares")),
        Some("diluted_shares"),
        "currency_per_share",
      ))
    "eps" ->
      Ok(MetricSpec(
        [#("net_income", "currency"), #("diluted_shares", "shares")],
        divide(reference("net_income"), reference("diluted_shares")),
        Some("diluted_shares"),
        "currency_per_share",
      ))
    "dividend_yield" ->
      Ok(MetricSpec(
        [
          #("annual_dividend", "currency_per_share"),
          #("share_price", "currency_per_share"),
        ],
        divide(reference("annual_dividend"), reference("share_price")),
        Some("share_price"),
        "ratio",
      ))
    "payout_ratio" ->
      Ok(MetricSpec(
        [#("dividends", "currency"), #("net_income", "currency")],
        divide(reference("dividends"), reference("net_income")),
        Some("net_income"),
        "ratio",
      ))
    "net_interest_margin" ->
      Ok(MetricSpec(
        [
          #("interest_income", "currency"),
          #("interest_expense", "currency"),
          #("average_earning_assets", "currency"),
        ],
        divide(
          formula.Subtract(
            reference("interest_income"),
            reference("interest_expense"),
          ),
          reference("average_earning_assets"),
        ),
        Some("average_earning_assets"),
        "ratio",
      ))
    "combined_ratio" ->
      Ok(MetricSpec(
        [
          #("claims", "currency"),
          #("expenses", "currency"),
          #("premiums_earned", "currency"),
        ],
        divide(
          formula.Add(reference("claims"), reference("expenses")),
          reference("premiums_earned"),
        ),
        Some("premiums_earned"),
        "ratio",
      ))
    "reit_ffo" ->
      Ok(MetricSpec(
        [
          #("net_income", "currency"),
          #("depreciation", "currency"),
          #("gains_on_sales", "currency"),
        ],
        formula.Subtract(
          formula.Add(reference("net_income"), reference("depreciation")),
          reference("gains_on_sales"),
        ),
        None,
        "currency",
      ))
    "reit_affo" ->
      Ok(MetricSpec(
        [
          #("net_income", "currency"),
          #("depreciation", "currency"),
          #("gains_on_sales", "currency"),
          #("maintenance_capex", "currency"),
        ],
        formula.Subtract(
          formula.Subtract(
            formula.Add(reference("net_income"), reference("depreciation")),
            reference("gains_on_sales"),
          ),
          reference("maintenance_capex"),
        ),
        None,
        "currency",
      ))
    "reserve_life" ->
      Ok(MetricSpec(
        [
          #("proven_reserves", "reserves"),
          #("annual_production", "reserves_per_year"),
        ],
        divide(reference("proven_reserves"), reference("annual_production")),
        Some("annual_production"),
        "years",
      ))
    "cash_runway" ->
      Ok(MetricSpec(
        [
          #("cash_balance", "currency"),
          #("quarterly_burn_rate", "currency_per_quarter"),
        ],
        divide(reference("cash_balance"), reference("quarterly_burn_rate")),
        Some("quarterly_burn_rate"),
        "quarters",
      ))
    _ -> Error(InvalidField("metricId", "unsupported Session 19 metric"))
  }
}

fn validate_operands(
  operands: List(decode.OperandInput),
  spec: MetricSpec,
) -> Result(Nil, Error) {
  let MetricSpec(expected, _, _, _) = spec
  validate_operand_loop(operands, expected, [])
}

fn validate_operand_loop(
  operands: List(decode.OperandInput),
  expected: List(#(String, String)),
  seen: List(String),
) -> Result(Nil, Error) {
  case operands {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(case list.contains(seen, value.name) {
        True -> Error(DuplicateOperand(value.name))
        False -> Ok(Nil)
      })
      use _ <- result.try(
        case list.any(expected, fn(contract) { contract.0 == value.name }) {
          True -> Ok(Nil)
          False -> Error(UnexpectedOperand(value.name))
        },
      )
      use _ <- result.try(nonblank("operands[].entityId", value.entity_id))
      use _ <- result.try(nonblank("operands[].currency", value.currency))
      use _ <- result.try(nonblank("operands[].unit", value.unit))
      use _ <- result.try(parse_date("operands[].periodEnd", value.period_end))
      use _ <- result.try(case value.period_start {
        None -> Ok(Nil)
        Some(text) ->
          parse_date("operands[].periodStart", text)
          |> result.map(fn(_) { Nil })
      })
      use _ <- result.try(case value.period_kind {
        "instant" | "annual" | "interim" | "quarter" | "semi_annual" -> Ok(Nil)
        _ -> Error(InvalidField("operands[].periodKind", "unknown period kind"))
      })
      use _ <- result.try(
        case value.reported_scale >= -18 && value.reported_scale <= 18 {
          True -> Ok(Nil)
          False ->
            Error(InvalidField(
              "operands[].reportedScale",
              "must be between -18 and 18",
            ))
        },
      )
      use _ <- result.try(case value.basis {
        "statement_fact"
        | "consensus_estimate"
        | "caller_declared"
        | "historical_average" -> Ok(Nil)
        _ -> Error(InvalidField("operands[].basis", "unknown assumption basis"))
      })
      use _ <- result.try(
        identity.sha256(value.source_receipt)
        |> result.map(fn(_) { Nil })
        |> result.map_error(fn(_) { InvalidReceipt("operands[].sourceReceipt") }),
      )
      validate_operand_loop(rest, expected, [value.name, ..seen])
    }
  }
}

fn context_issue(
  metric_id: String,
  operands: List(decode.OperandInput),
  expected: List(#(String, String)),
) -> Option(String) {
  let assert [first, ..] = operands
  case list.all(operands, fn(value) { value.entity_id == first.entity_id }) {
    False -> Some("incompatible_entities")
    True ->
      case list.all(operands, fn(value) { value.currency == first.currency }) {
        False -> Some("incompatible_currencies")
        True ->
          case
            list.all(operands, fn(value) {
              value.reported_scale == first.reported_scale
            })
          {
            False -> Some("incompatible_reported_scales")
            True ->
              case units_match(operands, expected) {
                False -> Some("incompatible_operand_units")
                True ->
                  case metric_id {
                    "revenue_growth" -> revenue_growth_period_issue(operands)
                    _ ->
                      case
                        list.all(operands, fn(value) {
                          value.period_end == first.period_end
                        })
                      {
                        True -> None
                        False -> Some("incompatible_period_ends")
                      }
                  }
              }
          }
      }
  }
}

fn units_match(
  operands: List(decode.OperandInput),
  expected: List(#(String, String)),
) -> Bool {
  list.all(expected, fn(contract) {
    case list.find(operands, fn(value) { value.name == contract.0 }) {
      Ok(value) -> value.unit == contract.1
      Error(_) -> False
    }
  })
}

fn revenue_growth_period_issue(
  operands: List(decode.OperandInput),
) -> Option(String) {
  let assert Ok(current) =
    list.find(operands, fn(value) { value.name == "current_revenue" })
  let assert Ok(prior) =
    list.find(operands, fn(value) { value.name == "prior_revenue" })
  let assert Ok(current_end) = parse_date("current", current.period_end)
  let assert Ok(prior_end) = parse_date("prior", prior.period_end)
  case date.compare(current_end, prior_end) {
    Gt ->
      case
        current.period_kind == prior.period_kind,
        current.inclusive_duration_days == prior.inclusive_duration_days
      {
        True, True -> None
        False, _ -> Some("incompatible_period_kinds")
        _, False -> Some("incompatible_inclusive_durations")
      }
    _ -> Some("current_period_does_not_follow_prior_period")
  }
}

fn decimal_inputs(
  operands: List(decode.OperandInput),
) -> Result(List(formula.Input), String) {
  list.try_map(operands, fn(value) {
    decimal.parse(value.exact_lexeme)
    |> result.map(fn(number) {
      formula.Input(value.name, formula.Available(number))
    })
    |> result.map_error(fn(_) { value.name })
  })
}

fn denominator_issue(
  denominator: Option(String),
  operands: List(decode.OperandInput),
) -> Option(String) {
  case denominator {
    None -> None
    Some(name) -> {
      let assert Ok(value) =
        list.find(operands, fn(value) { value.name == name })
      case decimal.parse(value.exact_lexeme) {
        Error(_) -> Some("invalid_denominator")
        Ok(number) ->
          case decimal.compare(number, decimal.zero()) {
            Gt -> None
            _ -> Some("non_positive_denominator")
          }
      }
    }
  }
}

fn calculated(
  input: decode.MetricInput,
  expression: Formula,
  output_unit: String,
  value: Decimal,
) -> Response {
  let calculation =
    json.object([
      #("state", json.string("calculated")),
      #("metricId", json.string(input.metric_id)),
      #("formula", formula_json(expression)),
      #("formulaVersion", json.string("session_19_metric_v1")),
      #("orderedOperands", json.array(input.operands, operand_json)),
      #("value", json.string(decimal.to_string(value))),
      #("unit", json.string(output_unit)),
      #("outputScale", json.int(input.output_scale)),
      #("rounding", json.string(input.rounding)),
      #("economicInterpretation", json.null()),
    ])
  let assert Ok(handle) = calculation |> json.to_string |> hash.text
  Response(
    "Calculated requested mechanical dossier metric "
      <> input.metric_id
      <> " as "
      <> decimal.to_string(value)
      <> " "
      <> output_unit
      <> "; no economic interpretation was made.",
    json.object([
      #("schema", json.string("pi-sparkles/investor-dossier-metric")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("dossier_metric")),
      #("requestId", json.string(input.request_id)),
      #("calculation", calculation),
      #("calculationHandle", json.string(identity.sha256_value(handle))),
      #("substituteMetricSelected", json.bool(False)),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ]),
  )
}

fn unperformed(
  input: decode.MetricInput,
  expression: Formula,
  output_unit: String,
  reason: String,
  missing: List(String),
  offending_operand: Option(String),
) -> Response {
  Response(
    "Did not calculate requested dossier metric "
      <> input.metric_id
      <> ": "
      <> reason
      <> ". No substitute metric was selected.",
    json.object([
      #("schema", json.string("pi-sparkles/investor-dossier-metric")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("dossier_metric")),
      #("requestId", json.string(input.request_id)),
      #(
        "calculation",
        json.object([
          #("state", json.string("unperformed")),
          #("metricId", json.string(input.metric_id)),
          #("reason", json.string(reason)),
          #("missingOperands", json.array(missing, json.string)),
          #("offendingOperand", json.nullable(offending_operand, json.string)),
          #("formula", formula_json(expression)),
          #("formulaVersion", json.string("session_19_metric_v1")),
          #("orderedProvidedOperands", json.array(input.operands, operand_json)),
          #("unit", json.string(output_unit)),
          #("economicInterpretation", json.null()),
        ]),
      ),
      #("substituteMetricSelected", json.bool(False)),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ]),
  )
}

fn operand_json(value: decode.OperandInput) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("exactLexeme", json.string(value.exact_lexeme)),
    #("entityId", json.string(value.entity_id)),
    #("periodStart", json.nullable(value.period_start, json.string)),
    #("periodEnd", json.string(value.period_end)),
    #("periodKind", json.string(value.period_kind)),
    #(
      "inclusiveDurationDays",
      json.nullable(value.inclusive_duration_days, json.int),
    ),
    #("currency", json.string(value.currency)),
    #("unit", json.string(value.unit)),
    #("reportedScale", json.int(value.reported_scale)),
    #("sourceReceipt", json.string(value.source_receipt)),
    #("basis", json.string(value.basis)),
  ])
}

fn formula_json(value: Formula) -> Json {
  case value {
    formula.Literal(number) ->
      json.object([
        #("kind", json.string("literal")),
        #("value", json.string(decimal.to_string(number))),
      ])
    formula.Reference(name) ->
      json.object([
        #("kind", json.string("reference")),
        #("name", json.string(name)),
      ])
    formula.Add(left, right) -> binary_formula_json("add", left, right)
    formula.Subtract(left, right) ->
      binary_formula_json("subtract", left, right)
    formula.Multiply(left, right) ->
      binary_formula_json("multiply", left, right)
    formula.Divide(numerator, denominator, scale, rounding) ->
      json.object([
        #("kind", json.string("divide")),
        #("numerator", formula_json(numerator)),
        #("denominator", formula_json(denominator)),
        #("scale", json.int(scale)),
        #("rounding", json.string(rounding_name(rounding))),
      ])
    formula.Negate(inner) -> unary_formula_json("negate", inner)
    formula.Absolute(inner) -> unary_formula_json("absolute", inner)
    formula.Power(inner, exponent) ->
      json.object([
        #("kind", json.string("power")),
        #("value", formula_json(inner)),
        #("exponent", json.int(exponent)),
      ])
    formula.Quantize(inner, scale, rounding) ->
      json.object([
        #("kind", json.string("quantize")),
        #("value", formula_json(inner)),
        #("scale", json.int(scale)),
        #("rounding", json.string(rounding_name(rounding))),
      ])
    formula.Sum(values) -> variadic_formula_json("sum", values)
    formula.Mean(values, scale, rounding) ->
      json.object([
        #("kind", json.string("mean")),
        #("values", json.array(values, formula_json)),
        #("scale", json.int(scale)),
        #("rounding", json.string(rounding_name(rounding))),
      ])
    formula.Minimum(values) -> variadic_formula_json("minimum", values)
    formula.Maximum(values) -> variadic_formula_json("maximum", values)
  }
}

fn binary_formula_json(kind: String, left: Formula, right: Formula) -> Json {
  json.object([
    #("kind", json.string(kind)),
    #("left", formula_json(left)),
    #("right", formula_json(right)),
  ])
}

fn unary_formula_json(kind: String, value: Formula) -> Json {
  json.object([
    #("kind", json.string(kind)),
    #("value", formula_json(value)),
  ])
}

fn variadic_formula_json(kind: String, values: List(Formula)) -> Json {
  json.object([
    #("kind", json.string(kind)),
    #("values", json.array(values, formula_json)),
  ])
}

fn rounding_mode(value: String) -> Result(RoundingMode, Error) {
  case value {
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    "half_up" -> Ok(decimal.HalfUp)
    "half_even" -> Ok(decimal.HalfEven)
    _ -> Error(InvalidField("rounding", "unknown rounding mode"))
  }
}

fn rounding_name(value: RoundingMode) -> String {
  case value {
    decimal.TowardZero -> "toward_zero"
    decimal.AwayFromZero -> "away_from_zero"
    decimal.HalfUp -> "half_up"
    decimal.HalfEven -> "half_even"
  }
}

fn parse_date(field: String, value: String) -> Result(Date, Error) {
  case string.split(value, "-") {
    [year_text, month_text, day_text] ->
      case
        string.length(year_text) == 4,
        string.length(month_text) == 2,
        string.length(day_text) == 2
      {
        True, True, True -> {
          use year <- result.try(
            int.parse(year_text)
            |> result.map_error(fn(_) {
              InvalidField(field, "must be YYYY-MM-DD")
            }),
          )
          use month <- result.try(
            int.parse(month_text)
            |> result.map_error(fn(_) {
              InvalidField(field, "must be YYYY-MM-DD")
            }),
          )
          use day <- result.try(
            int.parse(day_text)
            |> result.map_error(fn(_) {
              InvalidField(field, "must be YYYY-MM-DD")
            }),
          )
          time.date(year, month, day)
          |> result.map_error(fn(_) {
            InvalidField(field, "is not a Gregorian date")
          })
        }
        _, _, _ -> Error(InvalidField(field, "must be YYYY-MM-DD"))
      }
    _ -> Error(InvalidField(field, "must be YYYY-MM-DD"))
  }
}

fn nonblank(field: String, value: String) -> Result(Nil, Error) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "must be non-empty without surrounding whitespace",
      ))
  }
}
