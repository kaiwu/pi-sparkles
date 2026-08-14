import finance_broker_review/decode.{
  type ExplicitCapabilityInput, type FactInput, ExplicitCapabilityInput,
  FactInput, ReviewInput,
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

fn input(facts: List(FactInput)) -> ExplicitCapabilityInput {
  ExplicitCapabilityInput(
    "futu",
    ReviewInput(
      "handoff",
      "non_executable_handoff",
      "external_live",
      hash_a,
      "cn",
      "000001",
      "XSHE",
      hash_b,
      [
        FactInput(
          "broker_provider",
          "known",
          Some("futu"),
          Some("provider_identifier"),
          hash_a,
        ),
        FactInput(
          "read_only_authority",
          "known",
          Some("read_only"),
          Some("authority_scope"),
          hash_a,
        ),
        known("provider_capability_receipt"),
        ..facts
      ],
      [],
      [],
    ),
  )
}

fn known(name: String) -> FactInput {
  FactInput(name, "known", Some("caller_value"), Some("caller_unit"), hash_a)
}
