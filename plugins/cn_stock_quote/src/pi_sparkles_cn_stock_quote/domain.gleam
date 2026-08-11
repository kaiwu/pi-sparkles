import finance_calendar/date
import finance_core/time
import finance_eastmoney/query as eastmoney_query
import finance_eastmoney/quote as eastmoney_quote
import finance_provenance/identity.{type Sha256}
import finance_track
import finance_tushare/daily as tushare_daily
import finance_tushare/query as tushare_query
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq}
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
    as_of_date: time.Date,
  )
}

pub opaque type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  WrongTrack
  InvalidProvider
  InvalidVenue
  InvalidCode
  UnsupportedShareClass
  InvalidIdentityEvidenceId
  ProviderMismatch
  ProviderDateMismatch(expected: time.Date, received: time.Date)
  NoObservation
  MultipleObservations
}

pub fn plan(
  track: String,
  provider: String,
  venue: String,
  code: String,
  share_class: String,
  identity_evidence_id: String,
  as_of_date: time.Date,
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
  Ok(Plan(provider, venue, code, identity_evidence_id, as_of_date))
}

pub fn provider(value: Plan) -> Provider {
  value.provider
}

pub fn eastmoney_plan(
  value: Plan,
) -> Result(eastmoney_query.QuoteQuery, Error) {
  case value.provider {
    Tushare -> Error(ProviderMismatch)
    Eastmoney ->
      eastmoney_query.quote(
        finance_track.Cn,
        eastmoney_market(value.venue),
        value.code,
      )
      |> result.map_error(fn(_) { InvalidCode })
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
        value.as_of_date,
        value.as_of_date,
        1,
      )
      |> result.map_error(fn(_) { InvalidCode })
  }
}

pub fn assemble_eastmoney(
  plan: Plan,
  value: eastmoney_quote.Quote,
  retrieved_at: time.Instant,
  response_bytes: Int,
  content_sha256: Sha256,
) -> Result(Output, Error) {
  use _ <- result.try(eastmoney_plan(plan))
  use provider_date <- result.try(
    shanghai_date(eastmoney_quote.provider_unix_seconds(value)),
  )
  use _ <- result.try(require_date(plan.as_of_date, provider_date))
  let provider_timestamp =
    int.to_string(eastmoney_quote.provider_unix_seconds(value))
  Ok(Output(
    "CN "
      <> plan.code
      <> " | Eastmoney vendor quote snapshot | last "
      <> eastmoney_quote.last(value)
      <> " CNY | latency unknown",
    base_json(
      plan,
      "eastmoney",
      "vendor_quote_snapshot",
      provider_timestamp,
      Some(time.unix_milliseconds(retrieved_at)),
      retrieved_at,
      response_bytes,
      content_sha256,
      Some(eastmoney_quote.name(value)),
      eastmoney_quote.last(value),
      eastmoney_quote.open(value),
      eastmoney_quote.high(value),
      eastmoney_quote.low(value),
      eastmoney_quote.previous_close(value),
      Some(int.to_string(eastmoney_quote.provider_volume(value))),
      None,
      None,
      None,
      "unknown",
      "not_available_from_selected_endpoint",
      json.object([
        #("priceLimitUp", optional_json(eastmoney_quote.price_limit_up(value))),
        #(
          "priceLimitDown",
          optional_json(eastmoney_quote.price_limit_down(value)),
        ),
      ]),
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
  use _ <- result.try(tushare_plan(plan))
  use bar <- result.try(case tushare_daily.bars(value) {
    [] -> Error(NoObservation)
    [bar] -> Ok(bar)
    [_, _, ..] -> Error(MultipleObservations)
  })
  use _ <- result.try(require_date(plan.as_of_date, tushare_daily.date(bar)))
  Ok(Output(
    "CN "
      <> plan.code
      <> " | Tushare Pro end-of-day daily snapshot | close "
      <> tushare_daily.close(bar)
      <> " CNY",
    base_json(
      plan,
      "tushare_pro",
      "end_of_day_daily_bar_snapshot",
      date_text(tushare_daily.date(bar)),
      None,
      retrieved_at,
      response_bytes,
      content_sha256,
      None,
      tushare_daily.close(bar),
      tushare_daily.open(bar),
      tushare_daily.high(bar),
      tushare_daily.low(bar),
      tushare_daily.previous_close(bar),
      Some(tushare_daily.volume_lots(bar)),
      Some(tushare_daily.amount_thousand_cny(bar)),
      Some(tushare_daily.change(bar)),
      Some(tushare_daily.change_percent(bar)),
      "provider_lot_手",
      "thousand_cny",
      json.object([#("tradeDateGranularity", json.string("date_only"))]),
    ),
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
    InvalidProvider -> "provider must be explicitly eastmoney or tushare"
    InvalidVenue -> "venue must be sse, szse, or bse"
    InvalidCode -> "code must be exactly six digits"
    UnsupportedShareClass ->
      "T1 price snapshots cover explicitly proven a_share listings only"
    InvalidIdentityEvidenceId -> "identityEvidenceId is invalid"
    ProviderMismatch -> "selected provider and adapter do not match"
    ProviderDateMismatch(_, _) ->
      "provider observation date does not match requested asOfDate"
    NoObservation -> "selected provider returned no observation for asOfDate"
    MultipleObservations ->
      "selected provider returned multiple observations for one asOfDate"
  }
}

fn base_json(
  plan: Plan,
  provider: String,
  observation_kind: String,
  provider_timestamp: String,
  provider_unix_ms: Option(Int),
  retrieved_at: time.Instant,
  response_bytes: Int,
  content_sha256: Sha256,
  name: Option(String),
  last: String,
  open: String,
  high: String,
  low: String,
  previous_close: String,
  volume: Option(String),
  amount: Option(String),
  change: Option(String),
  change_percent: Option(String),
  volume_unit: String,
  amount_unit: String,
  provider_fields: json.Json,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/cn-stock-quote-result")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string("cn_stock_quote")),
    #("track", json.string("cn")),
    #("selectedProvider", json.string(provider)),
    #("fallbackPerformed", json.bool(False)),
    #("observationKind", json.string(observation_kind)),
    #(
      "listing",
      json.object([
        #("code", json.string(plan.code)),
        #("name", optional_json(name)),
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
    #("asOfDate", json.string(date_text(plan.as_of_date))),
    #("providerTimestamp", json.string(provider_timestamp)),
    #("providerUnixMilliseconds", option_int_json(provider_unix_ms)),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(retrieved_at)),
    ),
    #(
      "prices",
      json.object([
        #("lastOrClose", json.string(last)),
        #("open", json.string(open)),
        #("high", json.string(high)),
        #("low", json.string(low)),
        #("previousClose", json.string(previous_close)),
        #("currency", json.string("CNY")),
      ]),
    ),
    #("bid", json.null()),
    #("ask", json.null()),
    #("volume", optional_json(volume)),
    #("volumeUnit", json.string(volume_unit)),
    #("amount", optional_json(amount)),
    #("amountUnit", json.string(amount_unit)),
    #("change", optional_json(change)),
    #("changePercent", optional_json(change_percent)),
    #("providerFields", provider_fields),
    #(
      "source",
      json.object([
        #("provider", json.string(provider)),
        #("kind", json.string("vendor")),
        #("exchangeEvidence", json.bool(False)),
        #(
          "entitlement",
          json.string(case provider {
            "tushare_pro" -> "end_of_day_provider_account"
            _ -> "unknown_current_or_delayed_public_web"
          }),
        ),
        #("redistribution", json.string("unknown_or_provider_controlled")),
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
    #("freshness", json.string("unknown_no_service_level_claim")),
    #(
      "limitations",
      json.array(
        [
          "identity_evidence_reference_not_authenticated_by_this_tool",
          "vendor_origin_not_exchange_evidence",
          "no_silent_provider_fallback",
          "bid_and_ask_not_available_from_selected_first_slice_endpoints",
          "eastmoney_latency_and_volume_unit_unknown",
          "tushare_observation_is_end_of_day_daily_row_not_realtime_quote",
          "no_signal_recommendation_or_trade_action",
        ],
        json.string,
      ),
    ),
  ])
}

fn shanghai_date(unix_seconds: Int) -> Result(time.Date, Error) {
  let assert Ok(epoch) = time.date(1970, 1, 1)
  let local_days = { unix_seconds + 8 * 3600 } / 86_400
  date.add_days(epoch, local_days) |> result.map_error(fn(_) { NoObservation })
}

fn require_date(
  expected: time.Date,
  received: time.Date,
) -> Result(Nil, Error) {
  case date.compare(expected, received) {
    Eq -> Ok(Nil)
    _ -> Error(ProviderDateMismatch(expected, received))
  }
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

fn optional_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn option_int_json(value: Option(Int)) -> json.Json {
  case value {
    Some(value) -> json.int(value)
    None -> json.null()
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
