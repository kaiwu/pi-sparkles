import finance_broker_review/decode.{
  type FactInput, type ReviewInput, FactInput, ReviewInput,
}
import gleam/option.{Some}
import gleeunit
import gleeunit/should
import pi_sparkles_broker_live/domain

const hash_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const hash_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

pub fn main() {
  gleeunit.main()
}

pub fn non_executable_handoff_requires_unambiguous_instruction_context_test() {
  domain.run(input([known("instruction_side")])) |> should.be_error
  domain.run(
    input([
      known("instruction_side"),
      known("instruction_kind"),
      known("quantity"),
      known("quantity_unit"),
      known("time_in_force"),
      known("plan_fingerprint"),
      known("rule_reference"),
    ]),
  )
  |> should.be_ok
}

pub fn duplicate_instruction_fields_fail_closed_test() {
  domain.run(
    input([
      known("instruction_side"),
      known("instruction_side"),
      known("instruction_kind"),
      known("quantity"),
      known("quantity_unit"),
      known("time_in_force"),
      known("plan_fingerprint"),
      known("rule_reference"),
    ]),
  )
  |> should.be_error
}

fn input(facts: List(FactInput)) -> ReviewInput {
  ReviewInput(
    "handoff",
    "non_executable_handoff",
    "external_live",
    hash_a,
    "cn",
    "000001",
    "XSHE",
    hash_b,
    facts,
    [],
    [],
  )
}

fn known(name: String) -> FactInput {
  FactInput(name, "known", Some("caller_value"), Some("caller_unit"), hash_a)
}
