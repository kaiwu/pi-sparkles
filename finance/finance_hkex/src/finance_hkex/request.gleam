import finance_core/time
import finance_hkex.{type Access, type Board, type DocumentRef}
import finance_hkex/security_search.{type Query as SecurityQuery}
import finance_hkex/title_search.{type Plan}
import finance_http/request
import gleam/option.{None}
import gleam/result

pub const origin = "https://www1.hkexnews.hk"

pub const securities_origin = "https://www.hkex.com.hk"

pub const full_list_path = "/eng/services/trading/securities/securitieslists/ListOfSecurities.xlsx"

pub const recent_listings_path = "/Services/Trading/Securities/Trading-News/Newly-Listed-Securities"

pub const board_meeting_origin = "https://www3.hkexnews.hk"

pub const main_board_meetings_path = "/reports/bmn/ebmn.htm"

pub const gem_board_meetings_path = "/reports/bmn/ebmngem.htm"

pub const security_prefix_path = "/search/prefix.do"

pub const title_search_path = "/search/titlesearch.xhtml"

pub type RequestError {
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_hkex.AccessError)
}

pub fn full_list(access: Access) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(30_000)
  use base <- result.try(
    request.new(request.Get, securities_origin, full_list_path, None)
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(
    request.with_header(
      base,
      name: "Accept",
      value: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(
      accepted,
      timeout: timeout,
      maximum_response_bytes: 2_000_000,
    )
    |> result.map_error(InvalidHttp),
  )
  finance_hkex.authorize(access, bounded) |> result.map_error(InvalidAccess)
}

pub fn recent_listings(
  access: Access,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(30_000)
  use base <- result.try(
    request.new(request.Get, securities_origin, recent_listings_path, None)
    |> result.map_error(InvalidHttp),
  )
  use language <- result.try(public_query(base, "sc_lang", "en"))
  use accepted <- result.try(
    request.with_header(
      language,
      name: "Accept",
      value: "text/html, application/xhtml+xml;q=0.9",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(
      accepted,
      timeout: timeout,
      maximum_response_bytes: 4_000_000,
    )
    |> result.map_error(InvalidHttp),
  )
  finance_hkex.authorize(access, bounded) |> result.map_error(InvalidAccess)
}

pub fn board_meetings(
  access: Access,
  board: Board,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(30_000)
  let path = case board {
    finance_hkex.MainBoard -> main_board_meetings_path
    finance_hkex.Gem -> gem_board_meetings_path
  }
  use base <- result.try(
    request.new(request.Get, board_meeting_origin, path, None)
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(
    request.with_header(
      base,
      name: "Accept",
      value: "text/html, application/xhtml+xml;q=0.9",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(
      accepted,
      timeout: timeout,
      maximum_response_bytes: 2_000_000,
    )
    |> result.map_error(InvalidHttp),
  )
  finance_hkex.authorize(access, bounded) |> result.map_error(InvalidAccess)
}

pub fn document(
  access: Access,
  reference: DocumentRef,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(20_000)
  use base <- result.try(
    request.new(request.Get, origin, finance_hkex.path(reference), None)
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
  finance_hkex.authorize(access, bounded) |> result.map_error(InvalidAccess)
}

pub fn security_prefix(
  access: Access,
  query: SecurityQuery,
) -> Result(request.Request, RequestError) {
  use base <- result.try(discovery_get(access, security_prefix_path, 2_000_000))
  use callback <- result.try(public_query(base, "callback", "pi_sparkles"))
  use language <- result.try(public_query(callback, "lang", "EN"))
  use active <- result.try(public_query(language, "type", "A"))
  use named <- result.try(public_query(
    active,
    "name",
    security_search.query_code(query),
  ))
  public_query(named, "market", "SEHK")
}

pub fn titles(
  access: Access,
  plan: Plan,
) -> Result(request.Request, RequestError) {
  use base <- result.try(discovery_get(access, title_search_path, 8_000_000))
  use language <- result.try(public_query(base, "lang", "en"))
  use category <- result.try(public_query(language, "category", "0"))
  use market <- result.try(public_query(category, "market", "SEHK"))
  public_query(market, "stockId", title_search.stock_id_text(plan))
}

fn discovery_get(
  access: Access,
  path: String,
  maximum_bytes: Int,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(20_000)
  use base <- result.try(
    request.new(request.Get, origin, path, None)
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(
    request.with_header(
      base,
      name: "Accept",
      value: "application/json, application/javascript, text/html;q=0.9",
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
  finance_hkex.authorize(access, bounded) |> result.map_error(InvalidAccess)
}

fn public_query(
  value: request.Request,
  name: String,
  content: String,
) -> Result(request.Request, RequestError) {
  request.with_query(value, name, content, request.Public)
  |> result.map_error(InvalidHttp)
}
