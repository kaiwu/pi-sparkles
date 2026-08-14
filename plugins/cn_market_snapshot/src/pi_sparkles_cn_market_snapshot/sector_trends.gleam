import finance_calendar/date
import finance_core/decimal
import finance_core/time
import finance_eastmoney/history
import finance_eastmoney/query
import finance_provenance/identity.{type Sha256}
import gleam/int
import gleam/json
import gleam/list
import gleam/order.{Eq, Gt}
import gleam/result
import gleam/string

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
  ZeroStartingClose(code: String)
  InconsistentObservedWindow(code: String)
  InvalidRequestedWindow
}

type Row {
  Row(
    index: query.CnSectorIndex,
    provider_name: String,
    first_date: time.Date,
    latest_date: time.Date,
    first_close: String,
    latest_close: String,
    latest_session_return: decimal.Decimal,
    five_session_return: decimal.Decimal,
    window_return: decimal.Decimal,
    bars: Int,
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
  use rows <- result.try(build_rows(series, expected, []))
  use first <- result.try(first_row(rows))
  use _ <- result.try(validate_common_window(
    rows,
    first.first_date,
    first.latest_date,
  ))
  let five_session_ranking = rank(rows, by: fn(row) { row.five_session_return })
  let latest_session_ranking =
    rank(rows, by: fn(row) { row.latest_session_return })
  let window_ranking = rank(rows, by: fn(row) { row.window_return })
  let summary =
    "CN track | Eastmoney price-only CSI 800 level-one sector comparison | "
    <> int.to_string(list.length(rows))
    <> " sectors | observed "
    <> date_text(first.first_date)
    <> " through "
    <> date_text(first.latest_date)
    <> " | no fund-flow or causal-rotation evidence"
  let content =
    summary
    <> "\nsectorCode,sectorLabel,officialName,providerName,latestSessionReturnPercent,fiveSessionReturnPercent,windowReturnPercent,firstObservedDate,latestObservedDate\n"
    <> {
      five_session_ranking
      |> list.map(row_content)
      |> string.join("\n")
    }
    <> "\nEvidence boundaries: these are mechanically calculated relative price returns for a pinned CSI 800 industry-index profile. They do not establish fund flow, constituent breadth, causal rotation, theme exposure, trend reversal, or all-A-share sector completeness."
  Ok(Output(
    summary,
    content,
    json.object([
      #("schema", json.string("pi-sparkles/cn-sector-trends-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("acquire_cn_sector_trends")),
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
      #("firstObservedDate", json.string(date_text(first.first_date))),
      #("latestObservedDate", json.string(date_text(first.latest_date))),
      #("retrievedAtUnixMilliseconds", json.int(retrieved_at)),
      #("frequency", json.string("daily")),
      #("adjustment", json.string("raw_unadjusted_fqt_0")),
      #(
        "returnMethod",
        json.object([
          #("formula", json.string("(end_close / start_close - 1) * 100")),
          #("rounding", json.string("half_even_2_decimal_places")),
          #("latestSessionIntervals", json.int(1)),
          #("fiveSessionIntervals", json.int(5)),
          #(
            "windowIntervals",
            json.string("first_to_last_observed_close_in_requested_window"),
          ),
        ]),
      ),
      #("sectors", json.array(rows, row_json)),
      #("latestSessionRanking", json.array(latest_session_ranking, rank_json)),
      #("fiveSessionRanking", json.array(five_session_ranking, rank_json)),
      #("windowRanking", json.array(window_ranking, rank_json)),
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
      #("fundFlow", unavailable("no_fund_flow_fields")),
      #("constituentBreadth", unavailable("no_constituent_membership_rows")),
      #("causalRotation", unavailable("relative_price_performance_only")),
      #("themeExposure", unavailable("industry_indices_are_not_theme_indices")),
      #("latency", json.string("unknown")),
      #("entitlement", json.string("public_web_local_analysis")),
      #("licence", json.string("unknown")),
      #("redistribution", json.string("unknown")),
      #(
        "limitations",
        json.array(
          [
            "vendor_origin_not_index_publisher_evidence",
            "pinned_CSI_800_profile_not_all_A_share_sectors",
            "no_constituent_breadth",
            "no_fund_flow_or_causal_rotation_evidence",
            "no_theme_or_AI_chain_mapping",
            "no_trend_reversal_confirmation",
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
    ZeroStartingClose(code) ->
      "sector series " <> code <> " returned a non-positive starting close"
    InconsistentObservedWindow(code) ->
      "sector series "
      <> code
      <> " did not share the exact observed date window"
    InvalidRequestedWindow -> "requested sector date window was invalid"
  }
}

fn build_rows(
  acquired: List(AcquiredSeries),
  expected: List(query.CnSectorIndex),
  rows: List(Row),
) -> Result(List(Row), Error) {
  case acquired, expected {
    [], [] -> Ok(list.reverse(rows))
    [item, ..rest], [spec, ..expected_rest] -> {
      use row <- result.try(build_row(item, spec))
      build_rows(rest, expected_rest, [row, ..rows])
    }
    _, _ ->
      Error(InvalidSeriesCount(list.length(expected), list.length(acquired)))
  }
}

fn build_row(
  item: AcquiredSeries,
  expected: query.CnSectorIndex,
) -> Result(Row, Error) {
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
  use previous <- result.try(at(bars, count - 2, expected_code))
  use five_sessions_ago <- result.try(at(bars, count - 6, expected_code))
  use latest <- result.try(at(bars, count - 1, expected_code))
  use latest_session_return <- result.try(return_percent(
    expected_code,
    history.close(previous),
    history.close(latest),
  ))
  use five_session_return <- result.try(return_percent(
    expected_code,
    history.close(five_sessions_ago),
    history.close(latest),
  ))
  use window_return <- result.try(return_percent(
    expected_code,
    history.close(first),
    history.close(latest),
  ))
  Ok(Row(
    expected,
    history.name(item.history),
    history.date(first),
    history.date(latest),
    history.close(first),
    history.close(latest),
    latest_session_return,
    five_session_return,
    window_return,
    count,
    item.source_reference,
    item.response_bytes,
    item.response_sha256,
  ))
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

fn return_percent(
  code: String,
  start_raw: String,
  end_raw: String,
) -> Result(decimal.Decimal, Error) {
  use start <- result.try(
    decimal.parse(start_raw)
    |> result.map_error(fn(_) { InvalidClose(code, start_raw) }),
  )
  use end <- result.try(
    decimal.parse(end_raw)
    |> result.map_error(fn(_) { InvalidClose(code, end_raw) }),
  )
  use _ <- result.try(case decimal.compare(start, decimal.zero()) {
    Gt -> Ok(Nil)
    _ -> Error(ZeroStartingClose(code))
  })
  use _ <- result.try(case decimal.compare(end, decimal.zero()) {
    Gt -> Ok(Nil)
    _ -> Error(InvalidClose(code, end_raw))
  })
  let assert Ok(hundred) = decimal.parse("100")
  use ratio <- result.try(
    decimal.divide(
      decimal.subtract(end, start),
      by: start,
      scale: 8,
      rounding: decimal.HalfEven,
    )
    |> result.map_error(fn(_) { ZeroStartingClose(code) }),
  )
  let percentage = decimal.multiply(ratio, hundred)
  decimal.quantize(percentage, scale: 2, rounding: decimal.HalfEven)
  |> result.map_error(fn(_) { InvalidClose(code, end_raw) })
}

fn validate_common_window(
  rows: List(Row),
  first: time.Date,
  latest: time.Date,
) -> Result(Nil, Error) {
  case rows {
    [] -> Ok(Nil)
    [row, ..rest] ->
      case
        date.compare(row.first_date, first),
        date.compare(row.latest_date, latest)
      {
        Eq, Eq -> validate_common_window(rest, first, latest)
        _, _ ->
          Error(InconsistentObservedWindow(query.cn_sector_code(row.index)))
      }
  }
}

fn first_row(rows: List(Row)) -> Result(Row, Error) {
  case rows {
    [first, ..] -> Ok(first)
    [] -> Error(InvalidSeriesCount(list.length(query.cn_sector_indices()), 0))
  }
}

fn rank(rows: List(Row), by selector: fn(Row) -> decimal.Decimal) -> List(Row) {
  list.sort(rows, fn(left, right) {
    decimal.compare(selector(right), selector(left))
  })
}

fn row_content(row: Row) -> String {
  query.cn_sector_code(row.index)
  <> ","
  <> query.cn_sector_label(row.index)
  <> ","
  <> query.cn_sector_official_name(row.index)
  <> ","
  <> row.provider_name
  <> ","
  <> decimal.to_string(row.latest_session_return)
  <> ","
  <> decimal.to_string(row.five_session_return)
  <> ","
  <> decimal.to_string(row.window_return)
  <> ","
  <> date_text(row.first_date)
  <> ","
  <> date_text(row.latest_date)
}

fn row_json(row: Row) -> json.Json {
  json.object([
    #("sectorCode", json.string(query.cn_sector_code(row.index))),
    #("sectorLabel", json.string(query.cn_sector_label(row.index))),
    #("officialName", json.string(query.cn_sector_official_name(row.index))),
    #("providerName", json.string(row.provider_name)),
    #(
      "providerMarket",
      json.string(query.market_name(query.cn_sector_market(row.index))),
    ),
    #("instrumentKind", json.string("sector_index")),
    #("firstObservedDate", json.string(date_text(row.first_date))),
    #("latestObservedDate", json.string(date_text(row.latest_date))),
    #("firstClose", json.string(row.first_close)),
    #("latestClose", json.string(row.latest_close)),
    #(
      "latestSessionReturnPercent",
      json.string(decimal.to_string(row.latest_session_return)),
    ),
    #(
      "fiveSessionReturnPercent",
      json.string(decimal.to_string(row.five_session_return)),
    ),
    #("windowReturnPercent", json.string(decimal.to_string(row.window_return))),
    #("observations", json.int(row.bars)),
    #("sourceReference", json.string(row.source_reference)),
    #("responseBytes", json.int(row.response_bytes)),
    #("responseSha256", json.string(identity.sha256_value(row.response_sha256))),
  ])
}

fn rank_json(row: Row) -> json.Json {
  json.object([
    #("sectorCode", json.string(query.cn_sector_code(row.index))),
    #("sectorLabel", json.string(query.cn_sector_label(row.index))),
  ])
}

fn unavailable(reason: String) -> json.Json {
  json.object([
    #("state", json.string("unavailable")),
    #("reason", json.string(reason)),
  ])
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
