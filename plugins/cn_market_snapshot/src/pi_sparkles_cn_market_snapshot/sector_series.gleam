import finance_calendar/date
import finance_core/decimal
import finance_core/time
import finance_eastmoney/history
import finance_eastmoney/query
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import gleam/int
import gleam/json
import gleam/list
import gleam/order.{Eq, Gt, Lt}
import gleam/result

pub type AcquiredSeries {
  AcquiredSeries(
    index: query.CnSectorIndex,
    history: history.History,
    source_reference: String,
    response_bytes: Int,
    response_sha256: Sha256,
  )
}

pub opaque type Output {
  Output(summary: String, content: String, details: json.Json)
}

pub type Error {
  InvalidRetrievalTime
  InvalidSeriesCount(expected: Int, received: Int)
  InvalidSeriesIdentity(expected: String, received: String)
  InvalidResponseBytes(code: String, received: Int)
  InsufficientBars(code: String, received: Int)
  InvalidClose(code: String, raw: String)
  InconsistentObservationDates(code: String)
  InvalidRequestedWindow
  InvalidObservedWindow(code: String)
  ComparisonReceiptFailed
}

type SeriesRow {
  SeriesRow(
    index: query.CnSectorIndex,
    provider_name: String,
    window_start: history.Bar,
    five_sessions_ago: history.Bar,
    previous_session: history.Bar,
    latest: history.Bar,
    observations: Int,
    source_reference: String,
    response_bytes: Int,
    response_sha256: Sha256,
  )
}

const required_observations = 6

pub fn assemble(
  series: List(AcquiredSeries),
  requested_start: time.Date,
  requested_end: time.Date,
  retrieved_at: Int,
  manifest_sha256: Sha256,
) -> Result(Output, Error) {
  use _ <- result.try(case retrieved_at > 0 {
    True -> Ok(Nil)
    False -> Error(InvalidRetrievalTime)
  })
  use _ <- result.try(case date.compare(requested_start, requested_end) {
    Gt -> Error(InvalidRequestedWindow)
    _ -> Ok(Nil)
  })
  let expected = query.cn_sector_indices()
  use _ <- result.try(case list.length(series) == list.length(expected) {
    True -> Ok(Nil)
    False ->
      Error(InvalidSeriesCount(list.length(expected), list.length(series)))
  })
  use rows <- result.try(
    build_rows(series, expected, requested_start, requested_end, []),
  )
  use first <- result.try(first_row(rows))
  use _ <- result.try(validate_common_dates(rows, first))
  let comparison_input =
    comparison_input_json(rows, requested_start, requested_end, retrieved_at)
  let comparison_text = json.to_string(comparison_input)
  use comparison_digest <- result.try(
    hash.text(comparison_text)
    |> result.map_error(fn(_) { ComparisonReceiptFailed }),
  )
  let comparison_sha256 = identity.sha256_value(comparison_digest)
  let summary =
    "CN track | acquired "
    <> int.to_string(list.length(rows))
    <> " receipt-bound CSI 800 sector series | observed "
    <> date_text(history.date(first.window_start))
    <> " through "
    <> date_text(history.date(first.latest))
    <> " | calculation and interpretation not performed"
  let content =
    summary
    <> "\nCOMPARISON_INPUT "
    <> comparison_text
    <> "\nEXPECTED_INPUT_SHA256 "
    <> comparison_sha256
    <> "\nHandoff: pass comparisonInput and expectedInputSha256 unchanged to compare_series_returns. This acquisition result contains no calculated return, ranking, fund-flow claim, causal rotation claim, or recommendation."
  Ok(Output(
    summary,
    content,
    json.object([
      #("schema", json.string("pi-sparkles/cn-sector-series-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("acquire_cn_sector_series")),
      #("track", json.string("cn")),
      #("provider", json.string("eastmoney")),
      #("priceAuthority", json.string("eastmoney_vendor_observation")),
      #("classificationAuthority", json.string("CSI")),
      #("profileId", json.string(query.cn_sector_profile_id())),
      #("profileSource", json.string(query.cn_sector_profile_source())),
      #("profileUniverse", json.string("CSI_800_not_all_A_shares")),
      #("profileSectorCount", json.int(list.length(rows))),
      #("legacyCombinedFinancialRealEstateIndexIncluded", json.bool(False)),
      #("requestedStartDate", json.string(date_text(requested_start))),
      #("requestedEndDate", json.string(date_text(requested_end))),
      #(
        "firstObservedDate",
        json.string(date_text(history.date(first.window_start))),
      ),
      #(
        "latestObservedDate",
        json.string(date_text(history.date(first.latest))),
      ),
      #("retrievedAtUnixMilliseconds", json.int(retrieved_at)),
      #("frequency", json.string("daily")),
      #("adjustment", json.string("raw_unadjusted_fqt_0")),
      #("comparisonInput", comparison_input),
      #("expectedInputSha256", json.string(comparison_sha256)),
      #(
        "acquisitionReceipt",
        json.object([
          #(
            "canonicalSha256",
            json.string(identity.sha256_value(manifest_sha256)),
          ),
          #("scope", json.string("ordered_exact_response_sha256_manifest_v1")),
          #("providerAuthenticated", json.bool(False)),
          #("providerRequestCount", json.int(list.length(rows))),
        ]),
      ),
      #("batchKind", json.string("homogeneous_daily_history_transport")),
      #("outputOrder", json.string("pinned_CSI_profile_order")),
      #("perItemFailurePolicy", json.string("fail_closed_without_omission")),
      #("calculationPerformed", json.bool(False)),
      #("rankingPerformed", json.bool(False)),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
      #(
        "trackApplicabilityReview",
        json.object([
          #("cnAcquisition", json.string("supported_by_this_exact_adapter")),
          #(
            "hkAcquisition",
            json.string("unsupported:no_reviewed_track_owned_sector_profile"),
          ),
          #(
            "usAcquisition",
            json.string("unsupported:no_reviewed_track_owned_sector_profile"),
          ),
          #(
            "comparisonCalculation",
            json.string("shared_contract_supports_cn_hk_us"),
          ),
        ]),
      ),
      #(
        "limitations",
        json.array(
          [
            "vendor_origin_not_index_publisher_evidence",
            "pinned_CSI_800_profile_not_all_A_share_sectors",
            "no_constituent_breadth",
            "no_fund_flow_or_causal_rotation_evidence",
            "no_theme_or_AI_chain_mapping",
            "provider_timestamp_and_latency_unknown",
            "service_level_licence_and_redistribution_unknown",
            "no_fallback",
          ],
          json.string,
        ),
      ),
    ]),
  ))
}

pub fn summary(value: Output) -> String {
  value.summary
}

pub fn content(value: Output) -> String {
  value.content
}

pub fn details(value: Output) -> json.Json {
  value.details
}

pub fn error_message(error: Error) -> String {
  case error {
    InvalidRetrievalTime -> "retrieval time was invalid"
    InvalidSeriesCount(expected, received) ->
      "sector profile expected "
      <> int.to_string(expected)
      <> " series but received "
      <> int.to_string(received)
    InvalidSeriesIdentity(expected, received) ->
      "sector series identity mismatch: expected "
      <> expected
      <> ", received "
      <> received
    InvalidResponseBytes(code, received) ->
      "sector series "
      <> code
      <> " returned invalid response bytes "
      <> int.to_string(received)
    InsufficientBars(code, received) ->
      "sector series "
      <> code
      <> " requires at least "
      <> int.to_string(required_observations)
      <> " observations, received "
      <> int.to_string(received)
    InvalidClose(code, raw) ->
      "sector series " <> code <> " returned invalid close " <> raw
    InconsistentObservationDates(code) ->
      "sector series " <> code <> " did not share the exact handoff dates"
    InvalidRequestedWindow -> "requested sector date window was invalid"
    InvalidObservedWindow(code) ->
      "sector series " <> code <> " fell outside the requested date window"
    ComparisonReceiptFailed ->
      "canonical sector comparison input could not be hashed"
  }
}

fn build_rows(
  acquired: List(AcquiredSeries),
  expected: List(query.CnSectorIndex),
  requested_start: time.Date,
  requested_end: time.Date,
  rows: List(SeriesRow),
) -> Result(List(SeriesRow), Error) {
  case acquired, expected {
    [], [] -> Ok(list.reverse(rows))
    [item, ..rest], [spec, ..expected_rest] -> {
      use row <- result.try(build_row(
        item,
        spec,
        requested_start,
        requested_end,
      ))
      build_rows(rest, expected_rest, requested_start, requested_end, [
        row,
        ..rows
      ])
    }
    _, _ ->
      Error(InvalidSeriesCount(list.length(expected), list.length(acquired)))
  }
}

fn build_row(
  item: AcquiredSeries,
  expected: query.CnSectorIndex,
  requested_start: time.Date,
  requested_end: time.Date,
) -> Result(SeriesRow, Error) {
  let received = history.code(item.history)
  let expected_code = query.cn_sector_code(expected)
  use _ <- result.try(
    case
      query.cn_sector_code(item.index) == expected_code
      && received == expected_code
    {
      True -> Ok(Nil)
      False -> Error(InvalidSeriesIdentity(expected_code, received))
    },
  )
  use _ <- result.try(
    case item.response_bytes > 0 && item.response_bytes <= 2_000_000 {
      True -> Ok(Nil)
      False -> Error(InvalidResponseBytes(expected_code, item.response_bytes))
    },
  )
  let bars = history.bars(item.history)
  let count = list.length(bars)
  use _ <- result.try(case count >= required_observations {
    True -> Ok(Nil)
    False -> Error(InsufficientBars(expected_code, count))
  })
  use first <- result.try(at(bars, 0, expected_code))
  use five_sessions_ago <- result.try(at(bars, count - 6, expected_code))
  use previous <- result.try(at(bars, count - 2, expected_code))
  use latest <- result.try(at(bars, count - 1, expected_code))
  use _ <- result.try(validate_close(expected_code, history.close(first)))
  use _ <- result.try(validate_close(
    expected_code,
    history.close(five_sessions_ago),
  ))
  use _ <- result.try(validate_close(expected_code, history.close(previous)))
  use _ <- result.try(validate_close(expected_code, history.close(latest)))
  use _ <- result.try(
    case
      date.compare(history.date(first), requested_start) != Lt
      && date.compare(history.date(latest), requested_end) != Gt
    {
      True -> Ok(Nil)
      False -> Error(InvalidObservedWindow(expected_code))
    },
  )
  Ok(SeriesRow(
    expected,
    history.name(item.history),
    first,
    five_sessions_ago,
    previous,
    latest,
    count,
    item.source_reference,
    item.response_bytes,
    item.response_sha256,
  ))
}

fn validate_close(code: String, raw: String) -> Result(Nil, Error) {
  use value <- result.try(
    decimal.parse(raw)
    |> result.map_error(fn(_) { InvalidClose(code, raw) }),
  )
  case decimal.compare(value, decimal.zero()) {
    Gt -> Ok(Nil)
    _ -> Error(InvalidClose(code, raw))
  }
}

fn validate_common_dates(
  rows: List(SeriesRow),
  expected: SeriesRow,
) -> Result(Nil, Error) {
  case rows {
    [] -> Ok(Nil)
    [row, ..rest] ->
      case
        date.compare(
          history.date(row.window_start),
          history.date(expected.window_start),
        ),
        date.compare(
          history.date(row.five_sessions_ago),
          history.date(expected.five_sessions_ago),
        ),
        date.compare(
          history.date(row.previous_session),
          history.date(expected.previous_session),
        ),
        date.compare(history.date(row.latest), history.date(expected.latest))
      {
        Eq, Eq, Eq, Eq -> validate_common_dates(rest, expected)
        _, _, _, _ ->
          Error(InconsistentObservationDates(query.cn_sector_code(row.index)))
      }
  }
}

fn comparison_input_json(
  rows: List(SeriesRow),
  requested_start: time.Date,
  requested_end: time.Date,
  retrieved_at: Int,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/series-return-comparison-input")),
    #("schemaVersion", json.int(1)),
    #("track", json.string("cn")),
    #("sourceProfile", json.string(query.cn_sector_profile_id())),
    #("requestedStartDate", json.string(date_text(requested_start))),
    #("requestedEndDate", json.string(date_text(requested_end))),
    #("series", json.array(rows, fn(row) { series_json(row, retrieved_at) })),
  ])
}

fn series_json(row: SeriesRow, retrieved_at: Int) -> json.Json {
  json.object([
    #("seriesId", json.string(query.cn_sector_code(row.index))),
    #("label", json.string(query.cn_sector_label(row.index))),
    #("unit", json.string("index_points")),
    #("authorityLabel", json.string(query.cn_sector_official_name(row.index))),
    #("providerName", json.string(row.provider_name)),
    #(
      "source",
      json.object([
        #("provider", json.string("eastmoney")),
        #("sourceReference", json.string(row.source_reference)),
        #(
          "acquisitionReceipt",
          json.string(identity.sha256_value(row.response_sha256)),
        ),
        #("retrievalTimeUnixMilliseconds", json.int(retrieved_at)),
        #("responseBytes", json.int(row.response_bytes)),
      ]),
    ),
    #(
      "observations",
      json.array(
        [
          #("window_start", row.window_start),
          #("five_sessions_ago", row.five_sessions_ago),
          #("previous_session", row.previous_session),
          #("latest", row.latest),
        ],
        fn(item) {
          json.object([
            #("role", json.string(item.0)),
            #("date", json.string(date_text(history.date(item.1)))),
            #("value", json.string(history.close(item.1))),
          ])
        },
      ),
    ),
    #("availableObservationCount", json.int(row.observations)),
  ])
}

fn first_row(rows: List(SeriesRow)) -> Result(SeriesRow, Error) {
  case rows {
    [first, ..] -> Ok(first)
    [] -> Error(InvalidSeriesCount(list.length(query.cn_sector_indices()), 0))
  }
}

fn at(
  values: List(history.Bar),
  index: Int,
  code: String,
) -> Result(history.Bar, Error) {
  case list.drop(values, index) {
    [value, ..] -> Ok(value)
    [] -> Error(InsufficientBars(code, list.length(values)))
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
