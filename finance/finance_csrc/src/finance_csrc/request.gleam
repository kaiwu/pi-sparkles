import finance_core/time
import finance_csrc.{type Access, type Dataset}
import finance_http/request
import gleam/option.{None}
import gleam/result

pub const origin = "https://www.csrc.gov.cn"

pub const market_monthly_path = "/csrc/c100120/common_list.shtml"

pub const market_weekly_path = "/csrc/c100119/common_list.shtml"

pub const consultation_feedback_path = "/csrc/c100114/common_list.shtml"

pub type RequestError {
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_csrc.AccessError)
}

pub fn snapshot(
  access: Access,
  dataset: Dataset,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(15_000)
  use base <- result.try(
    request.new(request.Get, origin, path(dataset), None)
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
  finance_csrc.authorize(access, bounded) |> result.map_error(InvalidAccess)
}

pub fn path(value: Dataset) -> String {
  case value {
    finance_csrc.MarketMonthly -> market_monthly_path
    finance_csrc.MarketWeekly -> market_weekly_path
    finance_csrc.ConsultationFeedback -> consultation_feedback_path
  }
}
