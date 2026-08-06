import finance_archive
import finance_http/transport
import gleam/javascript/promise
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_entry_and_budget_policy_is_fail_closed_test() {
  finance_archive.policy(
    required_entries: ["xl/workbook.xml", "xl/worksheets/sheet1.xml"],
    maximum_archive_bytes: 2_000_000,
    maximum_entries: 32,
    maximum_entry_bytes: 20_000_000,
    maximum_total_uncompressed_bytes: 25_000_000,
  )
  |> should.be_ok

  finance_archive.policy(
    required_entries: ["../secret"],
    maximum_archive_bytes: 2_000_000,
    maximum_entries: 32,
    maximum_entry_bytes: 20_000_000,
    maximum_total_uncompressed_bytes: 25_000_000,
  )
  |> should.equal(Error(finance_archive.InvalidRequiredEntry("../secret")))

  finance_archive.policy(
    required_entries: ["xl/workbook.xml", "xl/workbook.xml"],
    maximum_archive_bytes: 2_000_000,
    maximum_entries: 32,
    maximum_entry_bytes: 20_000_000,
    maximum_total_uncompressed_bytes: 25_000_000,
  )
  |> should.equal(
    Error(finance_archive.DuplicateRequiredEntry("xl/workbook.xml")),
  )
}

pub fn cancelled_extraction_never_enters_archive_ffi_test() {
  let assert Ok(policy) =
    finance_archive.policy(
      required_entries: ["xl/workbook.xml"],
      maximum_archive_bytes: 2_000_000,
      maximum_entries: 32,
      maximum_entry_bytes: 20_000_000,
      maximum_total_uncompressed_bytes: 25_000_000,
    )
  let cancellation = transport.new_cancellation()
  transport.cancel(cancellation)

  use outcome <- promise.await(finance_archive.extract(
    policy,
    "not-even-base64",
    cancellation,
  ))
  outcome |> should.equal(Error(finance_archive.Cancelled))
  promise.resolve(Nil)
}
