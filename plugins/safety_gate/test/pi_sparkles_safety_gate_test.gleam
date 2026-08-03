import gleeunit
import gleeunit/should
import pi_sparkles_safety_gate/check

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn dangerous_command_test() {
  check.is_dangerous("rm -rf build")
  |> should.be_true
}

pub fn ordinary_command_test() {
  check.is_dangerous("rg TODO src")
  |> should.be_false
}
