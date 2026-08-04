import finance_sec/xbrl.{type Concept, type Fact}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

pub opaque type Plan {
  Plan(unit: Option(String), form: Option(String), limit: Int)
}

pub type PlanError {
  InvalidUnit
  InvalidForm
  InvalidLimit
}

pub type SelectedFact {
  SelectedFact(unit: String, fact: Fact)
}

pub type Selection {
  Selection(facts: List(SelectedFact), total: Int, truncated: Bool)
}

pub fn plan(
  unit: Option(String),
  form: Option(String),
  limit: Int,
) -> Result(Plan, PlanError) {
  case
    normalize(unit, 100, identity),
    normalize(form, 20, string.uppercase),
    limit < 1 || limit > 100
  {
    Error(_), _, _ -> Error(InvalidUnit)
    _, Error(_), _ -> Error(InvalidForm)
    _, _, True -> Error(InvalidLimit)
    Ok(unit), Ok(form), False -> Ok(Plan(unit, form, limit))
  }
}

pub fn select(concept: Concept, plan: Plan) -> Selection {
  let Plan(unit_filter, form_filter, limit) = plan
  let matches =
    concept.units
    |> list.flat_map(fn(unit_facts) {
      case unit_filter {
        Some(expected) if unit_facts.unit != expected -> []
        _ ->
          unit_facts.facts
          |> list.filter(fn(fact) {
            case form_filter {
              None -> True
              Some(expected) -> string.uppercase(fact.form) == expected
            }
          })
          |> list.map(fn(fact) { SelectedFact(unit_facts.unit, fact) })
      }
    })
    |> list.sort(by: latest_filed_first)
  let total = list.length(matches)
  Selection(list.take(matches, limit), total, total > limit)
}

fn latest_filed_first(left: SelectedFact, right: SelectedFact) -> order.Order {
  case string.compare(right.fact.filed, left.fact.filed) {
    order.Eq ->
      case string.compare(right.fact.accession, left.fact.accession) {
        order.Eq -> string.compare(left.unit, right.unit)
        other -> other
      }
    other -> other
  }
}

fn normalize(
  value: Option(String),
  maximum: Int,
  transform: fn(String) -> String,
) -> Result(Option(String), Nil) {
  case value {
    None -> Ok(None)
    Some(value) -> {
      let normalized = value |> string.trim |> transform
      case normalized == "" || string.length(normalized) > maximum {
        True -> Error(Nil)
        False -> Ok(Some(normalized))
      }
    }
  }
}

fn identity(value: String) -> String {
  value
}
