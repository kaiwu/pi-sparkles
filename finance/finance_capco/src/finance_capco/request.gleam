import finance_capco.{type Snapshot}
import finance_core/time
import finance_http/request
import gleam/option.{None}
import gleam/result

pub type RequestError {
  InvalidHttp(request.RequestError)
}

pub fn classification_pdf(
  snapshot: Snapshot,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(20_000)
  use base <- result.try(
    request.new(request.Get, snapshot.pdf_origin, snapshot.pdf_path, None)
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(
    request.with_header(
      base,
      name: "Accept",
      value: "application/pdf",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  request.with_limits(
    accepted,
    timeout: timeout,
    maximum_response_bytes: 1_000_000,
  )
  |> result.map_error(InvalidHttp)
}
