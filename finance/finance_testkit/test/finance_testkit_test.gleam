import finance_core/time
import finance_testkit
import finance_testkit/clock
import finance_testkit/script
import finance_testkit/seed
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_implementing_test() {
  finance_testkit.status()
  |> should.equal(finance_testkit.Implementing)
}

pub fn manual_clock_advances_without_wall_time_test() {
  let assert Ok(start) = time.instant(1000)
  let assert Ok(delta) = time.duration(250)
  let assert Ok(advanced) = clock.new(start) |> clock.advance(delta)

  advanced
  |> clock.now
  |> time.unix_milliseconds
  |> should.equal(1250)
  start
  |> time.unix_milliseconds
  |> should.equal(1000)
}

pub fn scripted_results_are_immutable_and_ordered_test() {
  let original = script.new([Ok("first"), Error("rate-limited"), Ok("last")])
  let assert Ok(#(after_first, Ok("first"))) = script.next(original)
  let assert Ok(#(after_second, Error("rate-limited"))) =
    script.next(after_first)

  script.consumed(original)
  |> should.equal(0)
  script.remaining(original)
  |> should.equal(3)
  script.consumed(after_second)
  |> should.equal(2)
  script.remaining(after_second)
  |> should.equal(1)
}

pub fn exhausted_script_is_a_typed_error_test() {
  script.new([])
  |> script.next
  |> should.equal(Error(script.Exhausted))
}

pub fn seeded_generation_is_repeatable_test() {
  let assert Ok(left) = seed.new(42)
  let assert Ok(right) = seed.new(42)
  let #(left_next, left_value) = seed.next(left)
  let #(right_next, right_value) = seed.next(right)

  left_value
  |> should.equal(right_value)
  left_value
  |> should.equal(2_027_382)
  seed.value(left_next)
  |> should.equal(seed.value(right_next))
  seed.value(left)
  |> should.equal(42)
}

pub fn seeded_range_is_explicit_test() {
  let assert Ok(seed) = seed.new(7)
  let assert Ok(#(_, value)) = seed.between(seed, 10, 12)
  let in_range = value >= 10 && value <= 12

  in_range
  |> should.be_true
  seed
  |> seed.between(12, 10)
  |> should.equal(Error(seed.InvalidRange))
}
