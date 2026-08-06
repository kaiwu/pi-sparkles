import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_listing/effective
import finance_listing/listing
import finance_market_alpaca/query as alpaca_query
import finance_ohlcv
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import finance_us_ohlcv/assessment
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pi
import pi/schema
import pi/tool
import pi_sparkles_us_ohlcv_gaps/query

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "us_ohlcv_gap_assessment",
    "US OHLCV gap assessment",
    "Classify every absent date in one copied Alpaca daily-bar receipt using the exact 2026 NYSE or Nasdaq calendar, caller-supplied listing interval, explicit status receipts, and complete provider pagination",
    "Compose bounded US OHLCV evidence without fetching data, synthesizing bars, or guessing closures, suspensions, provider omissions, or unavailable history",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case query.run(input) {
        Ok(value) ->
          tool.text_result(render(value), result_json(value, input))
          |> promise.resolve
        Error(error) -> tool.reject(error_message(error))
      }
    },
  )
  promise.resolve(Nil)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("venue", schema.string_enum(["nyse", "nasdaq"])),
    schema.Required("instrumentId", bounded_string(3, 200)),
    schema.Required("symbol", bounded_string(1, 20)),
    schema.Required("listingStartDate", bounded_string(10, 10)),
    schema.Required("listingEndDate", schema.nullable(bounded_string(10, 10))),
    schema.Required("listingEvidenceReference", bounded_string(1, 2000)),
    schema.Required("startDate", bounded_string(10, 10)),
    schema.Required("endDate", bounded_string(10, 10)),
    schema.Required("identityAsOf", bounded_string(10, 10)),
    schema.Required("feed", schema.string_enum(["iex", "sip"])),
    schema.Required(
      "pagination",
      schema.string_enum([
        "complete",
        "truncated_by_page_budget",
        "truncated_by_bar_budget",
      ]),
    ),
    schema.Required("sourceReference", bounded_string(1, 2000)),
    schema.Required(
      "requestIds",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 10),
    ),
    schema.Required(
      "barDates",
      schema.array(bounded_string(10, 10))
        |> schema.with_array_length(0, 366),
    ),
    schema.Required(
      "statusReceipts",
      schema.array(status_schema()) |> schema.with_array_length(0, 366),
    ),
  ])
}

fn status_schema() -> schema.Schema {
  schema.object([
    schema.Required("date", bounded_string(10, 10)),
    schema.Required("status", schema.string_enum(["trading", "suspended"])),
    schema.Required("evidenceReference", bounded_string(1, 2000)),
  ])
}

fn input_decoder() -> decode.Decoder(query.Input) {
  use venue <- decode.field("venue", venue_decoder())
  use instrument_id <- decode.field("instrumentId", decode.string)
  use symbol <- decode.field("symbol", decode.string)
  use listing_start <- decode.field("listingStartDate", date_decoder())
  use listing_end <- decode.field(
    "listingEndDate",
    decode.optional(date_decoder()),
  )
  use listing_evidence <- decode.field(
    "listingEvidenceReference",
    decode.string,
  )
  use start_date <- decode.field("startDate", date_decoder())
  use end_date <- decode.field("endDate", date_decoder())
  use identity_as_of <- decode.field("identityAsOf", date_decoder())
  use feed <- decode.field("feed", feed_decoder())
  use pagination <- decode.field("pagination", pagination_decoder())
  use source_reference <- decode.field("sourceReference", decode.string)
  use request_ids <- decode.field("requestIds", decode.list(of: decode.string))
  use bar_dates <- decode.field("barDates", decode.list(of: date_decoder()))
  use statuses <- decode.field(
    "statusReceipts",
    decode.list(of: status_decoder()),
  )
  decode.success(query.Input(
    venue,
    instrument_id,
    symbol,
    listing_start,
    listing_end,
    listing_evidence,
    start_date,
    end_date,
    identity_as_of,
    feed,
    pagination,
    source_reference,
    request_ids,
    bar_dates,
    statuses,
  ))
}

fn status_decoder() -> decode.Decoder(query.StatusInput) {
  use date <- decode.field("date", date_decoder())
  use status <- decode.field("status", status_decoder_value())
  use evidence <- decode.field("evidenceReference", decode.string)
  decode.success(query.StatusInput(date, status, evidence))
}

fn venue_decoder() -> decode.Decoder(assessment.Venue) {
  use value <- decode.then(decode.string)
  case value {
    "nyse" -> decode.success(assessment.Nyse)
    "nasdaq" -> decode.success(assessment.Nasdaq)
    _ -> decode.failure(assessment.Nyse, "exact nyse or nasdaq venue")
  }
}

fn feed_decoder() -> decode.Decoder(alpaca_query.Feed) {
  use value <- decode.then(decode.string)
  case value {
    "iex" -> decode.success(alpaca_query.Iex)
    "sip" -> decode.success(alpaca_query.Sip)
    _ -> decode.failure(alpaca_query.Iex, "explicit iex or sip feed")
  }
}

fn pagination_decoder() -> decode.Decoder(assessment.ProviderCompleteness) {
  use value <- decode.then(decode.string)
  case value {
    "complete" -> decode.success(assessment.Complete)
    "truncated_by_page_budget" ->
      decode.success(assessment.Incomplete("truncated_by_page_budget"))
    "truncated_by_bar_budget" ->
      decode.success(assessment.Incomplete("truncated_by_bar_budget"))
    _ -> decode.failure(assessment.Incomplete("invalid"), "pagination state")
  }
}

fn status_decoder_value() -> decode.Decoder(assessment.MarketStatus) {
  use value <- decode.then(decode.string)
  case value {
    "trading" -> decode.success(assessment.Trading)
    "suspended" -> decode.success(assessment.Suspended)
    _ -> decode.failure(assessment.Trading, "trading or suspended status")
  }
}

fn date_decoder() -> decode.Decoder(time.Date) {
  use value <- decode.then(decode.string)
  let assert Ok(placeholder) = time.date(2026, 1, 1)
  case parse_date(value) {
    Ok(date) -> decode.success(date)
    Error(_) -> decode.failure(placeholder, "exact Gregorian YYYY-MM-DD date")
  }
}

fn render(value: assessment.Assessment) -> String {
  "US track | "
  <> string.uppercase(assessment.venue_name(assessment.venue(value)))
  <> " OHLCV gaps | "
  <> int.to_string(assessment.assessed_date_count(value))
  <> " dates structurally classified from supplied receipts | "
  <> int.to_string(list.length(assessment.gaps(value)))
  <> " absent dates"
}

fn result_json(value: assessment.Assessment, input: query.Input) -> json.Json {
  let listing_receipt = assessment.listing_receipt_value(value)
  let key = assessment.listing_key(listing_receipt)
  let interval = assessment.listing_interval(listing_receipt)
  let provider = assessment.provider(value)
  let calendar_source = assessment.calendar_source(value)
  json.object(
    list.append(track_json.result_fields(result_context(value)), [
      #("venue", json.string(assessment.venue_name(assessment.venue(value)))),
      #(
        "listing",
        json.object([
          #(
            "instrumentId",
            json.string(
              key |> listing.instrument_id |> identifier.instrument_id_value,
            ),
          ),
          #(
            "symbol",
            json.string(key |> listing.symbol |> identifier.symbol_value),
          ),
          #("mic", json.string(key |> listing.mic |> identifier.mic_value)),
          #(
            "effective",
            json.object([
              #("start", json.string(date_text(effective.start(interval)))),
              #("end", case effective.end(interval) {
                Some(date) -> json.string(date_text(date))
                None -> json.null()
              }),
            ]),
          ),
          #(
            "evidenceReference",
            json.string(assessment.listing_evidence_reference(listing_receipt)),
          ),
          #("evidenceStatus", json.string("caller_supplied_unverified")),
        ]),
      ),
      #(
        "calendarReceipt",
        json.object([
          #("version", json.string(assessment.calendar_version(value))),
          #("provider", json.string(source.provider(calendar_source))),
          #("reference", json.string(source.reference(calendar_source))),
          #("coverage", json.string("2026-01-01/2026-12-31")),
          #("scheduleKind", json.string("planned_regular_equity")),
        ]),
      ),
      #(
        "providerReceipt",
        json.object([
          #("provider", json.string(assessment.provider_name(provider))),
          #("feed", json.string(alpaca_query.feed_name(input.feed))),
          #("identityAsOf", json.string(date_text(input.identity_as_of))),
          #(
            "sourceReference",
            json.string(assessment.provider_source_reference(provider)),
          ),
          #(
            "requestIds",
            json.array(assessment.provider_request_ids(provider), json.string),
          ),
          #("pagination", json.string("complete")),
          #(
            "integrity",
            json.string("copied_receipt_not_cryptographically_verified"),
          ),
        ]),
      ),
      #(
        "assessment",
        json.object([
          #("state", json.string("fully_classified_from_supplied_receipts")),
          #("startDate", json.string(date_text(assessment.start_date(value)))),
          #("endDate", json.string(date_text(assessment.end_date(value)))),
          #("datesAssessed", json.int(assessment.assessed_date_count(value))),
          #(
            "barsReturned",
            json.int(list.length(assessment.returned_bar_dates(value))),
          ),
          #("absentDates", json.int(list.length(assessment.gaps(value)))),
        ]),
      ),
      #(
        "barDates",
        json.array(assessment.returned_bar_dates(value), fn(date) {
          json.string(date_text(date))
        }),
      ),
      #("statusReceipts", json.array(assessment.statuses(value), status_json)),
      #("gaps", json.array(assessment.gaps(value), gap_json)),
      #("limitations", json.array(limitations(), json.string)),
    ]),
  )
}

fn status_json(value: assessment.StatusReceipt) -> json.Json {
  json.object([
    #("date", json.string(date_text(assessment.status_date(value)))),
    #("status", json.string(status_name(assessment.market_status(value)))),
    #(
      "evidenceReference",
      json.string(assessment.status_evidence_reference(value)),
    ),
    #("evidenceStatus", json.string("caller_supplied_unverified")),
  ])
}

fn gap_json(value: assessment.ClassifiedGap) -> json.Json {
  json.object([
    #("sessionDate", json.string(date_text(assessment.gap_date(value)))),
    #("state", json.string(gap_name(assessment.gap_state(value)))),
    #("evidence", json.array(assessment.gap_evidence(value), evidence_json)),
  ])
}

fn evidence_json(value: assessment.Evidence) -> json.Json {
  json.object([
    #("role", json.string(evidence_role_name(assessment.evidence_role(value)))),
    #("reference", json.string(assessment.evidence_reference(value))),
  ])
}

fn result_context(value: assessment.Assessment) -> track_context.Context {
  let assert Ok(zone) = time.timezone("America/New_York")
  let calendar_source = assessment.calendar_source(value)
  let assert Ok(context) =
    track_context.new(
      track: finance_track.Us,
      market_scope: "us_ohlcv_gap_assessment",
      venue_mic: {
        let assert Ok(mic) =
          identifier.mic(assessment.venue_mic_name(assessment.venue(value)))
        Some(mic)
      },
      board: Some(assessment.venue_name(assessment.venue(value))),
      timezone: Some(zone),
      source_language: "en-US",
      providers: [
        assessment.provider_name(assessment.provider(value)),
        source.provider(calendar_source),
        "caller_supplied_listing_and_status_receipts",
      ],
      entitlement: "inherits_supplied_receipts",
      limitations: limitations(),
    )
  context
}

fn limitations() -> List(String) {
  [
    "listing_and_status_evidence_is_caller_supplied_and_not_authority_verified",
    "copied_receipt_integrity_is_not_cryptographically_verified",
    "official_planned_calendar_may_be_superseded_by_exchange_alerts",
    "calendar_year_2026_only",
    "provider_omission_requires_complete_pagination_and_explicit_trading_status",
    "classification_only_no_bar_mutation_interpolation_or_synthesis",
    "corporate_actions_adjustments_and_redistribution_not_assessed",
  ]
}

fn error_message(value: query.QueryError) -> String {
  case value {
    query.InvalidInstrumentId ->
      "A safe namespaced instrumentId is required for US gap assessment"
    query.InvalidSymbol -> "An exact uppercase US symbol is required"
    query.InvalidListingInterval(_) -> "The exact listing interval is invalid"
    query.InvalidListingReceipt(_) ->
      "The listing receipt does not match the exact US venue/MIC or evidence contract"
    query.InvalidProviderPlan(_) ->
      "The copied Alpaca date, symbol, feed, or as-of plan is invalid"
    query.SourceReferenceMismatch ->
      "The copied Alpaca sourceReference does not match the exact receipt identity"
    query.InvalidProviderReceipt(_) ->
      "The copied provider receipt contains invalid or duplicate evidence"
    query.InvalidStatusReceipt(_, _) ->
      "A status receipt contains invalid evidence"
    query.InvalidAssessment(assessment.IncompleteProviderCoverage(_)) ->
      "Gap classification requires complete provider pagination"
    query.InvalidAssessment(assessment.MissingStatusReceipt(date)) ->
      "An absent open listing date has no explicit trading or suspension receipt: "
      <> date_text(date)
    query.InvalidAssessment(_) ->
      "US OHLCV evidence conflicts or falls outside the reviewed assessment scope"
  }
}

fn gap_name(value: finance_ohlcv.GapState) -> String {
  case value {
    finance_ohlcv.MarketClosure -> "market_closure"
    finance_ohlcv.Suspension -> "suspension"
    finance_ohlcv.ProviderOmission -> "provider_omission"
    finance_ohlcv.UnavailableHistory -> "unavailable_history"
  }
}

fn status_name(value: assessment.MarketStatus) -> String {
  case value {
    assessment.Trading -> "trading"
    assessment.Suspended -> "suspended"
  }
}

fn evidence_role_name(value: assessment.EvidenceRole) -> String {
  case value {
    assessment.CalendarSchedule -> "calendar_schedule"
    assessment.ListingInterval -> "listing_interval"
    assessment.MarketStatusEvidence -> "market_status"
    assessment.ProviderCoverage -> "provider_coverage"
  }
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn parse_date(value: String) -> Result(time.Date, Nil) {
  case string.split(value, "-") {
    [year, month, day] -> {
      use year <- result.try(int.parse(year) |> result.map_error(fn(_) { Nil }))
      use month <- result.try(
        int.parse(month) |> result.map_error(fn(_) { Nil }),
      )
      use day <- result.try(int.parse(day) |> result.map_error(fn(_) { Nil }))
      time.date(year, month, day) |> result.map_error(fn(_) { Nil })
    }
    _ -> Error(Nil)
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
