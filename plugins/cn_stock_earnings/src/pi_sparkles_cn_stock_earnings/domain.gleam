import finance_core/decimal
import finance_core/time
import finance_provenance/identity.{type Sha256}
import finance_track
import finance_tushare/query
import finance_tushare/request
import finance_tushare/response
import finance_tushare/table
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type EventClass {
  Forecast
  ExpressReport
  DisclosureSchedule
}

pub opaque type Plan {
  Plan(
    event_class: EventClass,
    exchange: query.Exchange,
    code: String,
    identity_evidence_id: String,
    start_date: time.Date,
    end_date: time.Date,
    maximum_rows: Int,
  )
}

pub opaque type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  WrongTrack
  InvalidVenue
  InvalidCode
  UnsupportedShareClass
  InvalidEventClass
  InvalidIdentityEvidenceId
  InvalidRange
  InvalidLimit
  InvalidProviderQuery
  InvalidTable(table.DecodeError)
  InvalidRow(index: Int)
  IdentityMismatch
}

pub fn plan(
  track: String,
  venue: String,
  code: String,
  share_class: String,
  identity_evidence_id: String,
  event_class: String,
  start_date: time.Date,
  end_date: time.Date,
  maximum_rows: Int,
) -> Result(Plan, Error) {
  use _ <- result.try(case track {
    "cn" -> Ok(Nil)
    _ -> Error(WrongTrack)
  })
  use exchange <- result.try(exchange_from_name(venue))
  use class <- result.try(class_from_name(event_class))
  use _ <- result.try(case share_class {
    "a_share" -> Ok(Nil)
    _ -> Error(UnsupportedShareClass)
  })
  use _ <- result.try(case valid_evidence_id(identity_evidence_id) {
    True -> Ok(Nil)
    False -> Error(InvalidIdentityEvidenceId)
  })
  use _ <- result.try(case date_key(start_date) <= date_key(end_date) {
    True -> Ok(Nil)
    False -> Error(InvalidRange)
  })
  use _ <- result.try(case maximum_rows >= 1 && maximum_rows <= 1000 {
    True -> Ok(Nil)
    False -> Error(InvalidLimit)
  })
  use _ <- result.try(
    query.security(finance_track.Cn, exchange, code, maximum_rows)
    |> result.map_error(fn(error) {
      case error {
        query.InvalidCode -> InvalidCode
        _ -> InvalidProviderQuery
      }
    }),
  )
  Ok(Plan(
    class,
    exchange,
    code,
    identity_evidence_id,
    start_date,
    end_date,
    maximum_rows,
  ))
}

pub fn event_class(value: Plan) -> EventClass {
  value.event_class
}

pub fn dated_query(value: Plan) -> Result(query.DatedSecurityQuery, Error) {
  query.dated_security(
    finance_track.Cn,
    value.exchange,
    value.code,
    value.start_date,
    value.end_date,
    value.maximum_rows,
  )
  |> result.map_error(fn(_) { InvalidProviderQuery })
}

pub fn security_query(value: Plan) -> Result(query.SecurityQuery, Error) {
  query.security(
    finance_track.Cn,
    value.exchange,
    value.code,
    value.maximum_rows,
  )
  |> result.map_error(fn(_) { InvalidProviderQuery })
}

pub fn decode_and_assemble(
  plan: Plan,
  body: String,
  retrieved_at: time.Instant,
  response_bytes: Int,
  content_sha256: Sha256,
) -> Result(Output, Error) {
  let #(fields, api_name) = case plan.event_class {
    Forecast -> #(request.forecast_fields, request.forecast_api)
    ExpressReport -> #(request.express_fields, request.express_api)
    DisclosureSchedule -> #(
      request.disclosure_date_fields,
      request.disclosure_date_api,
    )
  }
  use source <- result.try(
    table.decode(body, fields, plan.maximum_rows)
    |> result.map_error(InvalidTable),
  )
  let expected = query.ts_code(plan.exchange, plan.code)
  use events <- result.try(
    decode_rows(table.rows(source), plan.event_class, expected, 0, []),
  )
  Ok(Output(
    "CN "
      <> expected
      <> " | "
      <> class_name(plan.event_class)
      <> " | "
      <> int.to_string(list.length(events))
      <> " exact source rows",
    json.object([
      #("schema", json.string("pi-sparkles/cn-stock-earnings-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("cn_stock_earnings")),
      #("track", json.string("cn")),
      #("eventClass", json.string(class_name(plan.event_class))),
      #(
        "listing",
        json.object([
          #("tsCode", json.string(expected)),
          #("code", json.string(plan.code)),
          #("venue", json.string(query.exchange_name(plan.exchange))),
          #("shareClass", json.string("a_share")),
          #("identityEvidenceId", json.string(plan.identity_evidence_id)),
          #(
            "identityEvidenceAuthentication",
            json.string("not_authenticated_by_this_tool"),
          ),
        ]),
      ),
      #(
        "queryRange",
        json.object([
          #("start", json.string(date_text(plan.start_date))),
          #("end", json.string(date_text(plan.end_date))),
          #(
            "dateAxis",
            json.string(case plan.event_class {
              DisclosureSchedule -> "local_filter_latest_announcement_date"
              _ -> "provider_announcement_date"
            }),
          ),
        ]),
      ),
      #("events", json.array(events, fn(value) { value })),
      #(
        "timelinePolicy",
        json.object([
          #("sort", json.string("provider_order_preserved")),
          #("crossClassSubstitution", json.bool(False)),
          #("correctionSelection", json.string("preserve_all_rows")),
          #("missingDateFill", json.bool(False)),
        ]),
      ),
      #(
        "source",
        json.object([
          #("provider", json.string("Tushare Pro")),
          #("api", json.string(api_name)),
          #("reference", json.string(source_reference(plan, api_name))),
          #("kind", json.string("structured_vendor")),
          #("exchangeEvidence", json.bool(False)),
          #(
            "retrievedAtUnixMilliseconds",
            json.int(time.unix_milliseconds(retrieved_at)),
          ),
          #(
            "entitlement",
            json.string("caller_provider_account_permission_required"),
          ),
          #("redistribution", json.string("provider_controlled_unknown")),
        ]),
      ),
      #(
        "acquisitionReceipt",
        json.object([
          #("contentSha256", json.string(identity.sha256_value(content_sha256))),
          #("responseByteLength", json.int(response_bytes)),
          #(
            "integrity",
            json.string("sha256_content_bound_not_provider_authenticated"),
          ),
        ]),
      ),
      #(
        "limitations",
        json.array(
          [
            "forecast_express_and_disclosure_schedule_remain_distinct_event_classes",
            "provider_rows_are_not_periodic_report_documents",
            "board_meeting_dates_not_available_in_selected_structured_endpoints",
            "no_forecast_actual_surprise_quality_or_materiality_judgment",
            "no_recommendation_or_trade_action",
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

pub fn details(value: Output) -> json.Json {
  value.details
}

pub fn error_message(value: Error) -> String {
  case value {
    WrongTrack -> "track must be cn"
    InvalidVenue -> "venue must be sse, szse, or bse"
    InvalidCode -> "code must be exactly six digits"
    UnsupportedShareClass -> "only a_share is supported"
    InvalidEventClass ->
      "eventClass must be forecast, express_report, or disclosure_schedule"
    InvalidIdentityEvidenceId -> "identityEvidenceId is invalid"
    InvalidRange -> "startDate must not follow endDate"
    InvalidLimit -> "maximumRows must be between 1 and 1000"
    InvalidProviderQuery -> "provider query is invalid"
    InvalidTable(error) -> table.error_message(error)
    InvalidRow(index) ->
      "Tushare earnings row is invalid at index " <> int.to_string(index)
    IdentityMismatch ->
      "Tushare earnings row identity does not match the exact listing"
  }
}

fn decode_rows(rows, class, expected, index, decoded) {
  case rows {
    [] -> Ok(list.reverse(decoded))
    [row, ..rest] -> {
      use #(received, event) <- result.try(
        decode_row(row, class) |> result.map_error(fn(_) { InvalidRow(index) }),
      )
      use _ <- result.try(case received == expected {
        True -> Ok(Nil)
        False -> Error(IdentityMismatch)
      })
      decode_rows(rest, class, expected, index + 1, [event, ..decoded])
    }
  }
}

fn decode_row(row, class) -> Result(#(String, json.Json), Nil) {
  case class, row {
    Forecast,
      [
        ts,
        ann,
        period,
        kind,
        change_min,
        change_max,
        profit_min,
        profit_max,
        last_profit,
        first_ann,
        summary,
        reason,
      ]
    -> {
      use ts <- result.try(response.text(ts))
      use ann <- result.try(required_date(ann))
      use period <- result.try(required_date(period))
      use kind <- result.try(response.text(kind))
      use change_min <- result.try(optional_decimal(change_min))
      use change_max <- result.try(optional_decimal(change_max))
      use profit_min <- result.try(optional_decimal(profit_min))
      use profit_max <- result.try(optional_decimal(profit_max))
      use last_profit <- result.try(optional_decimal(last_profit))
      use first_ann <- result.try(optional_date(first_ann))
      use summary <- result.try(response.optional_text(summary))
      use reason <- result.try(response.optional_text(reason))
      Ok(#(
        ts,
        json.object([
          #("eventClass", json.string("forecast")),
          #("announcementDate", json.string(ann)),
          #("reportPeriodEnd", json.string(period)),
          #("forecastType", json.string(kind)),
          #("netProfitChangePercentMin", option_json(change_min)),
          #("netProfitChangePercentMax", option_json(change_max)),
          #("netProfitMinTenThousandCny", option_json(profit_min)),
          #("netProfitMaxTenThousandCny", option_json(profit_max)),
          #("priorParentNetProfit", option_json(last_profit)),
          #("firstAnnouncementDate", option_json(first_ann)),
          #("summaryOriginalZh", option_json(summary)),
          #("changeReasonOriginalZh", option_json(reason)),
        ]),
      ))
    }
    ExpressReport,
      [
        ts,
        ann,
        period,
        revenue,
        operating_profit,
        total_profit,
        net_income,
        total_assets,
        equity,
        eps,
        roe,
        summary,
        audit,
        remark,
      ]
    -> {
      use ts <- result.try(response.text(ts))
      use ann <- result.try(required_date(ann))
      use period <- result.try(required_date(period))
      use revenue <- result.try(optional_decimal(revenue))
      use operating_profit <- result.try(optional_decimal(operating_profit))
      use total_profit <- result.try(optional_decimal(total_profit))
      use net_income <- result.try(optional_decimal(net_income))
      use total_assets <- result.try(optional_decimal(total_assets))
      use equity <- result.try(optional_decimal(equity))
      use eps <- result.try(optional_decimal(eps))
      use roe <- result.try(optional_decimal(roe))
      use summary <- result.try(response.optional_text(summary))
      use audit <- result.try(response.optional_scalar(audit))
      use remark <- result.try(response.optional_text(remark))
      Ok(#(
        ts,
        json.object([
          #("eventClass", json.string("express_report")),
          #("announcementDate", json.string(ann)),
          #("reportPeriodEnd", json.string(period)),
          #("revenueCny", option_json(revenue)),
          #("operatingProfitCny", option_json(operating_profit)),
          #("totalProfitCny", option_json(total_profit)),
          #("netIncomeCny", option_json(net_income)),
          #("totalAssetsCny", option_json(total_assets)),
          #("parentEquityExcludingMinorityCny", option_json(equity)),
          #("dilutedEpsCnyPerShare", option_json(eps)),
          #("dilutedRoePercent", option_json(roe)),
          #("summaryOriginalZh", option_json(summary)),
          #("auditFlagProviderCode", option_json(audit)),
          #("remarkOriginalZh", option_json(remark)),
        ]),
      ))
    }
    DisclosureSchedule, [ts, ann, period, planned, actual, modified] -> {
      use ts <- result.try(response.text(ts))
      use ann <- result.try(required_date(ann))
      use period <- result.try(required_date(period))
      use planned <- result.try(optional_date(planned))
      use actual <- result.try(optional_date(actual))
      use modified <- result.try(optional_date(modified))
      Ok(#(
        ts,
        json.object([
          #("eventClass", json.string("disclosure_schedule")),
          #("latestScheduleAnnouncementDate", json.string(ann)),
          #("reportPeriodEnd", json.string(period)),
          #("plannedDisclosureDate", option_json(planned)),
          #("actualDisclosureDate", option_json(actual)),
          #("modifiedDisclosureDate", option_json(modified)),
        ]),
      ))
    }
    _, _ -> Error(Nil)
  }
}

fn source_reference(plan: Plan, api_name: String) -> String {
  case plan.event_class {
    DisclosureSchedule -> {
      let assert Ok(value) = security_query(plan)
      query.security_source_reference(value, api_name)
    }
    _ -> {
      let assert Ok(value) = dated_query(plan)
      query.dated_source_reference(value, api_name)
    }
  }
}

fn exchange_from_name(value: String) -> Result(query.Exchange, Error) {
  case value {
    "sse" -> Ok(query.Sse)
    "szse" -> Ok(query.Szse)
    "bse" -> Ok(query.Bse)
    _ -> Error(InvalidVenue)
  }
}

fn class_from_name(value: String) -> Result(EventClass, Error) {
  case value {
    "forecast" -> Ok(Forecast)
    "express_report" -> Ok(ExpressReport)
    "disclosure_schedule" -> Ok(DisclosureSchedule)
    _ -> Error(InvalidEventClass)
  }
}

fn class_name(value: EventClass) -> String {
  case value {
    Forecast -> "forecast"
    ExpressReport -> "express_report"
    DisclosureSchedule -> "disclosure_schedule"
  }
}

fn optional_decimal(value) -> Result(Option(String), Nil) {
  use value <- result.try(response.optional_scalar(value))
  case value {
    None -> Ok(None)
    Some(raw) ->
      case decimal.parse(raw) {
        Ok(_) -> Ok(Some(raw))
        Error(_) -> Error(Nil)
      }
  }
}

fn required_date(value) -> Result(String, Nil) {
  use value <- result.try(response.text(value))
  case valid_compact_date(value) {
    True -> Ok(value)
    False -> Error(Nil)
  }
}

fn optional_date(value) -> Result(Option(String), Nil) {
  use value <- result.try(response.optional_text(value))
  case value {
    None -> Ok(None)
    Some(value) ->
      case valid_compact_date(value) {
        True -> Ok(Some(value))
        False -> Error(Nil)
      }
  }
}

fn valid_compact_date(value: String) -> Bool {
  string.length(value) == 8
  && value
  |> string.to_graphemes
  |> list.all(fn(c) { string.contains("0123456789", c) })
}

fn valid_evidence_id(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 256
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn option_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn date_key(value: time.Date) -> Int {
  let #(y, m, d) = time.date_parts(value)
  y * 10_000 + m * 100 + d
}

fn date_text(value: time.Date) -> String {
  let #(y, m, d) = time.date_parts(value)
  int.to_string(y) <> "-" <> pad(m) <> "-" <> pad(d)
}

fn pad(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
