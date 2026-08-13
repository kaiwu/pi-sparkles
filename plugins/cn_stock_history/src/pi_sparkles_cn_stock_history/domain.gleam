import finance_calendar/date
import finance_core/time
import finance_eastmoney/history as eastmoney_history
import finance_eastmoney/query as eastmoney_query
import finance_ohlcv/acquisition_receipt
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_track
import finance_tushare/daily as tushare_daily
import finance_tushare/query as tushare_query
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/order.{Gt}
import gleam/result
import gleam/string

pub type Provider {
  Eastmoney
  Tushare
}

pub type Venue {
  Sse
  Szse
  Bse
}

pub opaque type Plan {
  Plan(
    provider: Provider,
    venue: Venue,
    code: String,
    identity_evidence_id: String,
    start_date: time.Date,
    end_date: time.Date,
    limit: Int,
  )
}

pub opaque type Output {
  Output(summary: String, model_content: String, details: json.Json)
}

pub type Error {
  WrongTrack
  InvalidProvider
  InvalidVenue
  InvalidCode
  UnsupportedShareClass
  InvalidIdentityEvidenceId
  InvalidDateRange
  InvalidLimit
  ProviderMismatch
  InvalidReceipt(acquisition_receipt.ReceiptError)
  InvalidReceiptDigest
}

pub fn plan(
  track: String,
  provider: String,
  venue: String,
  code: String,
  share_class: String,
  identity_evidence_id: String,
  start_date: time.Date,
  end_date: time.Date,
  limit: Int,
) -> Result(Plan, Error) {
  use _ <- result.try(case track {
    "cn" -> Ok(Nil)
    _ -> Error(WrongTrack)
  })
  use provider <- result.try(provider_from_name(provider))
  use venue <- result.try(venue_from_name(venue))
  use _ <- result.try(case valid_code(code) {
    True -> Ok(Nil)
    False -> Error(InvalidCode)
  })
  use _ <- result.try(case share_class {
    "a_share" -> Ok(Nil)
    _ -> Error(UnsupportedShareClass)
  })
  use _ <- result.try(case valid_evidence_id(identity_evidence_id) {
    True -> Ok(Nil)
    False -> Error(InvalidIdentityEvidenceId)
  })
  use _ <- result.try(case date.compare(start_date, end_date) {
    Gt -> Error(InvalidDateRange)
    _ -> Ok(Nil)
  })
  use _ <- result.try(case limit >= 1 && limit <= 1000 {
    True -> Ok(Nil)
    False -> Error(InvalidLimit)
  })
  Ok(Plan(
    provider,
    venue,
    code,
    identity_evidence_id,
    start_date,
    end_date,
    limit,
  ))
}

pub fn provider(value: Plan) -> Provider {
  value.provider
}

pub fn venue(value: Plan) -> Venue {
  value.venue
}

pub fn code(value: Plan) -> String {
  value.code
}

pub fn start_date(value: Plan) -> time.Date {
  value.start_date
}

pub fn end_date(value: Plan) -> time.Date {
  value.end_date
}

pub fn limit(value: Plan) -> Int {
  value.limit
}

pub fn eastmoney_plan(
  value: Plan,
) -> Result(eastmoney_query.HistoryQuery, Error) {
  case value.provider {
    Tushare -> Error(ProviderMismatch)
    Eastmoney ->
      eastmoney_query.history(
        finance_track.Cn,
        eastmoney_market(value.venue),
        value.code,
        value.start_date,
        value.end_date,
        value.limit,
      )
      |> result.map_error(fn(_) { InvalidDateRange })
  }
}

pub fn tushare_plan(value: Plan) -> Result(tushare_query.DailyQuery, Error) {
  case value.provider {
    Eastmoney -> Error(ProviderMismatch)
    Tushare ->
      tushare_query.daily(
        finance_track.Cn,
        tushare_exchange(value.venue),
        value.code,
        value.start_date,
        value.end_date,
        value.limit,
      )
      |> result.map_error(fn(_) { InvalidDateRange })
  }
}

pub fn assemble_eastmoney(
  plan: Plan,
  value: eastmoney_history.History,
  retrieved_at: time.Instant,
  response_bytes: Int,
  content_sha256: Sha256,
) -> Result(Output, Error) {
  use query <- result.try(eastmoney_plan(plan))
  let bars = eastmoney_history.bars(value)
  let dates = bars |> list.map(eastmoney_history.date) |> ascending_dates
  use receipt <- result.try(make_receipt(
    plan,
    "eastmoney",
    eastmoney_query.history_source_reference(query),
    retrieved_at,
    response_bytes,
    content_sha256,
    dates,
  ))
  let summary =
    "CN "
    <> plan.code
    <> " | Eastmoney raw unadjusted daily | "
    <> int.to_string(list.length(bars))
    <> " rows"
  Ok(Output(
    summary,
    eastmoney_model_content(summary, plan, bars, retrieved_at, receipt),
    base_json(
      plan,
      "eastmoney",
      eastmoney_query.history_source_reference(query),
      retrieved_at,
      receipt,
      "provider_order_ascending",
      "unknown",
      "unknown",
      json.array(bars, eastmoney_bar_json),
    ),
  ))
}

pub fn assemble_tushare(
  plan: Plan,
  value: tushare_daily.Daily,
  retrieved_at: time.Instant,
  response_bytes: Int,
  content_sha256: Sha256,
) -> Result(Output, Error) {
  use query <- result.try(tushare_plan(plan))
  let bars = tushare_daily.bars(value)
  let dates = bars |> list.map(tushare_daily.date) |> ascending_dates
  use receipt <- result.try(make_receipt(
    plan,
    "tushare_pro",
    tushare_query.daily_source_reference(query),
    retrieved_at,
    response_bytes,
    content_sha256,
    dates,
  ))
  let summary =
    "CN "
    <> plan.code
    <> " | Tushare Pro raw unadjusted daily | "
    <> int.to_string(list.length(bars))
    <> " rows"
  Ok(Output(
    summary,
    tushare_model_content(summary, plan, bars, retrieved_at, receipt),
    base_json(
      plan,
      "tushare_pro",
      tushare_query.daily_source_reference(query),
      retrieved_at,
      receipt,
      "provider_order_descending",
      "provider_lot_手",
      "thousand_cny",
      json.array(bars, tushare_bar_json),
    ),
  ))
}

pub fn summary(value: Output) -> String {
  value.summary
}

pub fn model_content(value: Output) -> String {
  value.model_content
}

pub fn details(value: Output) -> json.Json {
  value.details
}

pub fn error_message(value: Error) -> String {
  case value {
    WrongTrack -> "track must be cn"
    InvalidProvider -> "provider must be explicitly eastmoney or tushare"
    InvalidVenue -> "venue must be sse, szse, or bse"
    InvalidCode -> "code must be exactly six digits"
    UnsupportedShareClass ->
      "T1 history covers explicitly proven a_share listings only"
    InvalidIdentityEvidenceId -> "identityEvidenceId is invalid"
    InvalidDateRange -> "date range is invalid"
    InvalidLimit -> "limit must be between 1 and 1000"
    ProviderMismatch -> "selected provider and adapter do not match"
    InvalidReceipt(error) ->
      "canonical acquisition receipt was invalid: " <> string.inspect(error)
    InvalidReceiptDigest -> "canonical acquisition receipt digest failed"
  }
}

fn make_receipt(
  plan: Plan,
  provider: String,
  source_reference: String,
  retrieved_at: time.Instant,
  response_bytes: Int,
  content_sha256: Sha256,
  dates: List(time.Date),
) -> Result(acquisition_receipt.Receipt, Error) {
  use code <- result.try(
    acquisition_receipt.identity_field("code", plan.code)
    |> result.map_error(InvalidReceipt),
  )
  use mic <- result.try(
    acquisition_receipt.identity_field("venue_mic", venue_mic(plan.venue))
    |> result.map_error(InvalidReceipt),
  )
  use evidence <- result.try(
    acquisition_receipt.identity_field(
      "identity_evidence_id",
      plan.identity_evidence_id,
    )
    |> result.map_error(InvalidReceipt),
  )
  use adjustment <- result.try(
    acquisition_receipt.identity_field("adjustment", "raw_unadjusted")
    |> result.map_error(InvalidReceipt),
  )
  use page <- result.try(
    acquisition_receipt.page(1, None, response_bytes, content_sha256)
    |> result.map_error(InvalidReceipt),
  )
  acquisition_receipt.new(
    schema: "pi-sparkles/cn-stock-history-acquisition",
    schema_version: 1,
    track: finance_track.Cn,
    provider: provider,
    identity: [code, mic, evidence, adjustment],
    source_reference: source_reference,
    retrieved_at: retrieved_at,
    pagination: acquisition_receipt.Complete,
    pages: [page],
    range_start: plan.start_date,
    range_end: plan.end_date,
    bar_dates: dates,
  )
  |> result.map_error(InvalidReceipt)
}

fn base_json(
  plan: Plan,
  provider: String,
  source_reference: String,
  retrieved_at: time.Instant,
  receipt: acquisition_receipt.Receipt,
  row_order: String,
  volume_unit: String,
  amount_unit: String,
  bars: json.Json,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/cn-stock-history-result")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string("cn_stock_history")),
    #("track", json.string("cn")),
    #("selectedProvider", json.string(provider)),
    #("fallbackPerformed", json.bool(False)),
    #(
      "listing",
      json.object([
        #("code", json.string(plan.code)),
        #("venue", json.string(venue_name(plan.venue))),
        #("venueMic", json.string(venue_mic(plan.venue))),
        #("shareClass", json.string("a_share")),
        #("declaredCurrency", json.string("CNY")),
        #("identityEvidenceId", json.string(plan.identity_evidence_id)),
        #(
          "identityEvidenceAuthentication",
          json.string("not_authenticated_by_this_tool"),
        ),
      ]),
    ),
    #(
      "range",
      json.object([
        #("start", json.string(date_text(plan.start_date))),
        #("end", json.string(date_text(plan.end_date))),
        #("inclusive", json.bool(True)),
        #("limit", json.int(plan.limit)),
      ]),
    ),
    #("frequency", json.string("daily")),
    #("adjustment", json.string("raw_unadjusted")),
    #("rowOrder", json.string(row_order)),
    #("volumeUnit", json.string(volume_unit)),
    #("amountUnit", json.string(amount_unit)),
    #("bars", bars),
    #(
      "source",
      json.object([
        #("provider", json.string(provider)),
        #("reference", json.string(source_reference)),
        #("kind", json.string("vendor")),
        #("exchangeEvidence", json.bool(False)),
        #(
          "retrievedAtUnixMilliseconds",
          json.int(time.unix_milliseconds(retrieved_at)),
        ),
        #(
          "entitlement",
          json.string("provider_account_or_public_web_local_analysis"),
        ),
        #("redistribution", json.string("unknown_or_provider_controlled")),
      ]),
    ),
    #("acquisitionReceipt", receipt_json(receipt)),
    #("omissionAssessment", json.string("not_performed_no_calendar_join")),
    #(
      "limitations",
      json.array(
        [
          "identity_evidence_reference_not_authenticated_by_this_tool",
          "vendor_origin_not_exchange_evidence",
          "no_silent_provider_fallback",
          "no_gap_fill_or_suspension_inference",
          "no_adjustment_equivalence_or_return_calculation",
          "single_page_provider_response_with_content_bound_receipt",
        ],
        json.string,
      ),
    ),
  ])
}

fn receipt_json(value: acquisition_receipt.Receipt) -> json.Json {
  let canonical = acquisition_receipt.canonical_text(value)
  let assert Ok(digest) = hash.text(canonical)
  let assert [page] = acquisition_receipt.pages(value)
  json.object([
    #("schema", json.string(acquisition_receipt.schema(value))),
    #("schemaVersion", json.int(acquisition_receipt.schema_version(value))),
    #("canonicalSha256", json.string(identity.sha256_value(digest))),
    #(
      "contentSha256",
      json.string(
        identity.sha256_value(acquisition_receipt.page_content_sha256(page)),
      ),
    ),
    #(
      "responseByteLength",
      json.int(acquisition_receipt.page_byte_length(page)),
    ),
    #(
      "pagination",
      json.string(
        acquisition_receipt.pagination_name(acquisition_receipt.pagination(
          value,
        )),
      ),
    ),
    #(
      "integrity",
      json.string("sha256_content_bound_not_provider_authenticated"),
    ),
  ])
}

fn eastmoney_bar_json(value: eastmoney_history.Bar) -> json.Json {
  json.object([
    #("date", json.string(date_text(eastmoney_history.date(value)))),
    #("open", json.string(eastmoney_history.open(value))),
    #("high", json.string(eastmoney_history.high(value))),
    #("low", json.string(eastmoney_history.low(value))),
    #("close", json.string(eastmoney_history.close(value))),
    #("volume", json.string(eastmoney_history.volume(value))),
    #("amount", json.string(eastmoney_history.amount(value))),
    #(
      "providerFields",
      json.object([
        #(
          "amplitudePercent",
          json.string(eastmoney_history.amplitude_percent(value)),
        ),
        #("changePercent", json.string(eastmoney_history.change_percent(value))),
        #("change", json.string(eastmoney_history.change(value))),
        #(
          "turnoverPercent",
          json.string(eastmoney_history.turnover_percent(value)),
        ),
      ]),
    ),
  ])
}

fn eastmoney_model_content(
  summary: String,
  plan: Plan,
  bars: List(eastmoney_history.Bar),
  retrieved_at: time.Instant,
  receipt: acquisition_receipt.Receipt,
) -> String {
  summary
  <> "\nComplete bounded daily rows follow as CSV. Use close for SMA/RSI and high,low,close for ATR; do not claim the daily values are unavailable.\n"
  <> model_metadata(plan, "eastmoney", retrieved_at, receipt)
  <> "\ndate,open,high,low,close,volume,amount\n"
  <> {
    bars
    |> list.map(fn(bar) {
      [
        date_text(eastmoney_history.date(bar)),
        eastmoney_history.open(bar),
        eastmoney_history.high(bar),
        eastmoney_history.low(bar),
        eastmoney_history.close(bar),
        eastmoney_history.volume(bar),
        eastmoney_history.amount(bar),
      ]
      |> string.join(",")
    })
    |> string.join("\n")
  }
}

fn tushare_bar_json(value: tushare_daily.Bar) -> json.Json {
  json.object([
    #("date", json.string(date_text(tushare_daily.date(value)))),
    #("open", json.string(tushare_daily.open(value))),
    #("high", json.string(tushare_daily.high(value))),
    #("low", json.string(tushare_daily.low(value))),
    #("close", json.string(tushare_daily.close(value))),
    #("volume", json.string(tushare_daily.volume_lots(value))),
    #("amount", json.string(tushare_daily.amount_thousand_cny(value))),
    #(
      "providerFields",
      json.object([
        #("previousClose", json.string(tushare_daily.previous_close(value))),
        #("change", json.string(tushare_daily.change(value))),
        #("changePercent", json.string(tushare_daily.change_percent(value))),
      ]),
    ),
  ])
}

fn tushare_model_content(
  summary: String,
  plan: Plan,
  bars: List(tushare_daily.Bar),
  retrieved_at: time.Instant,
  receipt: acquisition_receipt.Receipt,
) -> String {
  summary
  <> "\nComplete bounded daily rows follow as CSV. Use close for SMA/RSI and high,low,close for ATR; do not claim the daily values are unavailable.\n"
  <> model_metadata(plan, "tushare_pro", retrieved_at, receipt)
  <> "\ndate,open,high,low,close,volume,amount\n"
  <> {
    bars
    |> list.map(fn(bar) {
      [
        date_text(tushare_daily.date(bar)),
        tushare_daily.open(bar),
        tushare_daily.high(bar),
        tushare_daily.low(bar),
        tushare_daily.close(bar),
        tushare_daily.volume_lots(bar),
        tushare_daily.amount_thousand_cny(bar),
      ]
      |> string.join(",")
    })
    |> string.join("\n")
  }
}

fn model_metadata(
  plan: Plan,
  provider: String,
  retrieved_at: time.Instant,
  receipt: acquisition_receipt.Receipt,
) -> String {
  let assert Ok(digest) = hash.text(acquisition_receipt.canonical_text(receipt))
  "track=cn;provider="
  <> provider
  <> ";venue="
  <> venue_name(plan.venue)
  <> ";venueMic="
  <> venue_mic(plan.venue)
  <> ";code="
  <> plan.code
  <> ";currency=CNY;frequency=daily;adjustment=raw_unadjusted;retrievedAtUnixMilliseconds="
  <> int.to_string(time.unix_milliseconds(retrieved_at))
  <> ";acquisitionReceiptCanonicalSha256="
  <> identity.sha256_value(digest)
  <> ";sourceReference="
  <> acquisition_receipt.source_reference(receipt)
}

fn provider_from_name(value: String) -> Result(Provider, Error) {
  case value {
    "eastmoney" -> Ok(Eastmoney)
    "tushare" -> Ok(Tushare)
    _ -> Error(InvalidProvider)
  }
}

fn venue_from_name(value: String) -> Result(Venue, Error) {
  case value {
    "sse" -> Ok(Sse)
    "szse" -> Ok(Szse)
    "bse" -> Ok(Bse)
    _ -> Error(InvalidVenue)
  }
}

fn eastmoney_market(value: Venue) -> eastmoney_query.Market {
  case value {
    Sse -> eastmoney_query.CnSse
    Szse -> eastmoney_query.CnSzse
    Bse -> eastmoney_query.CnBse
  }
}

fn tushare_exchange(value: Venue) -> tushare_query.Exchange {
  case value {
    Sse -> tushare_query.Sse
    Szse -> tushare_query.Szse
    Bse -> tushare_query.Bse
  }
}

fn venue_name(value: Venue) -> String {
  case value {
    Sse -> "sse"
    Szse -> "szse"
    Bse -> "bse"
  }
}

fn venue_mic(value: Venue) -> String {
  case value {
    Sse -> "XSHG"
    Szse -> "XSHE"
    Bse -> "XBSE"
  }
}

fn ascending_dates(values: List(time.Date)) -> List(time.Date) {
  list.sort(values, by: date.compare)
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 6
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn valid_evidence_id(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 256
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
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
