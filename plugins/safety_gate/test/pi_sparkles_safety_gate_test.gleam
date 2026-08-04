import gleeunit
import gleeunit/should
import pi_sparkles_safety_gate/check

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn dangerous_command_test() {
  check.classify("rm -rf build")
  |> should.equal(check.RequiresConfirmation([check.RecursiveDelete]))
}

pub fn ordinary_command_test() {
  check.classify("rg TODO src")
  |> should.equal(check.Ordinary)
}

pub fn risks_compose_in_rule_order_test() {
  check.classify("sudo chmod 777 output")
  |> should.equal(
    check.RequiresConfirmation([
      check.PrivilegeEscalation,
      check.WorldWritablePermissions,
    ]),
  )
}

pub fn risk_explanation_is_a_pure_projection_test() {
  [check.RecursiveDelete, check.OwnershipChange]
  |> check.explain
  |> should.equal("recursive deletion, ownership change")
}
