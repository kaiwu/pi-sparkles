import finance_core/decimal
import finance_journal/information.{type Information}
import finance_journal/receipt.{type Envelope}
import finance_provenance/identity.{type Sha256}
import gleam/json
import gleam/list
import gleam/order
import gleam/result
import gleam/string

pub type Mode {
  ExactEquality
  DecimalDelta(scale: Int, rounding: decimal.RoundingMode)
}

pub type FieldRequest {
  FieldRequest(
    field: String,
    planned: Information(String),
    observed: Information(String),
    mode: Mode,
    unit: String,
  )
}

pub type ResultItem {
  Compared(
    field: String,
    planned: String,
    observed: String,
    equal: Bool,
    delta: Information(String),
    unit: String,
  )
  Unperformed(
    field: String,
    planned: Information(String),
    observed: Information(String),
    reason: String,
    unit: String,
  )
}

pub opaque type Comparison {
  Comparison(
    instruction_receipt: Sha256,
    plan_receipt: Sha256,
    observation_receipts: List(Sha256),
    missing_policy: String,
    conflict_policy: String,
    requests: List(FieldRequest),
    results: List(ResultItem),
  )
}

pub type ComparisonError {
  EmptyRequests
  DuplicateField(field: String)
  InvalidText(field: String)
  NegativeScale
}

pub fn compare(
  instruction_receipt instruction: Sha256,
  plan_receipt plan: Sha256,
  observation_receipts observations: List(Sha256),
  missing_policy missing: String,
  conflict_policy conflict: String,
  requests request_values: List(FieldRequest),
) -> Result(Comparison, ComparisonError) {
  case request_values {
    [] -> Error(EmptyRequests)
    _ -> {
      use _ <- result.try(validate_text(missing, "missing_policy"))
      use _ <- result.try(validate_text(conflict, "conflict_policy"))
      use _ <- result.try(validate_requests(request_values, []))
      let results = list.map(request_values, compare_field)
      Ok(Comparison(
        instruction,
        plan,
        observations,
        missing,
        conflict,
        request_values,
        results,
      ))
    }
  }
}

fn validate_requests(
  values: List(FieldRequest),
  seen: List(String),
) -> Result(Nil, ComparisonError) {
  case values {
    [] -> Ok(Nil)
    [FieldRequest(field, _, _, mode, unit), ..rest] -> {
      use _ <- result.try(validate_text(field, "field"))
      use _ <- result.try(validate_text(unit, "unit"))
      case list.contains(seen, field), mode {
        True, _ -> Error(DuplicateField(field))
        _, DecimalDelta(scale, _) if scale < 0 -> Error(NegativeScale)
        False, _ -> validate_requests(rest, [field, ..seen])
      }
    }
  }
}

fn compare_field(value: FieldRequest) -> ResultItem {
  let FieldRequest(field, planned, observed, mode, unit) = value
  case planned, observed {
    information.Known(planned), information.Known(observed) ->
      compare_known(field, planned, observed, mode, unit)
    _, _ ->
      Unperformed(
        field,
        planned,
        observed,
        "one_or_both_values_not_known",
        unit,
      )
  }
}

fn compare_known(
  field: String,
  planned: String,
  observed: String,
  mode: Mode,
  unit: String,
) -> ResultItem {
  case mode {
    ExactEquality ->
      Compared(
        field,
        planned,
        observed,
        planned == observed,
        information.NotApplicable("exact_equality_has_no_numeric_delta"),
        unit,
      )
    DecimalDelta(scale, rounding) ->
      case decimal.parse(planned), decimal.parse(observed) {
        Ok(planned_decimal), Ok(observed_decimal) -> {
          let delta = decimal.subtract(observed_decimal, planned_decimal)
          let assert Ok(rounded) = decimal.quantize(delta, scale, rounding)
          Compared(
            field,
            planned,
            observed,
            decimal.compare(planned_decimal, observed_decimal) == order.Eq,
            information.Known(format_scale(rounded, scale)),
            unit,
          )
        }
        _, _ ->
          Unperformed(
            field,
            information.Known(planned),
            information.Known(observed),
            "decimal_decode_failure",
            unit,
          )
      }
  }
}

pub fn receipt(value: Comparison) -> Envelope {
  json.object([
    #("schema", json.string("pi-sparkles/journal-comparison-result")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #(
      "instruction_receipt",
      value.instruction_receipt |> identity.sha256_value |> json.string,
    ),
    #(
      "plan_receipt",
      value.plan_receipt |> identity.sha256_value |> json.string,
    ),
    #(
      "observation_receipts",
      value.observation_receipts
        |> list.map(identity.sha256_value)
        |> json.array(json.string),
    ),
    #("missing_policy", json.string(value.missing_policy)),
    #("conflict_policy", json.string(value.conflict_policy)),
    #("requested_fields", json.array(value.requests, request_json)),
    #("comparisons", json.array(value.results, result_json)),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
    #(
      "available_operations",
      json.array(
        [
          "inspect_plan_receipt",
          "inspect_observation_receipt",
          "request_different_comparison",
          "attach_review_conclusion",
        ],
        json.string,
      ),
    ),
  ])
  |> receipt.envelope
}

fn request_json(value: FieldRequest) -> json.Json {
  let FieldRequest(field, planned, observed, mode, unit) = value
  json.object([
    #("field", json.string(field)),
    #("planned", information_json(planned)),
    #("observed", information_json(observed)),
    #("mode", mode_json(mode)),
    #("unit", json.string(unit)),
  ])
}

fn result_json(value: ResultItem) -> json.Json {
  case value {
    Compared(field, planned, observed, equal, delta, unit) ->
      json.object([
        #("state", json.string("compared")),
        #("field", json.string(field)),
        #("planned", json.string(planned)),
        #("observed", json.string(observed)),
        #("equal", json.bool(equal)),
        #("delta", information_json(delta)),
        #("unit", json.string(unit)),
      ])
    Unperformed(field, planned, observed, reason, unit) ->
      json.object([
        #("state", json.string("unperformed")),
        #("field", json.string(field)),
        #("planned", information_json(planned)),
        #("observed", information_json(observed)),
        #("reason", json.string(reason)),
        #("unit", json.string(unit)),
      ])
  }
}

fn mode_json(value: Mode) -> json.Json {
  case value {
    ExactEquality -> json.object([#("kind", json.string("exact_equality"))])
    DecimalDelta(scale, rounding) ->
      json.object([
        #("kind", json.string("decimal_delta")),
        #("scale", json.int(scale)),
        #("rounding", rounding |> rounding_name |> json.string),
      ])
  }
}

fn information_json(value: Information(String)) -> json.Json {
  case value {
    information.Known(value) ->
      json.object([
        #("state", json.string("known")),
        #("value", json.string(value)),
      ])
    information.Conflicting(alternatives, reason) ->
      json.object([
        #("state", json.string("conflicting")),
        #("alternatives", json.array(alternatives, json.string)),
        #("reason", json.string(reason)),
      ])
    information.DecodeFailure(raw, reason) ->
      json.object([
        #("state", json.string("decode_failure")),
        #("raw", json.string(raw)),
        #("reason", json.string(reason)),
      ])
    other ->
      json.object([
        #("state", other |> information.state_name |> json.string),
        #("detail", other |> information_detail |> json.string),
      ])
  }
}

fn information_detail(value: Information(String)) -> String {
  case value {
    information.Unknown(reason)
    | information.NotObtained(reason)
    | information.NotApplicable(reason)
    | information.Redacted(reason)
    | information.Superseded(reason) -> reason
    information.NotAsked -> "not_asked"
    information.Declined -> "declined"
    _ -> ""
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

fn validate_text(value: String, field: String) -> Result(Nil, ComparisonError) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

pub fn results(value: Comparison) -> List(ResultItem) {
  value.results
}
