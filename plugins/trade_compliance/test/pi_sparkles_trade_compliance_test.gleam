import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_trade_compliance/decode.{
  EvaluationInput, FactInput, RuleInput,
}
import pi_sparkles_trade_compliance/domain

const hash_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const hash_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

pub fn main() {
  gleeunit.main()
}

pub fn evaluates_each_rule_without_aggregate_verdict_test() {
  let assert Ok(value) =
    domain.evaluate(
      EvaluationInput(
        "evaluate",
        "cn",
        hash_a,
        20,
        hash_b,
        [FactInput("t_plus_one_available", "known", Some(False), hash_a)],
        [
          RuleInput(
            "cn-settlement",
            "2026-01",
            10,
            None,
            "t_plus_one_available",
            True,
            "caller_high",
            hash_b,
          ),
        ],
        [],
      ),
    )
  let details = domain.details(value) |> json.to_string
  details |> string.contains("\"state\":\"False\"") |> should.be_true
  details |> string.contains("\"aggregateVerdict\":null") |> should.be_true
  details |> string.contains("\"executable\":false") |> should.be_true
  details |> string.contains("\"maturity\":\"track_partial\"") |> should.be_true
}

pub fn missing_fact_remains_unknown_test() {
  let assert Ok(value) =
    domain.evaluate(
      EvaluationInput(
        "evaluate",
        "cn",
        hash_a,
        20,
        hash_b,
        [],
        [
          RuleInput(
            "known-account",
            "v1",
            10,
            None,
            "account_enabled",
            True,
            "caller_high",
            hash_b,
          ),
        ],
        [],
      ),
    )
  domain.details(value)
  |> json.to_string
  |> string.contains("\"state\":\"Unknown\"")
  |> should.be_true
}

pub fn market_depth_rule_fails_closed_test() {
  domain.evaluate(
    EvaluationInput(
      "evaluate",
      "cn",
      hash_a,
      20,
      hash_b,
      [],
      [
        RuleInput(
          "depth-rule",
          "v1",
          10,
          None,
          "best_offer_price",
          True,
          "caller_high",
          hash_b,
        ),
      ],
      [],
    ),
  )
  |> should.be_error
}
