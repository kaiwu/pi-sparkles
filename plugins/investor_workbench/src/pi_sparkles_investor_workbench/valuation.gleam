import finance_core/decimal.{type RoundingMode}
import finance_core/time.{type Date}
import finance_math/formula
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
  DuplicateScenario(label: String)
  DuplicateAssumption(scenario: String, name: String)
}

type ScenarioResult {
  ScenarioResult(label: String, details: Json, calculated: Bool)
}

pub fn error_message(value: Error) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid dossier valuation field " <> field <> ": " <> reason
    InvalidReceipt(field) ->
      "Invalid SHA-256 receipt in dossier valuation field " <> field
    DuplicateScenario(label) ->
      "Dossier valuation repeats scenario label " <> label
    DuplicateAssumption(scenario, name) ->
      "Dossier valuation scenario "
      <> scenario
      <> " repeats assumption "
      <> name
  }
}

pub fn project(input: decode.ValuationInput) -> Result(Response, Error) {
  use _ <- result.try(nonblank("requestId", input.request_id))
  use _ <- result.try(nonblank("valuationCurrency", input.valuation_currency))
  use _ <- result.try(validate_method(input.method))
  use rounding <- result.try(rounding_mode(input.rounding))
  use _ <- result.try(case input.output_scale >= 0 && input.output_scale <= 18 {
    True -> Ok(Nil)
    False -> Error(InvalidField("outputScale", "must be between 0 and 18"))
  })
  use _ <- result.try(validate_scenario_labels(input.scenarios, []))
  use rows <- result.try(
    list.try_map(input.scenarios, fn(value) {
      project_scenario(
        value,
        input.valuation_currency,
        input.output_scale,
        rounding,
      )
    }),
  )
  let calculated_count =
    rows
    |> list.filter(fn(value) { value.calculated })
    |> list.length
  Ok(Response(
    "Projected "
      <> int.to_string(list.length(rows))
      <> " caller-labelled "
      <> input.method
      <> " valuation scenario row(s); "
      <> int.to_string(calculated_count)
      <> " had coherent enterprise-value, net-debt, and diluted-share facts. No target-price or valuation verdict was produced.",
    json.object([
      #("schema", json.string("pi-sparkles/investor-dossier-valuation")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("dossier_valuation")),
      #("requestId", json.string(input.request_id)),
      #("method", json.string(input.method)),
      #("methodSelectionOwner", json.string("caller")),
      #("valuationCurrency", json.string(input.valuation_currency)),
      #("outputScale", json.int(input.output_scale)),
      #("rounding", json.string(input.rounding)),
      #("scenarioCount", json.int(list.length(rows))),
      #("calculatedScenarioCount", json.int(calculated_count)),
      #(
        "unperformedScenarioCount",
        json.int(list.length(rows) - calculated_count),
      ),
      #("scenarios", json.array(rows, fn(value) { value.details })),
      #(
        "methodResultMeaning",
        json.string(
          "caller_supplied_enterprise_value_from_the_selected_method_not_calculated_or_endorsed_by_this_tool",
        ),
      ),
      #(
        "scenarioLabelMeaning",
        json.string("caller_supplied_label_not_plugin_probability_or_rank"),
      ),
      #("authoritativeTargetPrice", json.null()),
      #("valuationVerdict", json.null()),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ]),
  ))
}

fn project_scenario(
  value: decode.ValuationScenarioInput,
  currency: String,
  scale: Int,
  rounding: RoundingMode,
) -> Result(ScenarioResult, Error) {
  use _ <- result.try(nonblank("scenarios[].label", value.label))
  use _ <- result.try(validate_named_operand(
    value.method_result,
    "enterprise_value",
  ))
  use _ <- result.try(validate_named_operand(value.net_debt, "net_debt"))
  use _ <- result.try(validate_named_operand(
    value.diluted_shares,
    "diluted_shares",
  ))
  use _ <- result.try(validate_assumptions(value.label, value.assumptions, []))
  let expression =
    formula.Divide(
      formula.Subtract(
        formula.Reference("enterprise_value"),
        formula.Reference("net_debt"),
      ),
      formula.Reference("diluted_shares"),
      scale,
      rounding,
    )
  case scenario_context_issue(value, currency) {
    Some(reason) ->
      Ok(ScenarioResult(
        value.label,
        unperformed_json(value, reason, scale, rounding),
        False,
      ))
    None ->
      case
        decimal.parse(value.method_result.exact_lexeme),
        decimal.parse(value.net_debt.exact_lexeme),
        decimal.parse(value.diluted_shares.exact_lexeme)
      {
        Error(_), _, _ ->
          Ok(ScenarioResult(
            value.label,
            unperformed_json(
              value,
              "invalid_numeric_operand:enterprise_value",
              scale,
              rounding,
            ),
            False,
          ))
        _, Error(_), _ ->
          Ok(ScenarioResult(
            value.label,
            unperformed_json(
              value,
              "invalid_numeric_operand:net_debt",
              scale,
              rounding,
            ),
            False,
          ))
        _, _, Error(_) ->
          Ok(ScenarioResult(
            value.label,
            unperformed_json(
              value,
              "invalid_numeric_operand:diluted_shares",
              scale,
              rounding,
            ),
            False,
          ))
        Ok(enterprise_value), Ok(net_debt), Ok(shares) ->
          case decimal.compare(shares, decimal.zero()) {
            Gt ->
              case
                formula.evaluate(expression, with: [
                  formula.Input(
                    "enterprise_value",
                    formula.Available(enterprise_value),
                  ),
                  formula.Input("net_debt", formula.Available(net_debt)),
                  formula.Input("diluted_shares", formula.Available(shares)),
                ])
              {
                Error(error) ->
                  Ok(ScenarioResult(
                    value.label,
                    unperformed_json(
                      value,
                      "calculation_unperformed:" <> string.inspect(error),
                      scale,
                      rounding,
                    ),
                    False,
                  ))
                Ok(per_share) -> {
                  let equity_value =
                    decimal.subtract(enterprise_value, net_debt)
                  let row =
                    json.object([
                      #("label", json.string(value.label)),
                      #("state", json.string("calculated")),
                      #(
                        "assumptions",
                        json.array(value.assumptions, assumption_json),
                      ),
                      #("formula", bridge_formula_json(scale, rounding)),
                      #(
                        "operands",
                        json.array(
                          [
                            value.method_result,
                            value.net_debt,
                            value.diluted_shares,
                          ],
                          operand_json,
                        ),
                      ),
                      #(
                        "enterpriseValue",
                        json.string(decimal.to_string(enterprise_value)),
                      ),
                      #(
                        "equityValue",
                        json.string(decimal.to_string(equity_value)),
                      ),
                      #(
                        "perShareValue",
                        json.string(decimal.to_string(per_share)),
                      ),
                      #("currency", json.string(currency)),
                      #("interpretation", json.null()),
                    ])
                  let assert Ok(handle) = row |> json.to_string |> hash.text
                  Ok(ScenarioResult(
                    value.label,
                    json.object([
                      #("result", row),
                      #(
                        "scenarioHandle",
                        json.string(identity.sha256_value(handle)),
                      ),
                    ]),
                    True,
                  ))
                }
              }
            _ ->
              Ok(ScenarioResult(
                value.label,
                unperformed_json(
                  value,
                  "non_positive_denominator:diluted_shares",
                  scale,
                  rounding,
                ),
                False,
              ))
          }
      }
  }
}

fn scenario_context_issue(
  value: decode.ValuationScenarioInput,
  currency: String,
) -> Option(String) {
  let method_result = value.method_result
  let debt = value.net_debt
  let shares = value.diluted_shares
  case
    method_result.entity_id == debt.entity_id
    && debt.entity_id == shares.entity_id,
    method_result.period_end == debt.period_end
    && debt.period_end == shares.period_end,
    method_result.currency == currency
    && debt.currency == currency
    && shares.currency == currency
  {
    False, _, _ -> Some("incompatible_entities")
    _, False, _ -> Some("incompatible_periods")
    _, _, False -> Some("incompatible_currencies")
    True, True, True ->
      case
        method_result.unit,
        debt.unit,
        shares.unit,
        method_result.reported_scale == debt.reported_scale
        && debt.reported_scale == shares.reported_scale
      {
        "currency", "currency", "shares", True -> None
        "currency", "currency", "shares", False ->
          Some("incompatible_reported_scales")
        _, _, _, _ -> Some("incompatible_operand_units")
      }
  }
}

fn validate_named_operand(
  value: decode.OperandInput,
  expected_name: String,
) -> Result(Nil, Error) {
  use _ <- result.try(case value.name == expected_name {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "scenarios[]." <> expected_name <> ".name",
        "must be " <> expected_name,
      ))
  })
  use _ <- result.try(nonblank("scenarios[].operands.entityId", value.entity_id))
  use _ <- result.try(nonblank("scenarios[].operands.currency", value.currency))
  use _ <- result.try(nonblank("scenarios[].operands.unit", value.unit))
  use _ <- result.try(parse_date(
    "scenarios[].operands.periodEnd",
    value.period_end,
  ))
  use _ <- result.try(case value.period_start {
    None -> Ok(Nil)
    Some(text) ->
      parse_date("scenarios[].operands.periodStart", text)
      |> result.map(fn(_) { Nil })
  })
  use _ <- result.try(
    case value.reported_scale >= -18 && value.reported_scale <= 18 {
      True -> Ok(Nil)
      False ->
        Error(InvalidField(
          "scenarios[].operands.reportedScale",
          "must be between -18 and 18",
        ))
    },
  )
  use _ <- result.try(case value.basis {
    "statement_fact"
    | "consensus_estimate"
    | "caller_declared"
    | "historical_average" -> Ok(Nil)
    _ -> Error(InvalidField("scenarios[].operands.basis", "unknown basis"))
  })
  identity.sha256(value.source_receipt)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(_) {
    InvalidReceipt("scenarios[].operands.sourceReceipt")
  })
}

fn validate_assumptions(
  scenario: String,
  values: List(decode.AssumptionInput),
  seen: List(String),
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(nonblank("scenarios[].assumptions[].name", value.name))
      use _ <- result.try(nonblank(
        "scenarios[].assumptions[].exactValue",
        value.exact_value,
      ))
      use _ <- result.try(case list.contains(seen, value.name) {
        True -> Error(DuplicateAssumption(scenario, value.name))
        False -> Ok(Nil)
      })
      use _ <- result.try(case value.basis {
        "statement_fact"
        | "consensus_estimate"
        | "caller_declared"
        | "historical_average" -> Ok(Nil)
        _ ->
          Error(InvalidField("scenarios[].assumptions[].basis", "unknown basis"))
      })
      use _ <- result.try(case value.source_reference {
        None ->
          Error(InvalidField(
            "scenarios[].assumptions[].sourceReference",
            "every assumption must retain its statement, estimate, history, or caller declaration reference",
          ))
        Some(reference) ->
          nonblank("scenarios[].assumptions[].sourceReference", reference)
      })
      validate_assumptions(scenario, rest, [value.name, ..seen])
    }
  }
}

fn validate_scenario_labels(
  values: List(decode.ValuationScenarioInput),
  seen: List(String),
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case list.contains(seen, value.label) {
        True -> Error(DuplicateScenario(value.label))
        False -> validate_scenario_labels(rest, [value.label, ..seen])
      }
  }
}

fn unperformed_json(
  value: decode.ValuationScenarioInput,
  reason: String,
  scale: Int,
  rounding: RoundingMode,
) -> Json {
  json.object([
    #(
      "result",
      json.object([
        #("label", json.string(value.label)),
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
        #("assumptions", json.array(value.assumptions, assumption_json)),
        #("formula", bridge_formula_json(scale, rounding)),
        #(
          "operands",
          json.array(
            [value.method_result, value.net_debt, value.diluted_shares],
            operand_json,
          ),
        ),
        #("interpretation", json.null()),
      ]),
    ),
    #("scenarioHandle", json.null()),
  ])
}

fn bridge_formula_json(scale: Int, rounding: RoundingMode) -> Json {
  json.object([
    #("kind", json.string("divide")),
    #(
      "numerator",
      json.object([
        #("kind", json.string("subtract")),
        #(
          "left",
          json.object([
            #("kind", json.string("reference")),
            #("name", json.string("enterprise_value")),
          ]),
        ),
        #(
          "right",
          json.object([
            #("kind", json.string("reference")),
            #("name", json.string("net_debt")),
          ]),
        ),
      ]),
    ),
    #(
      "denominator",
      json.object([
        #("kind", json.string("reference")),
        #("name", json.string("diluted_shares")),
      ]),
    ),
    #("scale", json.int(scale)),
    #("rounding", json.string(rounding_name(rounding))),
  ])
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

fn assumption_json(value: decode.AssumptionInput) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("exactValue", json.string(value.exact_value)),
    #("basis", json.string(value.basis)),
    #("sourceReference", json.nullable(value.source_reference, json.string)),
  ])
}

fn validate_method(value: String) -> Result(Nil, Error) {
  case value {
    "comparable_multiples"
    | "historical_multiples"
    | "dcf"
    | "dividend_discount"
    | "asset_nav"
    | "sector_specific" -> Ok(Nil)
    _ -> Error(InvalidField("method", "unknown Session 19 valuation method"))
  }
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
