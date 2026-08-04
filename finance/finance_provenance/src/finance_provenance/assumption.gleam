import finance_core/decimal.{type Decimal}
import finance_core/money.{type Money}
import gleam/string

pub opaque type AssumptionId {
  AssumptionId(value: String)
}

pub type Origin {
  User
  Provider
  Method
  Policy
}

pub type Value {
  TextValue(String)
  DecimalValue(Decimal)
  MoneyValue(Money)
  BooleanValue(Bool)
}

pub type Assumption {
  Assumption(
    id: AssumptionId,
    name: String,
    value: Value,
    origin: Origin,
    explanation: String,
  )
}

pub type AssumptionError {
  InvalidId
  InvalidName
  InvalidExplanation
}

pub fn id(value: String) -> Result(AssumptionId, AssumptionError) {
  case valid(value) {
    True -> Ok(AssumptionId(value))
    False -> Error(InvalidId)
  }
}

pub fn id_value(id: AssumptionId) -> String {
  let AssumptionId(value) = id
  value
}

pub fn new(
  id id: AssumptionId,
  name name: String,
  value value: Value,
  origin origin: Origin,
  explanation explanation: String,
) -> Result(Assumption, AssumptionError) {
  case valid(name), valid(explanation) {
    False, _ -> Error(InvalidName)
    _, False -> Error(InvalidExplanation)
    True, True -> Ok(Assumption(id, name, value, origin, explanation))
  }
}

fn valid(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
