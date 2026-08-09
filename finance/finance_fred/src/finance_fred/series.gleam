import finance_calendar/date
import finance_core/decimal
import finance_core/time.{type Date}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string

pub type Query {
  Query(
    series_id: String,
    observation_start: Date,
    observation_end: Date,
    as_of_date: Date,
    maximum_observations: Int,
  )
}

pub type Metadata {
  Metadata(
    id: String,
    realtime_start: String,
    realtime_end: String,
    title: String,
    observation_start: String,
    observation_end: String,
    frequency: String,
    frequency_short: String,
    units: String,
    units_short: String,
    seasonal_adjustment: String,
    seasonal_adjustment_short: String,
    last_updated: String,
    popularity: Int,
    notes: Option(String),
  )
}

pub type Point {
  Point(
    realtime_start: String,
    realtime_end: String,
    date: Date,
    date_text: String,
    raw_value: String,
  )
}

pub type ObservationRange {
  ObservationRange(
    realtime_start: String,
    realtime_end: String,
    observation_start: String,
    observation_end: String,
    units: String,
    output_type: Int,
    file_type: String,
    order_by: String,
    sort_order: String,
    count: Int,
    offset: Int,
    limit: Int,
    observations: List(Point),
  )
}

pub type QueryError {
  InvalidSeriesId
  InvalidObservationStart
  InvalidObservationEnd
  InvalidAsOfDate
  InvalidObservationRange
  InvalidMaximumObservations
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  InvalidEnvelope
  SeriesMismatch(expected: String, received: String)
  RealtimeMismatch
  RangeMismatch
  UnexpectedTransformation
  Truncated(maximum: Int, available: Int)
  InvalidObservation
  OutOfOrder
}

pub fn query(
  series_id: String,
  observation_start: String,
  observation_end: String,
  as_of_date: String,
  maximum_observations: Int,
) -> Result(Query, QueryError) {
  use start <- result.try(
    parse_date(observation_start)
    |> result.map_error(fn(_) { InvalidObservationStart }),
  )
  use end <- result.try(
    parse_date(observation_end)
    |> result.map_error(fn(_) { InvalidObservationEnd }),
  )
  use as_of <- result.try(
    parse_date(as_of_date) |> result.map_error(fn(_) { InvalidAsOfDate }),
  )
  case
    valid_series_id(series_id),
    date.compare(start, end),
    maximum_observations >= 1 && maximum_observations <= 1000
  {
    False, _, _ -> Error(InvalidSeriesId)
    _, Gt, _ -> Error(InvalidObservationRange)
    _, _, False -> Error(InvalidMaximumObservations)
    True, _, True ->
      Ok(Query(series_id, start, end, as_of, maximum_observations))
  }
}

pub fn decode_metadata(
  body: String,
  query: Query,
) -> Result(Metadata, DecodeError) {
  use envelope <- result.try(
    json.parse(body, metadata_envelope_decoder())
    |> result.map_error(InvalidJson),
  )
  let #(realtime_start, realtime_end, values) = envelope
  let expected_as_of = date_text(query.as_of_date)
  case realtime_start, realtime_end, values {
    value_start, value_end, [metadata]
      if value_start == expected_as_of && value_end == expected_as_of
    -> {
      use Nil <- result.try(validate_metadata(metadata, query))
      Ok(metadata)
    }
    _, _, [_] -> Error(RealtimeMismatch)
    _, _, _ -> Error(InvalidEnvelope)
  }
}

pub fn decode_observations(
  body: String,
  query: Query,
) -> Result(ObservationRange, DecodeError) {
  use range <- result.try(
    json.parse(body, observation_range_decoder())
    |> result.map_error(InvalidJson),
  )
  let expected_as_of = date_text(query.as_of_date)
  use Nil <- result.try(
    case
      range.realtime_start == expected_as_of
      && range.realtime_end == expected_as_of
    {
      True -> Ok(Nil)
      False -> Error(RealtimeMismatch)
    },
  )
  use Nil <- result.try(
    case
      range.observation_start == date_text(query.observation_start)
      && range.observation_end == date_text(query.observation_end)
    {
      True -> Ok(Nil)
      False -> Error(RangeMismatch)
    },
  )
  use Nil <- result.try(
    case
      range.units == "lin",
      range.output_type == 1,
      range.file_type == "json",
      range.order_by == "observation_date",
      range.sort_order == "asc",
      range.offset == 0,
      range.limit == query.maximum_observations
    {
      True, True, True, True, True, True, True -> Ok(Nil)
      _, _, _, _, _, _, _ -> Error(UnexpectedTransformation)
    },
  )
  use Nil <- result.try(case range.count > query.maximum_observations {
    True -> Error(Truncated(query.maximum_observations, range.count))
    False -> Ok(Nil)
  })
  use Nil <- result.try(case list.length(range.observations) == range.count {
    True -> Ok(Nil)
    False -> Error(InvalidEnvelope)
  })
  use Nil <- result.try(validate_points(
    range.observations,
    query,
    expected_as_of,
    None,
  ))
  Ok(range)
}

pub fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> pad(month) <> "-" <> pad(day)
}

fn metadata_envelope_decoder() -> decode.Decoder(
  #(String, String, List(Metadata)),
) {
  use realtime_start <- decode.field("realtime_start", decode.string)
  use realtime_end <- decode.field("realtime_end", decode.string)
  use values <- decode.field("seriess", decode.list(of: metadata_decoder()))
  decode.success(#(realtime_start, realtime_end, values))
}

fn metadata_decoder() -> decode.Decoder(Metadata) {
  use id <- decode.field("id", decode.string)
  use realtime_start <- decode.field("realtime_start", decode.string)
  use realtime_end <- decode.field("realtime_end", decode.string)
  use title <- decode.field("title", decode.string)
  use observation_start <- decode.field("observation_start", decode.string)
  use observation_end <- decode.field("observation_end", decode.string)
  use frequency <- decode.field("frequency", decode.string)
  use frequency_short <- decode.field("frequency_short", decode.string)
  use units <- decode.field("units", decode.string)
  use units_short <- decode.field("units_short", decode.string)
  use seasonal_adjustment <- decode.field("seasonal_adjustment", decode.string)
  use seasonal_adjustment_short <- decode.field(
    "seasonal_adjustment_short",
    decode.string,
  )
  use last_updated <- decode.field("last_updated", decode.string)
  use popularity <- decode.field("popularity", decode.int)
  use notes <- decode.optional_field(
    "notes",
    None,
    decode.optional(decode.string),
  )
  decode.success(Metadata(
    id,
    realtime_start,
    realtime_end,
    title,
    observation_start,
    observation_end,
    frequency,
    frequency_short,
    units,
    units_short,
    seasonal_adjustment,
    seasonal_adjustment_short,
    last_updated,
    popularity,
    notes,
  ))
}

fn observation_range_decoder() -> decode.Decoder(ObservationRange) {
  use realtime_start <- decode.field("realtime_start", decode.string)
  use realtime_end <- decode.field("realtime_end", decode.string)
  use observation_start <- decode.field("observation_start", decode.string)
  use observation_end <- decode.field("observation_end", decode.string)
  use units <- decode.field("units", decode.string)
  use output_type <- decode.field("output_type", decode.int)
  use file_type <- decode.field("file_type", decode.string)
  use order_by <- decode.field("order_by", decode.string)
  use sort_order <- decode.field("sort_order", decode.string)
  use count <- decode.field("count", decode.int)
  use offset <- decode.field("offset", decode.int)
  use limit <- decode.field("limit", decode.int)
  use observations <- decode.field(
    "observations",
    decode.list(of: point_decoder()),
  )
  decode.success(ObservationRange(
    realtime_start,
    realtime_end,
    observation_start,
    observation_end,
    units,
    output_type,
    file_type,
    order_by,
    sort_order,
    count,
    offset,
    limit,
    observations,
  ))
}

fn point_decoder() -> decode.Decoder(Point) {
  use realtime_start <- decode.field("realtime_start", decode.string)
  use realtime_end <- decode.field("realtime_end", decode.string)
  use raw_date <- decode.field("date", decode.string)
  use raw_value <- decode.field("value", decode.string)
  case parse_date(raw_date) {
    Ok(date) ->
      decode.success(Point(
        realtime_start,
        realtime_end,
        date,
        raw_date,
        raw_value,
      ))
    Error(_) -> {
      let assert Ok(fallback) = time.date(1970, 1, 1)
      decode.failure(
        Point(realtime_start, realtime_end, fallback, raw_date, raw_value),
        "canonical FRED observation date",
      )
    }
  }
}

fn validate_metadata(
  value: Metadata,
  query: Query,
) -> Result(Nil, DecodeError) {
  let expected_as_of = date_text(query.as_of_date)
  case value.id == query.series_id {
    False -> Error(SeriesMismatch(query.series_id, value.id))
    True ->
      case
        value.realtime_start == expected_as_of,
        value.realtime_end == expected_as_of,
        valid_text(value.title),
        valid_text(value.frequency),
        valid_text(value.frequency_short),
        valid_text(value.units),
        valid_text(value.units_short),
        valid_text(value.seasonal_adjustment),
        valid_text(value.seasonal_adjustment_short),
        valid_text(value.last_updated),
        value.popularity >= 0,
        parse_date(value.observation_start),
        parse_date(value.observation_end)
      {
        True,
          True,
          True,
          True,
          True,
          True,
          True,
          True,
          True,
          True,
          True,
          Ok(_),
          Ok(_)
        -> Ok(Nil)
        False, _, _, _, _, _, _, _, _, _, _, _, _
        | _, False, _, _, _, _, _, _, _, _, _, _, _
        -> Error(RealtimeMismatch)
        _, _, _, _, _, _, _, _, _, _, _, _, _ -> Error(InvalidEnvelope)
      }
  }
}

fn validate_points(
  points: List(Point),
  query: Query,
  expected_as_of: String,
  previous: Option(Date),
) -> Result(Nil, DecodeError) {
  case points {
    [] -> Ok(Nil)
    [point, ..rest] -> {
      use Nil <- result.try(
        case
          point.realtime_start == expected_as_of
          && point.realtime_end == expected_as_of
          && {
            point.raw_value == "."
            || decimal.parse(point.raw_value) |> result.is_ok
          }
        {
          True -> Ok(Nil)
          False -> Error(InvalidObservation)
        },
      )
      use Nil <- result.try(
        case
          date.compare(point.date, query.observation_start),
          date.compare(point.date, query.observation_end),
          previous
        {
          Lt, _, _ | _, Gt, _ -> Error(RangeMismatch)
          _, _, None -> Ok(Nil)
          _, _, Some(prior) ->
            case date.compare(prior, point.date) {
              Lt -> Ok(Nil)
              _ -> Error(OutOfOrder)
            }
        },
      )
      validate_points(rest, query, expected_as_of, Some(point.date))
    }
  }
}

fn parse_date(value: String) -> Result(Date, Nil) {
  case string.split(value, "-") {
    [year_text, month_text, day_text] ->
      case
        int.parse(year_text),
        int.parse(month_text),
        int.parse(day_text),
        string.length(year_text),
        string.length(month_text),
        string.length(day_text)
      {
        Ok(year), Ok(month), Ok(day), 4, 2, 2 ->
          case time.date(year, month, day) {
            Error(_) -> Error(Nil)
            Ok(parsed) ->
              case date_text(parsed) == value {
                True -> Ok(parsed)
                False -> Error(Nil)
              }
          }
        _, _, _, _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn valid_series_id(value: String) -> Bool {
  value != ""
  && string.length(value) <= 120
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-",
        character,
      )
    })
  }
}

fn valid_text(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn pad(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
