import finance_core/time
import finance_http/request
import finance_sse_index.{type Access}
import finance_sse_index/query.{type Query}
import gleam/option.{None}
import gleam/result

pub const origin = "https://query.sse.com.cn"

pub const constituents_path = "/commonSoaQuery.do"

pub type RequestError {
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_sse_index.AccessError)
}

pub fn constituents(
  access: Access,
  query: Query,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(15_000)
  use base <- result.try(
    request.new(request.Get, origin, constituents_path, None)
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(
    request.with_header(
      base,
      name: "Accept",
      value: "application/json",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use referred <- result.try(
    request.with_header(
      accepted,
      name: "Referer",
      value: "https://www.sse.com.cn/",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(
      referred,
      timeout: timeout,
      maximum_response_bytes: 200_000,
    )
    |> result.map_error(InvalidHttp),
  )
  use paginated <- result.try(public_query(bounded, "isPagination", "true"))
  use operation <- result.try(public_query(
    paginated,
    "sqlId",
    "DB_SZZSLB_CFGLB",
  ))
  use identity <- result.try(public_query(
    operation,
    "indexCode",
    query.code(query),
  ))
  use page_size <- result.try(public_query(identity, "pageHelp.pageSize", "60"))
  use page_number <- result.try(public_query(page_size, "pageHelp.pageNo", "1"))
  use begin <- result.try(public_query(page_number, "pageHelp.beginPage", "1"))
  use cached <- result.try(public_query(begin, "pageHelp.cacheSize", "1"))
  finance_sse_index.authorize(access, cached)
  |> result.map_error(InvalidAccess)
}

pub fn industry_composition(
  access: Access,
  query: Query,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(15_000)
  use base <- result.try(
    request.new(request.Get, origin, constituents_path, None)
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(
    request.with_header(
      base,
      name: "Accept",
      value: "application/json",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use referred <- result.try(
    request.with_header(
      accepted,
      name: "Referer",
      value: "https://www.sse.com.cn/",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(
      referred,
      timeout: timeout,
      maximum_response_bytes: 100_000,
    )
    |> result.map_error(InvalidHttp),
  )
  use unpaginated <- result.try(public_query(bounded, "isPagination", "false"))
  use operation <- result.try(public_query(
    unpaginated,
    "sqlId",
    "DB_SZZSLB_QZHYLB",
  ))
  use identity <- result.try(public_query(
    operation,
    "indexCode",
    query.code(query),
  ))
  finance_sse_index.authorize(access, identity)
  |> result.map_error(InvalidAccess)
}

pub fn canonical_url(query: Query) -> String {
  "https://www.sse.com.cn/market/sseindex/indexlist/basic/index.shtml?COMPANY_CODE="
  <> query.code(query)
  <> "&INDEX_Code="
  <> query.code(query)
  <> "&type=1"
}

fn public_query(
  value: request.Request,
  name: String,
  content: String,
) -> Result(request.Request, RequestError) {
  request.with_query(value, name, content, request.Public)
  |> result.map_error(InvalidHttp)
}
