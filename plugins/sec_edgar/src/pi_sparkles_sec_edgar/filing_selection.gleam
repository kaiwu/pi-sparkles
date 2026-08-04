import finance_sec/response.{type Filing, type Submissions}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type Plan {
  Plan(form: Option(String), limit: Int)
}

pub type PlanError {
  InvalidForm
  InvalidLimit
}

pub fn plan(form: Option(String), limit: Int) -> Result(Plan, PlanError) {
  case normalize_form(form), limit < 1 || limit > 50 {
    Error(_), _ -> Error(InvalidForm)
    _, True -> Error(InvalidLimit)
    Ok(form), False -> Ok(Plan(form, limit))
  }
}

pub fn select(value: Submissions, plan: Plan) -> List(Filing) {
  let Plan(form, limit) = plan
  value.recent
  |> list.filter(fn(filing) {
    case form {
      None -> True
      Some(expected) -> string.uppercase(filing.form) == expected
    }
  })
  |> list.take(limit)
}

fn normalize_form(value: Option(String)) -> Result(Option(String), Nil) {
  case value {
    None -> Ok(None)
    Some(value) -> {
      let normalized = value |> string.trim |> string.uppercase
      case normalized == "" || string.length(normalized) > 20 {
        True -> Error(Nil)
        False -> Ok(Some(normalized))
      }
    }
  }
}
