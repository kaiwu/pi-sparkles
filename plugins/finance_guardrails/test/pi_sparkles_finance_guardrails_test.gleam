import finance_core/observation
import finance_core/time
import gleam/list
import gleeunit
import gleeunit/should
import pi_sparkles_finance_guardrails/policy

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn compatible_fresh_evidence_is_accepted_test() {
  facts(["USD", "usd"], ["FY2025"], ["split_adjusted"], 100, 200, "delayed")
  |> policy.validate
  |> fn(value) { value.accepted }
  |> should.be_true
}

pub fn incompatible_and_stale_evidence_accumulates_reasons_test() {
  let decision =
    facts(
      ["USD", "EUR"],
      ["FY2024", "FY2025"],
      ["raw", "split_adjusted"],
      300,
      200,
      "unknown",
    )
    |> policy.validate
  decision.accepted |> should.be_false
  decision.issues |> list.length |> should.equal(5)
}

pub fn freshness_boundary_is_inclusive_test() {
  let assert Ok(maximum_age) = time.duration(200)
  policy.freshness(200, 200)
  |> should.equal(Ok(observation.Fresh(maximum_age)))
}

pub fn negative_age_is_typed_failure_test() {
  policy.freshness(-1, 200)
  |> should.equal(Error(policy.NegativeAge))
}

pub fn oversized_age_is_typed_failure_test() {
  policy.freshness(8_640_000_000_000_001, 8_640_000_000_000_001)
  |> should.equal(Error(policy.AgeOutOfRange))
}

fn facts(
  currencies: List(String),
  periods: List(String),
  adjustments: List(String),
  age: Int,
  maximum: Int,
  entitlement: String,
) -> policy.EvidenceFacts {
  policy.EvidenceFacts(
    source: "provider:fixture",
    currencies:,
    periods:,
    adjustments:,
    age_milliseconds: age,
    maximum_age_milliseconds: maximum,
    entitlement:,
  )
}
