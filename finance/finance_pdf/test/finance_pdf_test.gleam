import finance_core/time
import finance_pdf
import finance_pdf/inspector
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_pdf.status() |> should.equal(finance_pdf.Experimental)
}

pub fn inspection_policy_is_explicitly_bounded_test() {
  inspector.policy(25_000_000, 2000, duration(10_000)) |> should.be_ok
  inspector.policy(0, 2000, duration(10_000))
  |> should.equal(Error(inspector.InvalidMaximumBytes))
  inspector.policy(25_000_000, 0, duration(10_000))
  |> should.equal(Error(inspector.InvalidMaximumPages))
  inspector.policy(25_000_000, 2000, duration(0))
  |> should.equal(Error(inspector.InvalidTimeout))
}

fn duration(value: Int) -> time.Duration {
  let assert Ok(parsed) = time.duration(value)
  parsed
}
