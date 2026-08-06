import finance_core/currency
import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_hk_identity/identity as hk_identity
import finance_hk_ohlcv/assessment
import finance_hk_ohlcv/gap_receipt
import finance_listing/effective
import finance_listing/listing
import finance_ohlcv
import finance_ohlcv/gap_assessment
import finance_provenance/hash
import finance_provenance/identity as provenance_identity
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
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
import pi_sparkles_hk_ohlcv_gaps/query

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "hk_ohlcv_gap_assessment",
    "HK OHLCV gap assessment",
    "Classify every absent date in one SHA-256-bound copied Eastmoney Hong Kong daily-bar projection using the exact 2026 HKEX calendar, an independently repeated caller listing identity, explicit status receipts, and complete provider coverage",
    "Compose bounded Hong Kong OHLCV evidence without fetching data, crossing tracks, synthesizing bars, or guessing closures, half-day completeness, suspensions, provider omissions, or unavailable history",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case query.canonical_receipt(input) {
        Error(error) -> tool.reject(error_message(error))
        Ok(canonical) ->
          case hash.text(canonical) {
            Error(_) ->
              tool.reject(
                "The copied HK provider receipt could not be hashed safely",
              )
            Ok(actual_digest) ->
              case query.run(input, actual_digest) {
                Ok(value) ->
                  tool.text_result(
                    render(value),
                    result_json(value, input, actual_digest),
                  )
                  |> promise.resolve
                Error(error) -> tool.reject(error_message(error))
              }
          }
      }
    },
  )
  promise.resolve(Nil)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("venue", schema.string_enum(["hk"])),
    schema.Required("board", schema.string_enum(["main", "gem"])),
    schema.Required(
      "shareClass",
      schema.string_enum(["ordinary_share", "depositary_receipt"]),
    ),
    schema.Required("currency", schema.string_enum(["HKD", "CNY", "USD"])),
    schema.Required("code", bounded_string(5, 5)),
    schema.Required("instrumentId", bounded_string(3, 200)),
    schema.Required("listingStartDate", bounded_string(10, 10)),
    schema.Required("listingEndDate", schema.nullable(bounded_string(10, 10))),
    schema.Required("listingEvidenceReference", bounded_string(1, 2000)),
    schema.Required("providerReceipt", provider_receipt_schema()),
    schema.Required(
      "statusReceipts",
      schema.array(status_schema()) |> schema.with_array_length(0, 366),
    ),
  ])
}

fn provider_receipt_schema() -> schema.Schema {
  schema.object([
    schema.Required("schema", schema.string_enum([gap_receipt.schema_name])),
    schema.Required(
      "schemaVersion",
      schema.integer() |> schema.with_number_range(1.0, 1.0),
    ),
    schema.Required(
      "digestAlgorithm",
      schema.string_enum([gap_receipt.digest_algorithm]),
    ),
    schema.Required("digest", bounded_string(64, 64)),
    schema.Required("provider", schema.string_enum(["eastmoney"])),
    schema.Required("venue", schema.string_enum(["hk"])),
    schema.Required("board", schema.string_enum(["main", "gem"])),
    schema.Required(
      "shareClass",
      schema.string_enum(["ordinary_share", "depositary_receipt"]),
    ),
    schema.Required("currency", schema.string_enum(["HKD", "CNY", "USD"])),
    schema.Required("code", bounded_string(5, 5)),
    schema.Required("startDate", bounded_string(10, 10)),
    schema.Required("endDate", bounded_string(10, 10)),
    schema.Required(
      "limit",
      schema.integer() |> schema.with_number_range(1.0, 1000.0),
    ),
    schema.Required("sourceReference", bounded_string(1, 2000)),
    schema.Required(
      "retrievedAtUnixMilliseconds",
      schema.integer() |> schema.with_number_range(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required(
      "pagination",
      schema.string_enum(["complete", "truncated_by_bar_budget"]),
    ),
    schema.Required(
      "pages",
      schema.array(page_receipt_schema()) |> schema.with_array_length(1, 1),
    ),
    schema.Required(
      "barDates",
      schema.array(bounded_string(10, 10))
        |> schema.with_array_length(0, 366),
    ),
  ])
}

fn page_receipt_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "sequence",
      schema.integer() |> schema.with_number_range(1.0, 1.0),
    ),
    schema.Required("requestId", schema.nullable(bounded_string(1, 200))),
    schema.Required(
      "byteLength",
      schema.integer() |> schema.with_number_range(0.0, 2_000_000.0),
    ),
    schema.Required("contentSha256", bounded_string(64, 64)),
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
  use board <- decode.field("board", board_decoder())
  use share_class <- decode.field("shareClass", share_class_decoder())
  use declared_currency <- decode.field("currency", currency_decoder())
  use code <- decode.field("code", decode.string)
  use instrument_id <- decode.field("instrumentId", decode.string)
  use listing_start <- decode.field("listingStartDate", date_decoder())
  use listing_end <- decode.field(
    "listingEndDate",
    decode.optional(date_decoder()),
  )
  use listing_evidence <- decode.field(
    "listingEvidenceReference",
    decode.string,
  )
  use provider_receipt <- decode.field(
    "providerReceipt",
    provider_receipt_decoder(),
  )
  use statuses <- decode.field(
    "statusReceipts",
    decode.list(of: status_decoder()),
  )
  decode.success(query.Input(
    venue,
    board,
    share_class,
    declared_currency,
    code,
    instrument_id,
    listing_start,
    listing_end,
    listing_evidence,
    provider_receipt,
    statuses,
  ))
}

fn provider_receipt_decoder() -> decode.Decoder(query.ProviderInput) {
  use schema_name <- decode.field("schema", decode.string)
  use schema_version <- decode.field("schemaVersion", decode.int)
  use digest_algorithm <- decode.field("digestAlgorithm", decode.string)
  use digest <- decode.field("digest", decode.string)
  use provider <- decode.field("provider", decode.string)
  use venue <- decode.field("venue", venue_decoder())
  use board <- decode.field("board", board_decoder())
  use share_class <- decode.field("shareClass", share_class_decoder())
  use declared_currency <- decode.field("currency", currency_decoder())
  use code <- decode.field("code", decode.string)
  use start_date <- decode.field("startDate", date_decoder())
  use end_date <- decode.field("endDate", date_decoder())
  use limit <- decode.field("limit", decode.int)
  use source_reference <- decode.field("sourceReference", decode.string)
  use retrieved_at <- decode.field(
    "retrievedAtUnixMilliseconds",
    instant_decoder(),
  )
  use pagination <- decode.field("pagination", pagination_decoder())
  use pages <- decode.field("pages", decode.list(of: page_receipt_decoder()))
  use bar_dates <- decode.field("barDates", decode.list(of: date_decoder()))
  decode.success(query.ProviderInput(
    schema_name,
    schema_version,
    digest_algorithm,
    digest,
    provider,
    venue,
    board,
    share_class,
    declared_currency,
    code,
    start_date,
    end_date,
    limit,
    source_reference,
    retrieved_at,
    pagination,
    pages,
    bar_dates,
  ))
}

fn page_receipt_decoder() -> decode.Decoder(query.PageInput) {
  use sequence <- decode.field("sequence", decode.int)
  use request_id <- decode.field("requestId", decode.optional(decode.string))
  use byte_length <- decode.field("byteLength", decode.int)
  use content_sha256 <- decode.field("contentSha256", decode.string)
  decode.success(query.PageInput(
    sequence,
    request_id,
    byte_length,
    content_sha256,
  ))
}

fn status_decoder() -> decode.Decoder(query.StatusInput) {
  use date <- decode.field("date", date_decoder())
  use status <- decode.field("status", status_decoder_value())
  use evidence <- decode.field("evidenceReference", decode.string)
  decode.success(query.StatusInput(date, status, evidence))
}

fn venue_decoder() -> decode.Decoder(String) {
  use value <- decode.then(decode.string)
  case value {
    "hk" -> decode.success(value)
    _ -> decode.failure("hk", "exact hk venue")
  }
}

fn board_decoder() -> decode.Decoder(hk_identity.Board) {
  use value <- decode.then(decode.string)
  case value {
    "main" -> decode.success(hk_identity.MainBoard)
    "gem" -> decode.success(hk_identity.Gem)
    _ -> decode.failure(hk_identity.MainBoard, "main or gem")
  }
}

fn share_class_decoder() -> decode.Decoder(hk_identity.ShareClass) {
  use value <- decode.then(decode.string)
  case value {
    "ordinary_share" -> decode.success(hk_identity.OrdinaryShare)
    "depositary_receipt" -> decode.success(hk_identity.DepositaryReceipt)
    _ ->
      decode.failure(
        hk_identity.OrdinaryShare,
        "ordinary_share or depositary_receipt",
      )
  }
}

fn currency_decoder() -> decode.Decoder(currency.Currency) {
  use value <- decode.then(decode.string)
  let assert Ok(hkd) = currency.from_code("HKD")
  case currency.from_code(value) {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(hkd, "HKD, CNY, or USD")
  }
}

fn pagination_decoder() -> decode.Decoder(gap_receipt.Pagination) {
  use value <- decode.then(decode.string)
  case value {
    "complete" -> decode.success(gap_receipt.Complete)
    "truncated_by_bar_budget" ->
      decode.success(gap_receipt.TruncatedByBarBudget)
    _ -> decode.failure(gap_receipt.TruncatedByBarBudget, "pagination state")
  }
}

fn status_decoder_value() -> decode.Decoder(gap_assessment.MarketStatus) {
  use value <- decode.then(decode.string)
  case value {
    "trading" -> decode.success(gap_assessment.Trading)
    "suspended" -> decode.success(gap_assessment.Suspended)
    _ -> decode.failure(gap_assessment.Trading, "trading or suspended status")
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

fn instant_decoder() -> decode.Decoder(time.Instant) {
  use value <- decode.then(decode.int)
  let assert Ok(placeholder) = time.instant(0)
  case time.instant(value) {
    Ok(instant) -> decode.success(instant)
    Error(_) -> decode.failure(placeholder, "non-negative Unix milliseconds")
  }
}

fn render(value: assessment.Assessment) -> String {
  let classification = assessment.classification(value)
  "HK track | HKEX OHLCV gaps | "
  <> int.to_string(gap_assessment.assessed_date_count(classification))
  <> " dates structurally classified from supplied receipts | "
  <> int.to_string(list.length(gap_assessment.gaps(classification)))
  <> " absent dates"
}

fn result_json(
  value: assessment.Assessment,
  input: query.Input,
  actual_digest: provenance_identity.Sha256,
) -> json.Json {
  let listing_receipt = assessment.listing_receipt_value(value)
  let listing_value = assessment.listing(listing_receipt)
  let key = hk_identity.key(listing_value)
  let interval = assessment.listing_interval(listing_receipt)
  let classification = assessment.classification(value)
  let provider = gap_assessment.provider(classification)
  let provider_input = input.provider_receipt
  let calendar_source = assessment.calendar_source(value)
  json.object(
    list.append(track_json.result_fields(result_context(value)), [
      #("venue", json.string("hk")),
      #(
        "listing",
        json.object([
          #(
            "instrumentId",
            json.string(
              key |> listing.instrument_id |> identifier.instrument_id_value,
            ),
          ),
          #("code", json.string(hk_identity.code(listing_value))),
          #("mic", json.string(key |> listing.mic |> identifier.mic_value)),
          #(
            "board",
            json.string(
              gap_receipt.board_name(hk_identity.board(listing_value)),
            ),
          ),
          #(
            "shareClass",
            json.string(
              gap_receipt.share_class_name(hk_identity.share_class(
                listing_value,
              )),
            ),
          ),
          #(
            "currency",
            json.string(listing_value |> hk_identity.currency |> currency.code),
          ),
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
          #("scheduleKind", json.string("planned_hk_securities")),
          #(
            "halfDayDates",
            json.array(assessment.calendar_half_day_dates(value), fn(date) {
              date |> date_text |> json.string
            }),
          ),
        ]),
      ),
      #(
        "providerReceipt",
        json.object([
          #("schema", json.string(provider_input.schema)),
          #("schemaVersion", json.int(provider_input.schema_version)),
          #("digestAlgorithm", json.string(provider_input.digest_algorithm)),
          #("digest", json.string(provider_input.digest)),
          #("provider", json.string(gap_assessment.provider_name(provider))),
          #(
            "sourceReference",
            json.string(gap_assessment.provider_source_reference(provider)),
          ),
          #(
            "requestIds",
            json.array(
              gap_assessment.provider_request_ids(provider),
              json.string,
            ),
          ),
          #("pagination", json.string("complete")),
          #(
            "retrievedAtUnixMilliseconds",
            json.int(time.unix_milliseconds(provider_input.retrieved_at)),
          ),
          #("pages", json.array(provider_input.pages, provider_page_json)),
          #(
            "integrity",
            json.object([
              #("state", json.string("sha256_content_match")),
              #("scope", json.string("canonical_hk_gap_projection_v1")),
              #(
                "actualDigest",
                json.string(provenance_identity.sha256_value(actual_digest)),
              ),
              #("providerAuthenticated", json.bool(False)),
            ]),
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
            json.int(
              list.length(gap_assessment.returned_bar_dates(classification)),
            ),
          ),
          #(
            "absentDates",
            json.int(list.length(gap_assessment.gaps(classification))),
          ),
        ]),
      ),
      #(
        "barDates",
        json.array(gap_assessment.returned_bar_dates(classification), fn(date) {
          json.string(date_text(date))
        }),
      ),
      #(
        "statusReceipts",
        json.array(gap_assessment.statuses(classification), status_json),
      ),
      #("gaps", json.array(gap_assessment.gaps(classification), gap_json)),
      #("limitations", json.array(limitations(), json.string)),
    ]),
  )
}

fn provider_page_json(value: query.PageInput) -> json.Json {
  let query.PageInput(sequence, request_id, byte_length, content_sha256) = value
  json.object([
    #("sequence", json.int(sequence)),
    #("requestId", json.nullable(request_id, json.string)),
    #("byteLength", json.int(byte_length)),
    #("contentSha256", json.string(content_sha256)),
  ])
}

fn status_json(value: gap_assessment.StatusReceipt) -> json.Json {
  json.object([
    #("date", json.string(date_text(gap_assessment.status_date(value)))),
    #("status", json.string(status_name(gap_assessment.market_status(value)))),
    #(
      "evidenceReference",
      json.string(gap_assessment.status_evidence_reference(value)),
    ),
    #("evidenceStatus", json.string("caller_supplied_unverified")),
  ])
}

fn gap_json(value: gap_assessment.ClassifiedGap) -> json.Json {
  json.object([
    #("sessionDate", json.string(date_text(gap_assessment.gap_date(value)))),
    #("state", json.string(gap_name(gap_assessment.gap_state(value)))),
    #("evidence", json.array(gap_assessment.gap_evidence(value), evidence_json)),
  ])
}

fn evidence_json(value: gap_assessment.Evidence) -> json.Json {
  json.object([
    #(
      "role",
      json.string(evidence_role_name(gap_assessment.evidence_role(value))),
    ),
    #("reference", json.string(gap_assessment.evidence_reference(value))),
  ])
}

fn result_context(value: assessment.Assessment) -> track_context.Context {
  let calendar_source = assessment.calendar_source(value)
  let listing_value =
    value |> assessment.listing_receipt_value |> assessment.listing
  let assert Ok(context) =
    track_context.new(
      track: finance_track.Hk,
      market_scope: "hk_ohlcv_gap_assessment",
      venue_mic: Some(hk_identity.venue_mic()),
      board: Some(gap_receipt.board_name(hk_identity.board(listing_value))),
      timezone: Some({
        let assert Ok(zone) = time.timezone("Asia/Hong_Kong")
        zone
      }),
      source_language: "zh-HK",
      providers: [
        gap_assessment.provider_name(
          value |> assessment.classification |> gap_assessment.provider,
        ),
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
    "sha256_content_match_is_not_a_provider_signature_or_authentication",
    "digest_scope_is_the_gap_projection_not_full_bar_value_replay",
    "eastmoney_origin_is_vendor_not_hkex_evidence",
    "official_planned_calendar_may_be_superseded_by_exchange_alerts",
    "half_day_schedule_is_retained_but_intraday_completeness_is_not_assessed",
    "calendar_year_2026_only",
    "provider_omission_requires_complete_coverage_and_explicit_trading_status",
    "classification_only_no_bar_mutation_interpolation_or_synthesis",
    "volume_amount_turnover_adjustments_and_redistribution_not_assessed",
  ]
}

fn error_message(value: query.QueryError) -> String {
  case value {
    query.InvalidVenue -> "The HK receipt venue must remain exactly hk"
    query.InvalidInstrumentId ->
      "A safe namespaced instrumentId is required for HK gap assessment"
    query.InvalidListingIdentity(_) ->
      "The HK board, share class, currency, or code identity is invalid"
    query.InvalidListingInterval(_) -> "The exact listing interval is invalid"
    query.InvalidListingReceipt(_) ->
      "The listing receipt does not satisfy the HK evidence contract"
    query.InvalidReceiptEnvelope ->
      "The copied HK provider receipt schema, version, algorithm, or provider is invalid"
    query.InvalidContentHash(_)
    | query.InvalidPageReceipt(_, _)
    | query.InvalidGapReceipt(_) ->
      "The copied HK provider receipt page or canonical content is invalid"
    query.InvalidReceiptDigest ->
      "The copied HK provider receipt digest is not a valid SHA-256 value"
    query.ReceiptDigestMismatch ->
      "The copied HK provider receipt does not match its canonical SHA-256 digest"
    query.ProviderIdentityMismatch ->
      "The independent HK listing identity does not match the provider projection"
    query.InvalidProviderPlan(_) ->
      "The copied Eastmoney HK range, code, or row limit is invalid"
    query.SourceReferenceMismatch ->
      "The copied Eastmoney sourceReference does not match the exact receipt identity"
    query.InvalidProviderReceipt(_) ->
      "The copied provider receipt contains invalid or duplicate evidence"
    query.InvalidStatusReceipt(_, _) ->
      "An HK status receipt contains invalid evidence"
    query.InvalidAssessment(assessment.InvalidAssessment(gap_assessment.IncompleteProviderCoverage(
      _,
    ))) -> "HK gap classification requires complete provider coverage"
    query.InvalidAssessment(assessment.InvalidAssessment(gap_assessment.MissingStatusReceipt(
      date,
    ))) ->
      "An absent open Hong Kong listing date has no explicit trading or suspension receipt: "
      <> date_text(date)
    query.InvalidAssessment(_) ->
      "HK OHLCV evidence conflicts or falls outside the reviewed assessment scope"
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

fn status_name(value: gap_assessment.MarketStatus) -> String {
  case value {
    gap_assessment.Trading -> "trading"
    gap_assessment.Suspended -> "suspended"
  }
}

fn evidence_role_name(value: gap_assessment.EvidenceRole) -> String {
  case value {
    gap_assessment.CalendarSchedule -> "calendar_schedule"
    gap_assessment.ListingInterval -> "listing_interval"
    gap_assessment.MarketStatusEvidence -> "market_status"
    gap_assessment.ProviderCoverage -> "provider_coverage"
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
