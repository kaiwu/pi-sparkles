import finance_core/observation
import finance_core/time
import gleam/list
import gleam/string

pub type Severity {
  Reject
  Warn
}

pub type Issue {
  Issue(code: String, severity: Severity, message: String)
}

pub type EvidenceFacts {
  EvidenceFacts(
    source: String,
    currencies: List(String),
    periods: List(String),
    adjustments: List(String),
    age_milliseconds: Int,
    maximum_age_milliseconds: Int,
    entitlement: String,
  )
}

pub type Decision {
  Decision(accepted: Bool, issues: List(Issue))
}

pub type FreshnessError {
  NegativeAge
  InvalidMaximumAge
  AgeOutOfRange
  MaximumAgeOutOfRange
}

pub fn validate(facts: EvidenceFacts) -> Decision {
  let issues =
    []
    |> list.append(source_issues(facts.source))
    |> list.append(consistency_issues(
      "mixed_currency",
      "currencies",
      facts.currencies,
    ))
    |> list.append(consistency_issues("mixed_period", "periods", facts.periods))
    |> list.append(consistency_issues(
      "mixed_adjustment",
      "adjustment bases",
      facts.adjustments,
    ))
    |> list.append(freshness_issues(
      facts.age_milliseconds,
      facts.maximum_age_milliseconds,
    ))
    |> list.append(entitlement_issues(facts.entitlement))

  Decision(
    accepted: !list.any(issues, fn(issue) { issue.severity == Reject }),
    issues: issues,
  )
}

pub fn freshness(
  age_milliseconds: Int,
  maximum_age_milliseconds: Int,
) -> Result(observation.Freshness, FreshnessError) {
  case age_milliseconds < 0, maximum_age_milliseconds < 0 {
    True, _ -> Error(NegativeAge)
    _, True -> Error(InvalidMaximumAge)
    False, False ->
      case
        time.duration(age_milliseconds),
        time.duration(maximum_age_milliseconds)
      {
        Error(_), _ -> Error(AgeOutOfRange)
        _, Error(_) -> Error(MaximumAgeOutOfRange)
        Ok(age), Ok(maximum_age) ->
          case age_milliseconds <= maximum_age_milliseconds {
            True -> Ok(observation.Fresh(maximum_age))
            False -> Ok(observation.Stale(age, maximum_age))
          }
      }
  }
}

pub fn freshness_name(value: observation.Freshness) -> String {
  case value {
    observation.Fresh(_) -> "fresh"
    observation.Stale(_, _) -> "stale"
    observation.UnknownFreshness -> "unknown"
  }
}

pub fn severity_name(value: Severity) -> String {
  case value {
    Reject -> "reject"
    Warn -> "warn"
  }
}

pub fn render(decision: Decision) -> String {
  let heading = case decision.accepted {
    True -> "accepted"
    False -> "rejected"
  }
  case decision.issues {
    [] -> "Evidence policy: " <> heading <> " (no issues)"
    issues ->
      "Evidence policy: "
      <> heading
      <> "\n"
      <> {
        issues
        |> list.map(fn(issue) {
          "- ["
          <> severity_name(issue.severity)
          <> "] "
          <> issue.code
          <> ": "
          <> issue.message
        })
        |> string.join("\n")
      }
  }
}

pub fn policy_text() -> String {
  "Finance evidence policy\n"
  <> "- source is required\n"
  <> "- mixed currencies, periods, or adjustment bases are rejected\n"
  <> "- age must be non-negative and not exceed maximum age\n"
  <> "- entitlement must be real_time, delayed, end_of_day, or unknown\n"
  <> "- unknown entitlement is retained as a warning, never silently upgraded"
}

fn source_issues(source: String) -> List(Issue) {
  case string.trim(source) {
    "" -> [Issue("missing_source", Reject, "a source reference is required")]
    _ -> []
  }
}

fn consistency_issues(
  code: String,
  label: String,
  values: List(String),
) -> List(Issue) {
  let distinct = distinct_normalized(values)
  case list.length(distinct) > 1 {
    True -> [
      Issue(
        code,
        Reject,
        label <> " are incompatible: " <> string.join(distinct, ", "),
      ),
    ]
    False -> []
  }
}

fn freshness_issues(age: Int, maximum: Int) -> List(Issue) {
  case freshness(age, maximum) {
    Error(NegativeAge) -> [
      Issue("invalid_age", Reject, "age cannot be negative"),
    ]
    Error(InvalidMaximumAge) -> [
      Issue("invalid_maximum_age", Reject, "maximum age cannot be negative"),
    ]
    Error(AgeOutOfRange) -> [
      Issue(
        "invalid_age",
        Reject,
        "age is outside the supported duration range",
      ),
    ]
    Error(MaximumAgeOutOfRange) -> [
      Issue(
        "invalid_maximum_age",
        Reject,
        "maximum age is outside the supported duration range",
      ),
    ]
    Ok(observation.Stale(_, _)) -> [
      Issue(
        "stale_evidence",
        Reject,
        "evidence age exceeds the declared maximum",
      ),
    ]
    Ok(_) -> []
  }
}

fn entitlement_issues(value: String) -> List(Issue) {
  case string.lowercase(string.trim(value)) {
    "real_time" | "delayed" | "end_of_day" -> []
    "unknown" -> [
      Issue(
        "unknown_entitlement",
        Warn,
        "redistribution and timeliness rights are unknown",
      ),
    ]
    _ -> [
      Issue(
        "invalid_entitlement",
        Reject,
        "entitlement must be real_time, delayed, end_of_day, or unknown",
      ),
    ]
  }
}

fn distinct_normalized(values: List(String)) -> List(String) {
  values
  |> list.fold([], fn(found, value) {
    let normalized = value |> string.trim |> string.lowercase
    case normalized == "" || list.contains(found, normalized) {
      True -> found
      False -> list.append(found, [normalized])
    }
  })
}
