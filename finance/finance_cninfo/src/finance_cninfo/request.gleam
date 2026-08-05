import finance_cninfo.{type Access, type DocumentRef}
import finance_core/time
import finance_http/request
import gleam/option.{None}
import gleam/result

pub const origin = "https://static.cninfo.com.cn"

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
