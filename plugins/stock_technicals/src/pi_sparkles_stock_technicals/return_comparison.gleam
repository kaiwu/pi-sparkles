import finance_core/decimal
import finance_core/time
import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode as decoder
import gleam/int
import gleam/json
import gleam/list
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string

pub type SourceInput {
  SourceInput(
    provider: String,
    source_reference: String,
    acquisition_receipt: String,
    retrieval_time_unix_ms: Int,
    response_bytes: Int,
  )
}

pub type ObservationInput {
  ObservationInput(role: String, date: String, value: String)
}

pub type SeriesInput {
  SeriesInput(
    series_id: String,
    label: String,
    unit: String,
    authority_label: String,
    provider_name: String,
    source: SourceInput,
    observations: List(ObservationInput),
    available_observation_count: Int,
  )
}

pub type Input {
  Input(
    expected_input_sha256: String,
    schema: String,
    schema_version: Int,
    track: String,
    source_profile: String,
    requested_start_date: String,
    requested_end_date: String,
    series: List(SeriesInput),
  )
}

pub opaque type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  InvalidField(field: String, reason: String)
  InputReceiptMismatch(expected: String, actual: String)
  HashFailed
}

type Row {
  Row(
    series: SeriesInput,
    window_start: ObservationInput,
    five_sessions_ago: ObservationInput,
    previous_session: ObservationInput,
    latest: ObservationInput,
    latest_session_return: decimal.Decimal,
    five_session_return: decimal.Decimal,
    window_return: decimal.Decimal,
  )
}

pub fn decoder() -> decoder.Decoder(Input) {
  use expected <- decoder.field("expectedInputSha256", decoder.string)
  use comparison <- decoder.field("comparisonInput", comparison_decoder())
  let #(schema, version, track, profile, start, end, series) = comparison
  decoder.success(Input(
    expected,
    schema,
    version,
    track,
    profile,
    start,
    end,
    series,
  ))
}

pub fn run(input: Input) -> Result(Output, Error) {
  use _ <- result.try(exact(
    "comparisonInput.schema",
    input.schema,
    "pi-sparkles/series-return-comparison-input",
  ))
  use _ <- result.try(case input.schema_version == 1 {
    True -> Ok(Nil)
    False -> Error(InvalidField("comparisonInput.schemaVersion", "expected 1"))
  })
  use _ <- result.try(case input.track {
    "cn" | "hk" | "us" -> Ok(Nil)
    _ -> Error(InvalidField("comparisonInput.track", "expected cn, hk, or us"))
  })
  use _ <- result.try(validate_date(
    "comparisonInput.requestedStartDate",
    input.requested_start_date,
  ))
  use _ <- result.try(validate_date(
    "comparisonInput.requestedEndDate",
    input.requested_end_date,
  ))
  use _ <- result.try(
    case string.compare(input.requested_start_date, input.requested_end_date) {
      Gt ->
        Error(InvalidField(
          "comparisonInput.requestedStartDate",
          "must not follow requestedEndDate",
        ))
      _ -> Ok(Nil)
    },
  )
  use expected <- result.try(
    identity.sha256(input.expected_input_sha256)
    |> result.map_error(fn(_) {
      InvalidField(
        "expectedInputSha256",
        "expected lowercase hexadecimal SHA-256",
      )
    }),
  )
  let canonical = canonical_input(input)
  use actual <- result.try(
    hash.text(json.to_string(canonical))
    |> result.map_error(fn(_) { HashFailed }),
  )
  use _ <- result.try(
    case identity.sha256_value(expected) == identity.sha256_value(actual) {
      True -> Ok(Nil)
      False ->
        Error(InputReceiptMismatch(
          identity.sha256_value(expected),
          identity.sha256_value(actual),
        ))
    },
  )
  use _ <- result.try(case list.length(input.series) >= 2 {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "comparisonInput.series",
        "requires at least two series",
      ))
  })
  use _ <- result.try(validate_unique_ids(input.series))
  use rows <- result.try(build_rows(input, input.series, []))
  use first <- result.try(first_row(rows))
  use _ <- result.try(validate_common_dates(rows, first))
  let latest_order = order_rows(rows, fn(row) { row.latest_session_return })
  let five_session_order = order_rows(rows, fn(row) { row.five_session_return })
  let window_order = order_rows(rows, fn(row) { row.window_return })
  let calculation_receipt_text =
    json.to_string(canonical)
    <> "\nformula=(end-start)/start*100"
    <> "\nrounding=half_even_2"
  use calculation_receipt <- result.try(
    hash.text(calculation_receipt_text)
    |> result.map_error(fn(_) { HashFailed }),
  )
  let summary =
    input.track
    <> " track | calculated exact relative returns for "
    <> int.to_string(list.length(rows))
    <> " caller-selected series | interpretation not performed"
  let details =
    json.object([
      #("schema", json.string("pi-sparkles/series-return-comparison-result")),
      #("schemaVersion", json.int(1)),
      #("track", json.string(input.track)),
      #("sourceProfile", json.string(input.source_profile)),
      #("requestedStartDate", json.string(input.requested_start_date)),
      #("requestedEndDate", json.string(input.requested_end_date)),
      #(
        "inputReceipt",
        json.object([
          #("expectedSha256", json.string(identity.sha256_value(expected))),
          #("actualSha256", json.string(identity.sha256_value(actual))),
          #("matched", json.bool(True)),
        ]),
      ),
      #(
        "calculationReceiptSha256",
        json.string(identity.sha256_value(calculation_receipt)),
      ),
      #(
        "returnMethod",
        json.object([
          #("formula", json.string("(end_value / start_value - 1) * 100")),
          #("rounding", json.string("half_even_2_decimal_places")),
          #("latestSession", json.string("previous_session_to_latest")),
          #("fiveSession", json.string("five_sessions_ago_to_latest")),
          #("window", json.string("window_start_to_latest")),
        ]),
      ),
      #("series", json.array(rows, row_json)),
      #("latestSessionOrder", json.array(latest_order, rank_json)),
      #("fiveSessionOrder", json.array(five_session_order, rank_json)),
      #("windowOrder", json.array(window_order, rank_json)),
      #("networkRequests", json.int(0)),
      #("providerOrUniverseSelectedByCalculator", json.bool(False)),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
      #(
        "limitations",
        json.array(
          [
            "orders_only_the_explicit_receipt_bound_input_series",
            "relative_price_math_not_fund_flow_or_causal_evidence",
            "no_identity_calendar_or_market_completeness_inference",
            "no_forecast_recommendation_or_trade_action",
          ],
          json.string,
        ),
      ),
    ])
  Ok(Output(summary, details))
}

pub fn model_content(output: Output) -> String {
  output.summary <> "\nMODEL_DATA " <> json.to_string(output.details)
}

pub fn details(output: Output) -> json.Json {
  output.details
}

pub fn error_message(error: Error) -> String {
  case error {
    InvalidField(field, reason) ->
      "Invalid explicit return-comparison field " <> field <> ": " <> reason
    InputReceiptMismatch(expected, actual) ->
      "Return-comparison input receipt mismatch: expected "
      <> expected
      <> ", calculated "
      <> actual
    HashFailed -> "Return-comparison receipt hashing failed"
  }
}

fn comparison_decoder() {
  use schema <- decoder.field("schema", decoder.string)
  use version <- decoder.field("schemaVersion", decoder.int)
  use track <- decoder.field("track", decoder.string)
  use profile <- decoder.field("sourceProfile", decoder.string)
  use start <- decoder.field("requestedStartDate", decoder.string)
  use end <- decoder.field("requestedEndDate", decoder.string)
  use series <- decoder.field("series", decoder.list(of: series_decoder()))
  decoder.success(#(schema, version, track, profile, start, end, series))
}

fn series_decoder() -> decoder.Decoder(SeriesInput) {
  use series_id <- decoder.field("seriesId", decoder.string)
  use label <- decoder.field("label", decoder.string)
  use unit <- decoder.field("unit", decoder.string)
  use authority_label <- decoder.field("authorityLabel", decoder.string)
  use provider_name <- decoder.field("providerName", decoder.string)
  use source <- decoder.field("source", source_decoder())
  use observations <- decoder.field(
    "observations",
    decoder.list(of: observation_decoder()),
  )
  use count <- decoder.field("availableObservationCount", decoder.int)
  decoder.success(SeriesInput(
    series_id,
    label,
    unit,
    authority_label,
    provider_name,
    source,
    observations,
    count,
  ))
}

fn source_decoder() -> decoder.Decoder(SourceInput) {
  use provider <- decoder.field("provider", decoder.string)
  use reference <- decoder.field("sourceReference", decoder.string)
  use receipt <- decoder.field("acquisitionReceipt", decoder.string)
  use retrieved <- decoder.field("retrievalTimeUnixMilliseconds", decoder.int)
  use bytes <- decoder.field("responseBytes", decoder.int)
  decoder.success(SourceInput(provider, reference, receipt, retrieved, bytes))
}

fn observation_decoder() -> decoder.Decoder(ObservationInput) {
  use role <- decoder.field("role", decoder.string)
  use date <- decoder.field("date", decoder.string)
  use value <- decoder.field("value", decoder.string)
  decoder.success(ObservationInput(role, date, value))
}

fn canonical_input(input: Input) -> json.Json {
  json.object([
    #("schema", json.string(input.schema)),
    #("schemaVersion", json.int(input.schema_version)),
    #("track", json.string(input.track)),
    #("sourceProfile", json.string(input.source_profile)),
    #("requestedStartDate", json.string(input.requested_start_date)),
    #("requestedEndDate", json.string(input.requested_end_date)),
    #("series", json.array(input.series, series_input_json)),
  ])
}

fn series_input_json(series: SeriesInput) -> json.Json {
  json.object([
    #("seriesId", json.string(series.series_id)),
    #("label", json.string(series.label)),
    #("unit", json.string(series.unit)),
    #("authorityLabel", json.string(series.authority_label)),
    #("providerName", json.string(series.provider_name)),
    #(
      "source",
      json.object([
        #("provider", json.string(series.source.provider)),
        #("sourceReference", json.string(series.source.source_reference)),
        #("acquisitionReceipt", json.string(series.source.acquisition_receipt)),
        #(
          "retrievalTimeUnixMilliseconds",
          json.int(series.source.retrieval_time_unix_ms),
        ),
        #("responseBytes", json.int(series.source.response_bytes)),
      ]),
    ),
    #("observations", json.array(series.observations, observation_json)),
    #("availableObservationCount", json.int(series.available_observation_count)),
  ])
}

fn observation_json(observation: ObservationInput) -> json.Json {
  json.object([
    #("role", json.string(observation.role)),
    #("date", json.string(observation.date)),
    #("value", json.string(observation.value)),
  ])
}

fn build_rows(
  input: Input,
  series: List(SeriesInput),
  rows: List(Row),
) -> Result(List(Row), Error) {
  case series {
    [] -> Ok(list.reverse(rows))
    [item, ..rest] -> {
      use row <- result.try(build_row(input, item))
      build_rows(input, rest, [row, ..rows])
    }
  }
}

fn build_row(input: Input, series: SeriesInput) -> Result(Row, Error) {
  let field = "comparisonInput.series[" <> series.series_id <> "]"
  use _ <- result.try(nonempty(field <> ".seriesId", series.series_id))
  use _ <- result.try(nonempty(field <> ".label", series.label))
  use _ <- result.try(nonempty(field <> ".unit", series.unit))
  use _ <- result.try(nonempty(
    field <> ".authorityLabel",
    series.authority_label,
  ))
  use _ <- result.try(nonempty(field <> ".providerName", series.provider_name))
  use _ <- result.try(nonempty(
    field <> ".source.provider",
    series.source.provider,
  ))
  use _ <- result.try(nonempty(
    field <> ".source.sourceReference",
    series.source.source_reference,
  ))
  use _ <- result.try(
    identity.sha256(series.source.acquisition_receipt)
    |> result.map(fn(_) { Nil })
    |> result.map_error(fn(_) {
      InvalidField(field <> ".source.acquisitionReceipt", "invalid SHA-256")
    }),
  )
  use _ <- result.try(
    case
      series.source.retrieval_time_unix_ms > 0
      && series.source.response_bytes > 0
      && series.available_observation_count >= 6
    {
      True -> Ok(Nil)
      False ->
        Error(InvalidField(
          field <> ".source",
          "requires positive retrieval time/bytes and at least six available observations",
        ))
    },
  )
  use window_start <- result.try(exact_role(series, "window_start"))
  use five_sessions_ago <- result.try(exact_role(series, "five_sessions_ago"))
  use previous <- result.try(exact_role(series, "previous_session"))
  use latest <- result.try(exact_role(series, "latest"))
  use window_start_value <- result.try(observation_value(field, window_start))
  use five_sessions_value <- result.try(observation_value(
    field,
    five_sessions_ago,
  ))
  use previous_value <- result.try(observation_value(field, previous))
  use latest_value <- result.try(observation_value(field, latest))
  use _ <- result.try(
    case
      string.compare(window_start.date, input.requested_start_date) != Lt
      && string.compare(latest.date, input.requested_end_date) != Gt
      && string.compare(window_start.date, five_sessions_ago.date) != Gt
      && string.compare(five_sessions_ago.date, previous.date) == Lt
      && string.compare(previous.date, latest.date) == Lt
    {
      True -> Ok(Nil)
      False ->
        Error(InvalidField(
          field <> ".observations",
          "roles must be ordered inside the requested window",
        ))
    },
  )
  use latest_session_return <- result.try(return_percent(
    field,
    previous_value,
    latest_value,
  ))
  use five_session_return <- result.try(return_percent(
    field,
    five_sessions_value,
    latest_value,
  ))
  use window_return <- result.try(return_percent(
    field,
    window_start_value,
    latest_value,
  ))
  Ok(Row(
    series,
    window_start,
    five_sessions_ago,
    previous,
    latest,
    latest_session_return,
    five_session_return,
    window_return,
  ))
}

fn exact_role(
  series: SeriesInput,
  role: String,
) -> Result(ObservationInput, Error) {
  let matches =
    list.filter(series.observations, fn(value) { value.role == role })
  case matches {
    [value] -> Ok(value)
    _ ->
      Error(InvalidField(
        "comparisonInput.series[" <> series.series_id <> "].observations",
        "requires exactly one " <> role <> " observation",
      ))
  }
}

fn observation_value(
  field: String,
  observation: ObservationInput,
) -> Result(decimal.Decimal, Error) {
  use _ <- result.try(validate_date(
    field <> "." <> observation.role,
    observation.date,
  ))
  use value <- result.try(
    decimal.parse(observation.value)
    |> result.map_error(fn(_) {
      InvalidField(
        field <> "." <> observation.role <> ".value",
        "invalid decimal",
      )
    }),
  )
  case decimal.compare(value, decimal.zero()) {
    Gt -> Ok(value)
    _ ->
      Error(InvalidField(
        field <> "." <> observation.role <> ".value",
        "must be positive",
      ))
  }
}

fn return_percent(
  field: String,
  start: decimal.Decimal,
  end: decimal.Decimal,
) -> Result(decimal.Decimal, Error) {
  let assert Ok(hundred) = decimal.parse("100")
  use ratio <- result.try(
    decimal.divide(
      decimal.subtract(end, start),
      by: start,
      scale: 8,
      rounding: decimal.HalfEven,
    )
    |> result.map_error(fn(_) { InvalidField(field, "return division failed") }),
  )
  decimal.multiply(ratio, hundred)
  |> decimal.quantize(scale: 2, rounding: decimal.HalfEven)
  |> result.map_error(fn(_) { InvalidField(field, "return rounding failed") })
}

fn validate_unique_ids(series: List(SeriesInput)) -> Result(Nil, Error) {
  let ids = list.map(series, fn(value) { value.series_id })
  case list.length(ids) == list.length(list.unique(ids)) {
    True -> Ok(Nil)
    False -> Error(InvalidField("comparisonInput.series", "duplicate seriesId"))
  }
}

fn validate_common_dates(rows: List(Row), first: Row) -> Result(Nil, Error) {
  case rows {
    [] -> Ok(Nil)
    [row, ..rest] ->
      case
        row.window_start.date == first.window_start.date,
        row.five_sessions_ago.date == first.five_sessions_ago.date,
        row.previous_session.date == first.previous_session.date,
        row.latest.date == first.latest.date
      {
        True, True, True, True -> validate_common_dates(rest, first)
        _, _, _, _ ->
          Error(InvalidField(
            "comparisonInput.series["
              <> row.series.series_id
              <> "].observations",
            "comparison roles must share exact dates across every series",
          ))
      }
  }
}

fn first_row(rows: List(Row)) -> Result(Row, Error) {
  case rows {
    [first, ..] -> Ok(first)
    [] -> Error(InvalidField("comparisonInput.series", "requires rows"))
  }
}

fn order_rows(
  rows: List(Row),
  selector: fn(Row) -> decimal.Decimal,
) -> List(Row) {
  list.sort(rows, fn(left, right) {
    case decimal.compare(selector(right), selector(left)) {
      Eq -> string.compare(left.series.series_id, right.series.series_id)
      order -> order
    }
  })
}

fn row_json(row: Row) -> json.Json {
  json.object([
    #("seriesId", json.string(row.series.series_id)),
    #("label", json.string(row.series.label)),
    #("unit", json.string(row.series.unit)),
    #("authorityLabel", json.string(row.series.authority_label)),
    #("providerName", json.string(row.series.provider_name)),
    #("windowStartDate", json.string(row.window_start.date)),
    #("fiveSessionsAgoDate", json.string(row.five_sessions_ago.date)),
    #("previousSessionDate", json.string(row.previous_session.date)),
    #("latestDate", json.string(row.latest.date)),
    #(
      "latestSessionReturnPercent",
      json.string(decimal.to_string(row.latest_session_return)),
    ),
    #(
      "fiveSessionReturnPercent",
      json.string(decimal.to_string(row.five_session_return)),
    ),
    #("windowReturnPercent", json.string(decimal.to_string(row.window_return))),
    #("sourceReceipt", json.string(row.series.source.acquisition_receipt)),
  ])
}

fn rank_json(row: Row) -> json.Json {
  json.object([
    #("seriesId", json.string(row.series.series_id)),
    #("label", json.string(row.series.label)),
  ])
}

fn exact(field: String, value: String, expected: String) -> Result(Nil, Error) {
  case value == expected {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "expected " <> expected))
  }
}

fn nonempty(field: String, value: String) -> Result(Nil, Error) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "must be non-empty and trimmed"))
  }
}

fn validate_date(field: String, value: String) -> Result(Nil, Error) {
  case string.split(value, "-") {
    [year_text, month_text, day_text] -> {
      use year <- result.try(
        int.parse(year_text)
        |> result.map_error(fn(_) { InvalidField(field, "invalid date") }),
      )
      use month <- result.try(
        int.parse(month_text)
        |> result.map_error(fn(_) { InvalidField(field, "invalid date") }),
      )
      use day <- result.try(
        int.parse(day_text)
        |> result.map_error(fn(_) { InvalidField(field, "invalid date") }),
      )
      use date <- result.try(
        time.date(year, month, day)
        |> result.map_error(fn(_) { InvalidField(field, "invalid date") }),
      )
      case date_text(date) == value {
        True -> Ok(Nil)
        False -> Error(InvalidField(field, "expected YYYY-MM-DD"))
      }
    }
    _ -> Error(InvalidField(field, "expected YYYY-MM-DD"))
  }
}

fn date_text(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
