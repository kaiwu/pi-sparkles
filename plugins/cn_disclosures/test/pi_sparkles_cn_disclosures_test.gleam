import finance_cninfo/security_master
import finance_core/identifier
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import pi_sparkles_cn_disclosures/selection

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn disclosure_identity_selection_never_guesses_test() {
  let assert Ok([first, second]) =
    security_master.decode(
      "{\"stockList\":[{\"code\":\"000001\",\"pinyin\":\"a\",\"category\":\"A股\",\"orgId\":\"org_a\",\"zwjc\":\"甲\"},{\"code\":\"000001\",\"pinyin\":\"b\",\"category\":\"A股\",\"orgId\":\"org_b\",\"zwjc\":\"乙\"}]}",
    )
  let resolution = identifier.Ambiguous(first, second, [])

  selection.select(resolution, None)
  |> should.equal(Error(selection.AmbiguousCandidates(2)))
  let assert Ok(selected) = selection.select(resolution, Some("org_b"))
  security_master.organization_id(selected) |> should.equal("org_b")
  selection.select(resolution, Some("missing"))
  |> should.equal(Error(selection.OrganizationIdMismatch))
}
