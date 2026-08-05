import finance_core/identifier
import finance_hkex/security_search
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import pi_sparkles_hk_disclosures/selection

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn disclosure_identity_selection_never_guesses_test() {
  let assert Ok([first, second]) =
    security_search.decode(
      "pi_sparkles({\"more\":\"1\",\"stockInfo\":[{\"stockId\":1,\"code\":\"00700\",\"name\":\"FIRST\"},{\"stockId\":2,\"code\":\"00700\",\"name\":\"SECOND\"}]});",
    )
  let resolution = identifier.Ambiguous(first, second, [])

  selection.select(resolution, None)
  |> should.equal(Error(selection.AmbiguousCandidates(2)))
  let assert Ok(selected) = selection.select(resolution, Some(2))
  security_search.stock_id(selected) |> should.equal(2)
  selection.select(resolution, Some(3))
  |> should.equal(Error(selection.StockIdMismatch))
}
