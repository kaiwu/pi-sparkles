import finance_core/time
import finance_fred.{type Access}
import finance_fred/series.{type Query}
import finance_http/request
import gleam/int
import gleam/option.{None}
import gleam/result

pub const origin = "https://api.stlouisfed.org"

pub const metadata_path = "/fred/series"

pub const observations_path = "/fred/series/observations"

pub type RequestError {
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_fred.AccessError)
}

pub fn metadata(
  access: Access,
  query: Query,
) -> Result(request.Request, RequestError) {
  use value <- result.try(base(metadata_path, 250_000))
  use value <- result.try(
    request.with_query(value, "series_id", query.series_id, request.Public)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(value, "file_type", "json", request.Public)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(
      value,
      "realtime_start",
      series.date_text(query.as_of_date),
      request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(
      value,
      "realtime_end",
      series.date_text(query.as_of_date),
      request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  finance_fred.authorize(access, value) |> result.map_error(InvalidAccess)
}

pub fn observations(
  access: Access,
  query: Query,
) -> Result(request.Request, RequestError) {
  use value <- result.try(base(observations_path, 2_000_000))
  use value <- result.try(
    request.with_query(value, "series_id", query.series_id, request.Public)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(value, "file_type", "json", request.Public)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(
      value,
      "realtime_start",
      series.date_text(query.as_of_date),
      request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(
      value,
      "realtime_end",
      series.date_text(query.as_of_date),
      request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(
      value,
      "observation_start",
      series.date_text(query.observation_start),
      request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(
      value,
      "observation_end",
      series.date_text(query.observation_end),
      request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(value, "units", "lin", request.Public)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(value, "output_type", "1", request.Public)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(value, "sort_order", "asc", request.Public)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(
      value,
      "limit",
      int.to_string(query.maximum_observations),
      request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_query(value, "offset", "0", request.Public)
    |> result.map_error(InvalidHttp),
  )
  finance_fred.authorize(access, value) |> result.map_error(InvalidAccess)
}

fn base(
  path: String,
  maximum_response_bytes: Int,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(15_000)
  use value <- result.try(
    request.new(request.Get, origin, path, None)
    |> result.map_error(InvalidHttp),
  )
  use value <- result.try(
    request.with_limits(value, timeout, maximum_response_bytes)
    |> result.map_error(InvalidHttp),
  )
  request.with_header(value, "Accept", "application/json", request.Public)
  |> result.map_error(InvalidHttp)
}
