import finance_core/time
import finance_fred
import finance_fred/request
import finance_fred/runtime
import finance_fred/series
import finance_http/request as http_request
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn access_requires_exact_per_user_key_shape_test() {
  finance_fred.access("abcdefghijklmnopqrstuvwxyz123456") |> should.be_ok
  finance_fred.access("ABCDEFGHIJKLMNOPQRSTUVWXYZ123456")
  |> should.equal(Error(finance_fred.InvalidApiKey))
  finance_fred.access("short")
  |> should.equal(Error(finance_fred.InvalidApiKey))
}

pub fn requests_are_exact_bounded_and_keep_key_secret_test() {
  let assert Ok(access) =
    finance_fred.access("abcdefghijklmnopqrstuvwxyz123456")
  let assert Ok(query) =
    series.query("CPIAUCSL", "2025-01-01", "2025-12-31", "2026-01-15", 24)
  let assert Ok(metadata) = request.metadata(access, query)
  let assert Ok(observations) = request.observations(access, query)

  http_request.origin(metadata) |> should.equal(request.origin)
  http_request.path(metadata) |> should.equal(request.metadata_path)
  http_request.maximum_response_bytes(metadata) |> should.equal(250_000)
  http_request.path(observations) |> should.equal(request.observations_path)
  http_request.maximum_response_bytes(observations) |> should.equal(2_000_000)
  time.duration_milliseconds(http_request.timeout(observations))
  |> should.equal(15_000)
  http_request.query(observations)
  |> list.contains(http_request.QueryParameter(
    "api_key",
    "abcdefghijklmnopqrstuvwxyz123456",
    http_request.Secret,
  ))
  |> should.be_true
  http_request.query(observations)
  |> list.contains(http_request.QueryParameter(
    "units",
    "lin",
    http_request.Public,
  ))
  |> should.be_true
  http_request.query(observations)
  |> list.contains(http_request.QueryParameter(
    "limit",
    "24",
    http_request.Public,
  ))
  |> should.be_true
}

pub fn metadata_decoder_preserves_exact_provider_fields_and_optional_notes_test() {
  let assert Ok(query) =
    series.query("CPIAUCSL", "2025-01-01", "2025-12-31", "2026-01-15", 24)
  let assert Ok(value) = series.decode_metadata(metadata_fixture(), query)

  value.id |> should.equal("CPIAUCSL")
  value.units |> should.equal("Index 1982-1984=100")
  value.seasonal_adjustment |> should.equal("Seasonally Adjusted")
  value.last_updated |> should.equal("2026-01-14 07:42:02-06")
  value.notes |> should.equal(None)
}

pub fn observation_decoder_preserves_lexemes_missing_rows_and_order_test() {
  let assert Ok(query) =
    series.query("CPIAUCSL", "2025-01-01", "2025-12-31", "2026-01-15", 24)
  let assert Ok(value) =
    series.decode_observations(observations_fixture(3, 24), query)
  let assert [first, second, third] = value.observations

  first.raw_value |> should.equal("320.500")
  second.raw_value |> should.equal("321.10")
  third.raw_value |> should.equal(".")
  third.date_text |> should.equal("2025-03-01")
}

pub fn incomplete_or_mismatched_ranges_fail_closed_test() {
  let assert Ok(query) =
    series.query("CPIAUCSL", "2025-01-01", "2025-12-31", "2026-01-15", 2)
  series.decode_observations(observations_fixture(3, 2), query)
  |> should.equal(Error(series.Truncated(2, 3)))

  let assert Ok(ordered_query) =
    series.query("CPIAUCSL", "2025-01-01", "2025-12-31", "2026-01-15", 24)
  observations_fixture(3, 24)
  |> string.replace("2025-02-01", "2024-12-01")
  |> series.decode_observations(ordered_query)
  |> should.equal(Error(series.RangeMismatch))

  metadata_fixture()
  |> string.replace("CPIAUCSL", "UNRATE")
  |> series.decode_metadata(ordered_query)
  |> should.equal(Error(series.SeriesMismatch("CPIAUCSL", "UNRATE")))
}

pub fn query_and_runtime_enforce_local_bounds_test() {
  series.query("CPI/AUCSL", "2025-01-01", "2025-12-31", "2026-01-15", 24)
  |> should.equal(Error(series.InvalidSeriesId))
  series.query("CPIAUCSL", "2025-12-31", "2025-01-01", "2026-01-15", 24)
  |> should.equal(Error(series.InvalidObservationRange))
  series.query("CPIAUCSL", "2025-01-01", "2025-12-31", "2026-01-15", 1001)
  |> should.equal(Error(series.InvalidMaximumObservations))
  runtime.new() |> should.be_ok
}

fn metadata_fixture() -> String {
  "{\"realtime_start\":\"2026-01-15\",\"realtime_end\":\"2026-01-15\",\"seriess\":[{\"id\":\"CPIAUCSL\",\"realtime_start\":\"2026-01-15\",\"realtime_end\":\"2026-01-15\",\"title\":\"Consumer Price Index for All Urban Consumers\",\"observation_start\":\"1947-01-01\",\"observation_end\":\"2025-12-01\",\"frequency\":\"Monthly\",\"frequency_short\":\"M\",\"units\":\"Index 1982-1984=100\",\"units_short\":\"Index 1982-1984=100\",\"seasonal_adjustment\":\"Seasonally Adjusted\",\"seasonal_adjustment_short\":\"SA\",\"last_updated\":\"2026-01-14 07:42:02-06\",\"popularity\":95}]}"
}

fn observations_fixture(count: Int, limit: Int) -> String {
  "{\"realtime_start\":\"2026-01-15\",\"realtime_end\":\"2026-01-15\",\"observation_start\":\"2025-01-01\",\"observation_end\":\"2025-12-31\",\"units\":\"lin\",\"output_type\":1,\"file_type\":\"json\",\"order_by\":\"observation_date\",\"sort_order\":\"asc\",\"count\":"
  <> int.to_string(count)
  <> ",\"offset\":0,\"limit\":"
  <> int.to_string(limit)
  <> ",\"observations\":[{\"realtime_start\":\"2026-01-15\",\"realtime_end\":\"2026-01-15\",\"date\":\"2025-01-01\",\"value\":\"320.500\"},{\"realtime_start\":\"2026-01-15\",\"realtime_end\":\"2026-01-15\",\"date\":\"2025-02-01\",\"value\":\"321.10\"},{\"realtime_start\":\"2026-01-15\",\"realtime_end\":\"2026-01-15\",\"date\":\"2025-03-01\",\"value\":\".\"}]}"
}
