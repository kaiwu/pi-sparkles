import gleam/list

pub type Case(value) {
  Accept(name: String, payload: String, expected: value)
  Reject(name: String, payload: String)
}

pub type Failure(value) {
  RejectedValid(name: String)
  AcceptedInvalid(name: String, actual: value)
  ValueMismatch(name: String, expected: value, actual: value)
}

pub type Report(value) {
  Report(total: Int, failures: List(Failure(value)))
}

pub type Decoder(value, error) =
  fn(String) -> Result(value, error)

pub fn check(
  cases: List(Case(value)),
  using decoder: Decoder(value, error),
) -> Report(value) {
  let failures =
    cases
    |> list.filter_map(fn(case_value) {
      case case_value, decoder(payload(case_value)) {
        Accept(_, _, expected), Ok(actual) if expected == actual -> Error(Nil)
        Accept(name, _, expected), Ok(actual) ->
          Ok(ValueMismatch(name, expected, actual))
        Accept(name, _, _), Error(_) -> Ok(RejectedValid(name))
        Reject(_, _), Error(_) -> Error(Nil)
        Reject(name, _), Ok(actual) -> Ok(AcceptedInvalid(name, actual))
      }
    })
  Report(list.length(cases), failures)
}

pub fn passed(report: Report(value)) -> Bool {
  let Report(_, failures) = report
  list.is_empty(failures)
}

pub fn required_boundary_rejections(
  missing_field: String,
  null_field: String,
  wrong_type: String,
  unsafe_number: String,
  unknown_enum: String,
) -> List(Case(value)) {
  [
    Reject("missing-field", missing_field),
    Reject("null-field", null_field),
    Reject("wrong-type", wrong_type),
    Reject("unsafe-exact-number", unsafe_number),
    Reject("unknown-enum", unknown_enum),
  ]
}

fn payload(case_value: Case(value)) -> String {
  case case_value {
    Accept(_, payload, _) | Reject(_, payload) -> payload
  }
}
