import finance_core/time
import finance_http/request
import finance_sfc.{type Access}
import gleam/option.{None}
import gleam/result

pub const origin = "https://www.sfc.hk"

pub const press_releases_path = "/en/RSS-Feeds/Press-releases"

pub type RequestError {
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_sfc.AccessError)
}

pub fn press_releases(access: Access) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(15_000)
  use base <- result.try(
    request.new(request.Get, origin, press_releases_path, None)
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(
    request.with_header(
      base,
      name: "Accept",
      value: "application/rss+xml, application/xml;q=0.9, text/xml;q=0.8",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use bounded <- result.try(
    request.with_limits(
      accepted,
      timeout: timeout,
      maximum_response_bytes: 1_000_000,
    )
    |> result.map_error(InvalidHttp),
  )
  finance_sfc.authorize(access, bounded) |> result.map_error(InvalidAccess)
}
