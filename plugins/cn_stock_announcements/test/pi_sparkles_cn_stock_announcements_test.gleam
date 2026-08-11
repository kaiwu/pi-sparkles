import finance_cninfo/security_master
import finance_core/identifier
import gleam/json
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import pi_sparkles_cn_stock_announcements/selection

pub fn main() {
  gleeunit.main()
}

pub fn ambiguous_issuer_requires_organization_id_test() {
  let assert Ok([first, second]) = security_master.decode(fixture())
  selection.select(identifier.Ambiguous(first, second, []), None)
  |> should.equal(Error(selection.AmbiguousCandidates(2)))
}

pub fn exact_organization_id_selects_only_matching_candidate_test() {
  let assert Ok([first, second]) = security_master.decode(fixture())
  selection.select(identifier.Ambiguous(first, second, []), Some("gssz0000002"))
  |> should.equal(Ok(second))
}

fn fixture() -> String {
  json.object([
    #(
      "stockList",
      json.array(["gssz0000001", "gssz0000002"], fn(organization_id) {
        json.object([
          #("code", json.string("000001")),
          #("orgId", json.string(organization_id)),
          #("zwjc", json.string("平安银行")),
          #("category", json.string("A股")),
          #("pinyin", json.string("payh")),
        ])
      }),
    ),
  ])
  |> json.to_string
}
