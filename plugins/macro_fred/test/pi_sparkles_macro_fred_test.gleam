import finance_core/time
import finance_fred/request
import finance_fred/series
import finance_provenance/identity
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_macro_fred/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn plan_is_exact_and_not_a_market_track_test() {
  let assert Ok(value) = plan()
  value.query.series_id |> should.equal("CPIAUCSL")
  value.query.maximum_observations |> should.equal(24)

  domain.plan("CPI/AUCSL", "2025-01-01", "2025-12-31", "2026-01-15", 24)
  |> should.equal(Error(domain.InvalidQuery(series.InvalidSeriesId)))
}

pub fn result_preserves_metadata_observations_and_exact_change_test() {
  let assert Ok(query) = plan()
  let assert Ok(output) =
    domain.run(
      query,
      capture([
        point("2025-01-01", "320.500"),
        point("2025-02-01", "321.10"),
      ]),
    )
  let text = json.to_string(output.details)

  text |> string.contains("\"track\":null") |> should.be_true
  text |> string.contains("\"rawValue\":\"320.500\"") |> should.be_true
  text |> string.contains("\"value\":\"0.6\"") |> should.be_true
  text
  |> string.contains("\"expression\":\"latest - previous\"")
  |> should.be_true
  text
  |> string.contains("\"seasonalAdjustment\":\"Seasonally Adjusted\"")
  |> should.be_true
  text
  |> string.contains("utc_midnight_ordering_anchor_only")
  |> should.be_true
  text |> string.contains("not_provider_signature") |> should.be_true
  output.summary |> string.contains("No forecast") |> should.be_true
}

pub fn missing_latest_is_not_skipped_and_change_is_not_calculated_test() {
  let assert Ok(query) = plan()
  let assert Ok(output) =
    domain.run(
      query,
      capture([
        point("2025-01-01", "320.500"),
        point("2025-02-01", "."),
      ]),
    )
  let text = json.to_string(output.details)

  text
  |> string.contains("\"reason\":\"latest_source_value_not_numeric\"")
  |> should.be_true
  text
  |> string.contains("\"state\":\"not_calculated\"")
  |> should.be_true
  text
  |> string.contains("\"quality\":{\"tag\":\"missing\"")
  |> should.be_true
}

pub fn empty_range_retains_metadata_without_inventing_latest_test() {
  let assert Ok(query) = plan()
  let assert Ok(output) = domain.run(query, capture([]))
  let text = json.to_string(output.details)

  text |> string.contains("\"observationCount\":0") |> should.be_true
  text
  |> string.contains("\"reason\":\"no_observations\"")
  |> should.be_true
}

pub fn response_receipts_must_match_exact_endpoints_test() {
  let assert Ok(query) = plan()
  let value = capture([point("2025-01-01", "320.500")])
  domain.run(
    query,
    domain.Capture(
      ..value,
      metadata_receipt: domain.Receipt(
        request.observations_path,
        None,
        100,
        digest("a"),
      ),
    ),
  )
  |> should.equal(Error(domain.InvalidReceipt))
}

fn plan() -> Result(domain.Plan, domain.Error) {
  domain.plan("CPIAUCSL", "2025-01-01", "2025-12-31", "2026-01-15", 24)
}

fn capture(points: List(series.Point)) -> domain.Capture {
  let assert Ok(retrieved_at) = time.instant(1_768_521_600_000)
  domain.Capture(
    series.Metadata(
      "CPIAUCSL",
      "2026-01-15",
      "2026-01-15",
      "Consumer Price Index for All Urban Consumers",
      "1947-01-01",
      "2025-12-01",
      "Monthly",
      "M",
      "Index 1982-1984=100",
      "Index 1982-1984=100",
      "Seasonally Adjusted",
      "SA",
      "2026-01-14 07:42:02-06",
      95,
      None,
    ),
    domain.Receipt(request.metadata_path, Some("meta-1"), 400, digest("a")),
    series.ObservationRange(
      "2026-01-15",
      "2026-01-15",
      "2025-01-01",
      "2025-12-31",
      "lin",
      1,
      "json",
      "observation_date",
      "asc",
      list.length(points),
      0,
      24,
      points,
    ),
    domain.Receipt(
      request.observations_path,
      Some("observations-1"),
      800,
      digest("b"),
    ),
    retrieved_at,
  )
}

fn point(date_text: String, raw_value: String) -> series.Point {
  let assert [year_text, month_text, day_text] = string.split(date_text, "-")
  let assert Ok(year) = int.parse(year_text)
  let assert Ok(month) = int.parse(month_text)
  let assert Ok(day) = int.parse(day_text)
  let assert Ok(date) = time.date(year, month, day)
  series.Point("2026-01-15", "2026-01-15", date, date_text, raw_value)
}

fn digest(character: String) -> identity.Sha256 {
  let assert Ok(value) = identity.sha256(string.repeat(character, 64))
  value
}
