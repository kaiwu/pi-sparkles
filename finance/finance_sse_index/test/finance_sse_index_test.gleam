import finance_http/request as http_request
import finance_sse_index
import finance_sse_index/composition
import finance_sse_index/constituents
import finance_sse_index/query
import finance_sse_index/request
import gleam/int
import gleam/json
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn reviewed_identity_builds_one_bounded_official_request_test() {
  let assert Ok(access) =
    finance_sse_index.access("product/1", "test@example.com")
  let assert Ok(plan) = query.constituents("sse", "000688")
  let assert Ok(value) = request.constituents(access, plan)

  http_request.origin(value) |> should.equal("https://query.sse.com.cn")
  http_request.path(value) |> should.equal("/commonSoaQuery.do")
  http_request.maximum_response_bytes(value) |> should.equal(200_000)
  http_request.query(value) |> list.length |> should.equal(7)
  http_request.headers(value) |> list.length |> should.equal(3)
}

pub fn unreviewed_index_is_rejected_locally_test() {
  query.constituents("sse", "000001") |> should.be_error
  query.constituents("szse", "000688") |> should.be_error
}

pub fn exact_current_manifest_decodes_with_publication_date_test() {
  let assert Ok(plan) = query.constituents("sse", "000688")
  let assert Ok(value) = constituents.decode(fixture(0), for: plan)

  constituents.publication_date(value) |> should.equal("2026-08-19")
  constituents.members(value) |> list.length |> should.equal(50)
  let assert [first, ..] = constituents.members(value)
  constituents.code(first) |> should.equal("688001")
  constituents.name(first) |> should.equal("成员1")
}

pub fn duplicate_member_identity_fails_closed_test() {
  let assert Ok(plan) = query.constituents("sse", "000688")
  constituents.decode(fixture(2), for: plan) |> should.be_error
}

pub fn exact_industry_composition_preserves_weight_lexemes_test() {
  let assert Ok(plan) = query.constituents("sse", "000688")
  let body =
    "{\"result\":[{\"securityNum\":31,\"level1Code\":\"45\",\"level1Name\":\"信息技术\",\"indexCode\":\"000688\",\"weight\":85.544,\"level1NameEn\":\"Information Technology\",\"effectiveDate\":\"20260818\"},{\"securityNum\":19,\"level1Code\":\"35\",\"level1Name\":\"工业\",\"indexCode\":\"000688\",\"weight\":14.4560,\"level1NameEn\":\"Industrials\",\"effectiveDate\":\"20260818\"}]}"
  let assert Ok(value) = composition.decode(body, for: plan)
  composition.effective_date(value) |> should.equal("20260818")
  let assert [first, second] = composition.sectors(value)
  composition.security_count(first) |> should.equal(31)
  composition.weight_raw(first) |> should.equal("85.544")
  composition.weight_raw(second) |> should.equal("14.4560")
}

fn fixture(duplicate_at: Int) -> String {
  let rows = indices(1, [])
  json.object([
    #(
      "pageHelp",
      json.object([
        #("pageCount", json.int(1)),
        #("total", json.int(50)),
        #("pageNo", json.int(1)),
        #("pageSize", json.int(60)),
      ]),
    ),
    #(
      "result",
      json.array(rows, fn(index) {
        let code = case duplicate_at == index {
          True -> "688001"
          False -> member_code(index)
        }
        json.object([
          #("securityAbbrEn", json.string("Member " <> int.to_string(index))),
          #("securityAbbr", json.string("成员" <> int.to_string(index))),
          #("inDate", json.string("2026-08-19")),
          #("securityCode", json.string(code)),
          #("marketSource", json.string("1")),
        ])
      }),
    ),
  ])
  |> json.to_string
}

fn indices(next: Int, values: List(Int)) -> List(Int) {
  case next > 50 {
    True -> list.reverse(values)
    False -> indices(next + 1, [next, ..values])
  }
}

fn member_code(index: Int) -> String {
  case index < 10 {
    True -> "68800" <> int.to_string(index)
    False -> "6880" <> int.to_string(index)
  }
}
