import finance_cninfo.{type Access, type DocumentRef}
import finance_cninfo/disclosure.{type Query}
import finance_core/time
import finance_http/request
import gleam/option.{None}
import gleam/result

pub const origin = "https://static.cninfo.com.cn"

pub const discovery_origin = "https://www.cninfo.com.cn"

pub const security_master_path = "/new/data/szse_stock.json"

pub const announcement_query_path = "/new/hisAnnouncement/query"

pub type RequestError {
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_cninfo.AccessError)
}

pub fn document(
  access: Access,
  reference: DocumentRef,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(20_000)
  use base <- result.try(
    request.new(request.Get, origin, finance_cninfo.path(reference), None)
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(
    request.with_header(
      base,
      name: "Accept",
      value: "application/pdf, application/octet-stream;q=0.8",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(
      accepted,
      timeout: timeout,
      maximum_response_bytes: 25_000_000,
    )
    |> result.map_error(InvalidHttp),
  )
  finance_cninfo.authorize(access, bounded) |> result.map_error(InvalidAccess)
}

pub fn security_master(
  access: Access,
) -> Result(request.Request, RequestError) {
  build_discovery_get(access, security_master_path, 5_000_000)
}

pub fn announcements(
  access: Access,
  query: Query,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(20_000)
  use base <- result.try(
    request.new(request.Post, discovery_origin, announcement_query_path, None)
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
      value: "https://www.cninfo.com.cn/new/commonUrl/pageOfSearch?url=disclosure/list/search",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use with_body <- result.try(
    request.with_text_body(
      referred,
      content_type: "application/x-www-form-urlencoded; charset=UTF-8",
      value: disclosure.form_body(query),
      safe_variant: disclosure.safe_variant(query),
    )
    |> result.map_error(InvalidHttp),
  )
  use repeatable <- result.try(
    request.as_repeatable_read(with_body) |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(
      repeatable,
      timeout: timeout,
      maximum_response_bytes: 5_000_000,
    )
    |> result.map_error(InvalidHttp),
  )
  finance_cninfo.authorize(access, bounded) |> result.map_error(InvalidAccess)
}

fn build_discovery_get(
  access: Access,
  path: String,
  maximum_bytes: Int,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(20_000)
  use base <- result.try(
    request.new(request.Get, discovery_origin, path, None)
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
  use bounded <- result.try(
    request.with_limits(
      accepted,
      timeout: timeout,
      maximum_response_bytes: maximum_bytes,
    )
    |> result.map_error(InvalidHttp),
  )
  finance_cninfo.authorize(access, bounded) |> result.map_error(InvalidAccess)
}
