import gleeunit
import gleeunit/should
import pi_sparkles_hello/greeting

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn greeting_test() {
  greeting.greeting("Gleam")
  |> should.equal("Hello, Gleam!")
}
