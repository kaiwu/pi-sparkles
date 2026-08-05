import finance_authority_pdf
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_authority_pdf.status()
  |> should.equal(finance_authority_pdf.Experimental)
}
