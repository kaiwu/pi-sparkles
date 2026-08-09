import finance_calendar/date
import finance_core/adjustment
import finance_core/decimal
import finance_core/market
import finance_core/observation.{type Observation}
import finance_core/observation_json
import finance_core/source
import finance_core/time.{type Date, type Instant}
import finance_fred/request as provider_request
import finance_fred/series
import finance_math/formula
import finance_provenance/identity.{type Sha256}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

const provider = "Federal Reserve Bank of St. Louis FRED"

pub type Plan {
  Plan(query: series.Query)
}

pub type Receipt {
  Receipt(
    endpoint: String,
    request_id: Option(String),
    response_byte_length: Int,
    content_sha256: Sha256,
  )
}

pub type Capture {
  Capture(
    metadata: series.Metadata,
    metadata_receipt: Receipt,
    range: series.ObservationRange,
    observations_receipt: Receipt,
    retrieved_at: Instant,
  )
}

pub type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  InvalidQuery(series.QueryError)
  InvalidReceipt
  InvalidSource(source.SourceError)
  InvalidUnit(market.MarketError)
  InvalidAdjustment(adjustment.AdjustmentError)
  InvalidObservationDate
  InvalidCalculation
}

pub fn plan(
  series_id: String,
  observation_start: String,
  observation_end: String,
  as_of_date: String,
  maximum_observations: Int,
) -> Result(Plan, Error) {
  series.query(
    series_id,
    observation_start,
    observation_end,
    as_of_date,
    maximum_observations,
  )
  |> result.map(Plan)
  |> result.map_error(InvalidQuery)
}

pub fn run(plan: Plan, capture: Capture) -> Result(Output, Error) {
  use Nil <- result.try(validate_receipt(
    capture.metadata_receipt,
    provider_request.metadata_path,
  ))
  use Nil <- result.try(validate_receipt(
    capture.observations_receipt,
    provider_request.observations_path,
  ))
  use source_ref <- result.try(
    source.new(provider, observations_reference(plan.query), source.Official)
    |> result.map_error(InvalidSource),
  )
  use unit <- result.try(
    market.custom_unit(capture.metadata.units) |> result.map_error(InvalidUnit),
  )
  use adjustment_value <- result.try(
    adjustment.provider_adjusted("FRED", capture.metadata.seasonal_adjustment)
    |> result.map_error(InvalidAdjustment),
  )
  use observations <- result.try(
    capture.range.observations
    |> list.try_map(fn(point) {
      use anchor <- result.try(
        date_anchor(point.date)
        |> result.map_error(fn(_) { InvalidObservationDate }),
      )
      Ok(observation.Observation(
        value: point,
        as_of: anchor,
        retrieved_at: capture.retrieved_at,
        timezone: None,
        source: source_ref,
        evidence_id: Some(identity.sha256_value(
          capture.observations_receipt.content_sha256,
        )),
        freshness: observation.UnknownFreshness,
        entitlement: observation.UnknownEntitlement,
        quality: case point.raw_value {
          "." -> observation.Missing(observation.NotReported)
          _ -> observation.Reported
        },
        unit: Some(unit),
        adjustment: Some(adjustment_value),
        session: None,
      ))
    }),
  )
  use change <- result.try(change_json(observations))
  let latest = latest_json(observations)
  let count = list.length(observations)
  Ok(Output(
    summary(plan.query, observations),
    json.object([
      #("schema", json.string("pi-sparkles/macro-fred-series-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("fred_series")),
      #("track", json.null()),
      #(
        "query",
        json.object([
          #("seriesId", json.string(plan.query.series_id)),
          #(
            "observationStart",
            json.string(series.date_text(plan.query.observation_start)),
          ),
          #(
            "observationEnd",
            json.string(series.date_text(plan.query.observation_end)),
          ),
          #("asOfDate", json.string(series.date_text(plan.query.as_of_date))),
          #("maximumObservations", json.int(plan.query.maximum_observations)),
          #("units", json.string("lin")),
          #("sortOrder", json.string("asc")),
          #("outputType", json.int(1)),
        ]),
      ),
      #("metadata", metadata_json(capture.metadata)),
      #("observationCount", json.int(count)),
      #(
        "observations",
        json.array(observations, fn(value) {
          observation_json.to_json(value, point_json)
        }),
      ),
      #("latest", latest),
      #("change", change),
      #(
        "source",
        json.object([
          #("provider", json.string(provider)),
          #("kind", json.string("official_api_aggregator")),
          #("apiVersion", json.string("FRED_v1")),
          #(
            "termsReference",
            json.string(
              "https://fred.stlouisfed.org/docs/api/terms_of_use.html",
            ),
          ),
          #(
            "retrievedAtUnixMs",
            capture.retrieved_at
              |> time.unix_milliseconds
              |> int.to_string
              |> json.string,
          ),
          #(
            "metadata",
            receipt_json(
              capture.metadata_receipt,
              metadata_reference(plan.query),
            ),
          ),
          #(
            "observations",
            receipt_json(
              capture.observations_receipt,
              observations_reference(plan.query),
            ),
          ),
          #(
            "receiptState",
            json.string(
              "sha256_response_content_bound_not_provider_signature_or_origin_authentication",
            ),
          ),
        ]),
      ),
      #(
        "scope",
        json.object([
          #("marketTrack", json.string("not_market_specific")),
          #(
            "realtimeMeaning",
            json.string("information_known_on_exact_as_of_date"),
          ),
          #(
            "observationDateMeaning",
            json.string("source_period_label_not_publication_timestamp"),
          ),
          #(
            "observationTimeBasis",
            json.string(
              "utc_midnight_ordering_anchor_only_not_provider_timestamp",
            ),
          ),
          #("freshness", json.string("unknown_without_release_calendar")),
          #("entitlement", json.string("series_dependent_unknown")),
          #(
            "thirdPartyRights",
            json.string("series_dependent_check_fred_terms_and_series_source"),
          ),
          #("forecast", json.null()),
          #("economicInterpretation", json.null()),
          #("releaseCalendar", json.null()),
          #("vintageComparison", json.null()),
        ]),
      ),
      #(
        "limitations",
        json.array(
          [
            "The result is one FRED v1 point-in-time view; it does not compare ALFRED vintages.",
            "units=lin disables FRED value transformations but does not remove the series' published seasonal-adjustment basis.",
            "Latest means the final source row in the complete bounded requested range; missing final rows are not skipped.",
            "Change is exact latest-minus-immediately-previous arithmetic only; it is not a percentage, trend, surprise, or signal.",
            "Observation dates are source period labels, not release or publication timestamps.",
            "FRED aggregates series whose underlying rights and source authorities can differ.",
          ],
          json.string,
        ),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ]),
  ))
}

pub fn error_message(value: Error) -> String {
  case value {
    InvalidQuery(error) -> query_error_message(error)
    InvalidReceipt -> "fred_series source receipt was invalid"
    InvalidSource(_) -> "fred_series source reference was invalid"
    InvalidUnit(_) -> "fred_series metadata unit was invalid"
    InvalidAdjustment(_) ->
      "fred_series seasonal-adjustment metadata was invalid"
    InvalidObservationDate ->
      "fred_series observation date could not form an ordering anchor"
    InvalidCalculation -> "fred_series exact change calculation failed safely"
  }
}

fn change_json(
  observations: List(Observation(series.Point)),
) -> Result(json.Json, Error) {
  case list.reverse(observations) {
    [] -> Ok(unavailable_change("no_observations"))
    [_] -> Ok(unavailable_change("fewer_than_two_observations"))
    [current, previous, ..] ->
      case
        decimal.parse(current.value.raw_value),
        decimal.parse(previous.value.raw_value)
      {
        Error(_), _ -> Ok(unavailable_change("latest_source_value_not_numeric"))
        _, Error(_) ->
          Ok(unavailable_change("previous_source_value_not_numeric"))
        Ok(current_value), Ok(previous_value) -> {
          let expression =
            formula.Subtract(
              formula.Reference("latest"),
              formula.Reference("previous"),
            )
          case
            formula.evaluate(expression, with: [
              formula.Input("latest", formula.Available(current_value)),
              formula.Input("previous", formula.Available(previous_value)),
            ])
          {
            Error(_) -> Error(InvalidCalculation)
            Ok(value) ->
              Ok(
                json.object([
                  #("state", json.string("calculated")),
                  #("expression", json.string("latest - previous")),
                  #("value", json.string(decimal.to_string(value))),
                  #("unit", json.string("same_as_series_metadata_units")),
                  #("current", point_reference_json(current.value)),
                  #("previous", point_reference_json(previous.value)),
                  #("interpretation", json.null()),
                ]),
              )
          }
        }
      }
  }
}

fn latest_json(observations: List(Observation(series.Point))) -> json.Json {
  case list.reverse(observations) {
    [] ->
      json.object([
        #("state", json.string("not_obtained")),
        #("reason", json.string("no_observations")),
      ])
    [value, ..] ->
      case decimal.parse(value.value.raw_value) {
        Error(_) ->
          json.object([
            #("state", json.string("not_obtained")),
            #("reason", json.string("latest_source_value_not_numeric")),
            #("source", point_reference_json(value.value)),
          ])
        Ok(_) ->
          json.object([
            #("state", json.string("observed")),
            #("source", point_reference_json(value.value)),
          ])
      }
  }
}

fn summary(
  query: series.Query,
  observations: List(Observation(series.Point)),
) -> String {
  let count = list.length(observations)
  let ending = case list.reverse(observations) {
    [] -> "no source observation"
    [value, ..] ->
      case value.value.raw_value {
        "." -> "a final non-numeric source value"
        raw -> "latest " <> raw <> " at " <> value.value.date_text
      }
  }
  "FRED "
  <> query.series_id
  <> " as known on "
  <> series.date_text(query.as_of_date)
  <> ": "
  <> int.to_string(count)
  <> " exact source observation(s), "
  <> ending
  <> ". No forecast, release-time inference, or economic interpretation is made."
}

fn point_json(value: series.Point) -> json.Json {
  json.object([
    #("sourceDate", json.string(value.date_text)),
    #("realtimeStart", json.string(value.realtime_start)),
    #("realtimeEnd", json.string(value.realtime_end)),
    #("rawValue", json.string(value.raw_value)),
    #("numericValue", case decimal.parse(value.raw_value) {
      Ok(number) -> json.string(decimal.to_string(number))
      Error(_) -> json.null()
    }),
  ])
}

fn point_reference_json(value: series.Point) -> json.Json {
  json.object([
    #("date", json.string(value.date_text)),
    #("rawValue", json.string(value.raw_value)),
  ])
}

fn metadata_json(value: series.Metadata) -> json.Json {
  json.object([
    #("id", json.string(value.id)),
    #("realtimeStart", json.string(value.realtime_start)),
    #("realtimeEnd", json.string(value.realtime_end)),
    #("title", json.string(value.title)),
    #("observationStart", json.string(value.observation_start)),
    #("observationEnd", json.string(value.observation_end)),
    #("frequency", json.string(value.frequency)),
    #("frequencyShort", json.string(value.frequency_short)),
    #("units", json.string(value.units)),
    #("unitsShort", json.string(value.units_short)),
    #("seasonalAdjustment", json.string(value.seasonal_adjustment)),
    #("seasonalAdjustmentShort", json.string(value.seasonal_adjustment_short)),
    #("lastUpdated", json.string(value.last_updated)),
    #("popularity", json.int(value.popularity)),
    #("notes", json.nullable(value.notes, json.string)),
  ])
}

fn receipt_json(value: Receipt, reference: String) -> json.Json {
  json.object([
    #("endpoint", json.string(value.endpoint)),
    #("reference", json.string(reference)),
    #("requestId", json.nullable(value.request_id, json.string)),
    #("responseByteLength", json.int(value.response_byte_length)),
    #("contentSha256", json.string(identity.sha256_value(value.content_sha256))),
  ])
}

fn unavailable_change(reason: String) -> json.Json {
  json.object([
    #("state", json.string("not_calculated")),
    #("reason", json.string(reason)),
  ])
}

fn validate_receipt(value: Receipt, endpoint: String) -> Result(Nil, Error) {
  case value.endpoint == endpoint, value.response_byte_length >= 0 {
    True, True -> Ok(Nil)
    _, _ -> Error(InvalidReceipt)
  }
}

fn date_anchor(value: Date) -> Result(Instant, Nil) {
  let assert Ok(epoch) = time.date(1970, 1, 1)
  time.instant(date.days_between(epoch, value) * 86_400_000)
  |> result.map_error(fn(_) { Nil })
}

fn metadata_reference(query: series.Query) -> String {
  provider_request.origin
  <> provider_request.metadata_path
  <> "?series_id="
  <> query.series_id
  <> "&file_type=json&realtime_start="
  <> series.date_text(query.as_of_date)
  <> "&realtime_end="
  <> series.date_text(query.as_of_date)
}

fn observations_reference(query: series.Query) -> String {
  provider_request.origin
  <> provider_request.observations_path
  <> "?series_id="
  <> query.series_id
  <> "&file_type=json&realtime_start="
  <> series.date_text(query.as_of_date)
  <> "&realtime_end="
  <> series.date_text(query.as_of_date)
  <> "&observation_start="
  <> series.date_text(query.observation_start)
  <> "&observation_end="
  <> series.date_text(query.observation_end)
  <> "&units=lin&output_type=1&sort_order=asc&limit="
  <> int.to_string(query.maximum_observations)
  <> "&offset=0"
}

fn query_error_message(value: series.QueryError) -> String {
  case value {
    series.InvalidSeriesId ->
      "fred_series seriesId must use 1 to 120 FRED identifier characters"
    series.InvalidObservationStart ->
      "fred_series observationStart must be canonical YYYY-MM-DD"
    series.InvalidObservationEnd ->
      "fred_series observationEnd must be canonical YYYY-MM-DD"
    series.InvalidAsOfDate ->
      "fred_series asOfDate must be canonical YYYY-MM-DD"
    series.InvalidObservationRange ->
      "fred_series observationStart must be on or before observationEnd"
    series.InvalidMaximumObservations ->
      "fred_series maximumObservations must be between 1 and 1000"
  }
}
