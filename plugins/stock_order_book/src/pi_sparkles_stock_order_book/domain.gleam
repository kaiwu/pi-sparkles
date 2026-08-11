import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/market
import finance_core/observation
import finance_core/source
import finance_core/time
import finance_provenance/evidence
import finance_provenance/hash
import finance_provenance/identity
import finance_provenance/redact
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_stock_order_book/decode

const maximum_safe_integer = 9_007_199_254_740_991

const maximum_sources = 25

const maximum_reports = 100

const maximum_alternatives = 10

const maximum_page_size = 50

pub opaque type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
}

type SafeSource {
  SafeSource(value: source.SourceRef, reference_redacted: Bool)
}

type Listing {
  Listing(
    listing_id: String,
    mic: identifier.Mic,
    symbol: String,
    currency: currency.Currency,
  )
}

type SourceRecord {
  SourceRecord(
    source_id: String,
    safe: SafeSource,
    kind: source.SourceKind,
    feed: String,
    entitlement: observation.Entitlement,
    licence: evidence.Licence,
    receipt_hash: String,
  )
}

type Venue {
  Venue(kind: String, code: String)
}

type Candidate {
  Candidate(
    raw_price: String,
    normalized_price: decimal.Decimal,
    raw_size: String,
    normalized_size: decimal.Decimal,
    venue: Venue,
  )
}

type Alternative {
  Alternative(candidate: Candidate, evidence_id: String)
}

type SideState {
  ObservedSide(candidate: Candidate)
  UnavailableSide(reason: String)
  ConflictingSide(reason: String, alternatives: List(Alternative))
}

type ExchangeTime {
  ReportedExchangeTime(unix_milliseconds: Int, source_lexeme: String)
  UnknownExchangeTime(reason: String)
}

type SequenceState {
  ReportedSequence(value: Int, scope: String)
  UnknownSequence(reason: String)
}

type GapState {
  NoGapReported
  SequenceGap(from_sequence: Int, to_sequence: Int)
  SequenceReset(previous_sequence: Int, reset_at_sequence: Int)
  UnknownGap(reason: String)
}

type Aggregation {
  Aggregation(
    kind: String,
    venues: List(Venue),
    coverage: String,
    method_label: Option(String),
    reason: Option(String),
  )
}

type SizeUnit {
  SizeUnit(kind: String, label: Option(String), reason: Option(String))
}

type TopOfBook {
  TopOfBook(
    currency: currency.Currency,
    provider_timestamp: String,
    exchange_time: ExchangeTime,
    sequence: SequenceState,
    gap: GapState,
    aggregation: Aggregation,
    size_unit: SizeUnit,
    condition_codes: List(String),
    bid: SideState,
    ask: SideState,
  )
}

type Report {
  Report(
    report_id: String,
    source_record: SourceRecord,
    observed: observation.Observation(TopOfBook),
    currency_matches_listing: Bool,
  )
}

type Counts {
  Counts(
    reports: Int,
    fully_observed: Int,
    bids_observed: Int,
    bids_unavailable: Int,
    bids_conflicting: Int,
    asks_observed: Int,
    asks_unavailable: Int,
    asks_conflicting: Int,
    sequences_reported: Int,
    gaps_reported: Int,
    resets_reported: Int,
  )
}

type Page {
  Page(offset: Int, limit: Int)
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> Json {
  value.details
}

pub fn error_message(value: DomainError) -> String {
  let InvalidField(field, reason) = value
  "Invalid exact stock-order-book field " <> field <> ": " <> reason
}

pub fn run(input: decode.Input) -> Result(Response, DomainError) {
  use track <- result.try(parse_track(input.track))
  use listing <- result.try(parse_listing(input.listing, track))
  use _ <- result.try(count_range("sources", input.sources, 1, maximum_sources))
  use _ <- result.try(count_range("reports", input.reports, 1, maximum_reports))
  use sources <- result.try(prepare_sources(input.sources, 0, []))
  use _ <- result.try(validate_unique_sources(sources))
  use reports <- result.try(
    prepare_reports(input.reports, sources, track, listing, 0, []),
  )
  use _ <- result.try(validate_unique_reports(reports))
  use page <- result.try(parse_page(input.page))
  let counts = count_reports(reports)
  let selected = reports |> list.drop(page.offset) |> list.take(page.limit)
  let returned = list.length(selected)
  let next_offset = case page.offset + returned < counts.reports {
    True -> Some(page.offset + returned)
    False -> None
  }
  let limitations = limitations()
  use context <- result.try(
    track_context.new(
      track: track,
      market_scope: finance_track.name(track) <> "_stock_order_book",
      venue_mic: Some(listing.mic),
      board: None,
      timezone: Some(market_timezone(track)),
      source_language: source_language(track),
      providers: unique_providers(sources),
      entitlement: "mixed_caller_declared",
      limitations: limitations,
    )
    |> result.map_error(fn(error) {
      InvalidField("trackContext", string.inspect(error))
    }),
  )
  let receipt_projection =
    json.object([
      #("track", json.string(finance_track.name(track))),
      #("listing", listing_json(listing)),
      #("sources", json.array(sources, source_receipt_json)),
      #("reports", json.array(reports, report_receipt_json)),
    ])
  let assert Ok(calculation_receipt) =
    receipt_projection |> json.to_string |> hash.text
  Ok(Response(
    finance_track.name(track)
      <> " top of book | "
      <> listing.symbol
      <> " @ "
      <> identifier.mic_value(listing.mic)
      <> " | "
      <> int.to_string(counts.reports)
      <> " reports / "
      <> int.to_string(counts.fully_observed)
      <> " fully observed",
    json.object(
      list.append(track_json.result_fields(context), [
        #("schemaVersion", json.int(1)),
        #("operation", json.string("stock_top_of_book")),
        #("listing", listing_json(listing)),
        #("summary", counts_json(counts)),
        #(
          "page",
          json.object([
            #("offset", json.int(page.offset)),
            #("limit", json.int(page.limit)),
            #("returned", json.int(returned)),
            #("total", json.int(counts.reports)),
            #("nextOffset", json.nullable(next_offset, json.int)),
            #("order", json.string("caller_supplied_report_order")),
          ]),
        ),
        #("reports", json.array(selected, report_json)),
        #("sources", json.array(sources, source_record_json)),
        #(
          "calculation",
          json.object([
            #("reportMerge", json.string("not_performed")),
            #("sourceSelection", json.string("not_performed")),
            #("spreadOrMidpoint", json.string("not_performed")),
            #("gapRepair", json.string("not_performed")),
            #("depthReconstruction", json.string("not_performed")),
            #(
              "receiptHash",
              json.string(identity.sha256_value(calculation_receipt)),
            ),
          ]),
        ),
        #(
          "liquidityWarning",
          json.object([
            #("displayedOnly", json.bool(True)),
            #("hiddenLiquidityKnown", json.bool(False)),
            #("durabilityClaim", json.bool(False)),
            #("executablePricePromise", json.bool(False)),
            #("fillPrediction", json.bool(False)),
          ]),
        ),
        #(
          "unknownFacts",
          json.array(
            [
              "listing_and_venue_identity_authority",
              "source_receipt_origin_authentication",
              "licence_and_entitlement_verification",
              "clock_synchronization_and_latency",
              "aggregation_completeness_and_nbbo_status",
              "sequence_continuity_beyond_declared_gap_state",
              "displayed_liquidity_durability_and_hidden_liquidity",
              "source_correctness_or_preference",
            ],
            json.string,
          ),
        ),
        #(
          "assessmentStatus",
          json.string("reported_top_of_book_facts_only_no_execution_verdict"),
        ),
        #("decisionOwner", json.string("llm")),
        #(
          "pluginDecisionFields",
          json.array([], fn(value: String) { json.string(value) }),
        ),
        #("limitations", json.array(limitations, json.string)),
      ]),
    ),
  ))
}

fn parse_track(value: String) -> Result(finance_track.Track, DomainError) {
  finance_track.from_name(value)
  |> result.map_error(fn(_) {
    InvalidField("track", "expected exactly cn, hk, or us")
  })
}

fn parse_listing(
  value: decode.ListingInput,
  track: finance_track.Track,
) -> Result(Listing, DomainError) {
  use listing_id <- result.try(bounded_text(
    "listing.listingId",
    value.listing_id,
    2000,
  ))
  use mic <- result.try(parse_mic("listing.mic", value.mic))
  use _ <- result.try(validate_track_mic(track, mic, "listing.mic"))
  use symbol <- result.try(symbol_text("listing.symbol", value.symbol))
  use listing_currency <- result.try(parse_currency(
    "listing.currency",
    value.currency,
  ))
  Ok(Listing(listing_id, mic, symbol, listing_currency))
}

fn prepare_sources(
  remaining: List(decode.SourceInput),
  index: Int,
  reversed: List(SourceRecord),
) -> Result(List(SourceRecord), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      let field = "sources[" <> int.to_string(index) <> "]"
      use source_id <- result.try(bounded_text(
        field <> ".sourceId",
        value.source_id,
        200,
      ))
      use provider <- result.try(bounded_text(
        field <> ".provider",
        value.provider,
        200,
      ))
      use feed <- result.try(bounded_text(field <> ".feed", value.feed, 200))
      use kind <- result.try(parse_source_kind(value, field))
      use safe <- result.try(make_safe_source(
        provider,
        value.reference,
        kind,
        field,
      ))
      use entitlement <- result.try(parse_entitlement(
        value.entitlement,
        field <> ".entitlement",
      ))
      use licence <- result.try(parse_licence(
        value.licence,
        field <> ".licence",
      ))
      use receipt <- result.try(sha(field <> ".receiptHash", value.receipt_hash))
      prepare_sources(rest, index + 1, [
        SourceRecord(
          source_id,
          safe,
          kind,
          feed,
          entitlement,
          licence,
          identity.sha256_value(receipt),
        ),
        ..reversed
      ])
    }
  }
}

fn validate_unique_sources(
  values: List(SourceRecord),
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case list.any(rest, fn(other) { other.source_id == current.source_id }) {
        True -> Error(InvalidField("sources", "sourceId values must be unique"))
        False -> validate_unique_sources(rest)
      }
  }
}

fn prepare_reports(
  remaining: List(decode.ReportInput),
  sources: List(SourceRecord),
  track: finance_track.Track,
  listing: Listing,
  index: Int,
  reversed: List(Report),
) -> Result(List(Report), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use report <- result.try(prepare_report(
        value,
        sources,
        track,
        listing,
        index,
      ))
      prepare_reports(rest, sources, track, listing, index + 1, [
        report,
        ..reversed
      ])
    }
  }
}

fn prepare_report(
  value: decode.ReportInput,
  sources: List(SourceRecord),
  track: finance_track.Track,
  listing: Listing,
  index: Int,
) -> Result(Report, DomainError) {
  let field = "reports[" <> int.to_string(index) <> "]"
  use report_id <- result.try(bounded_text(
    field <> ".reportId",
    value.report_id,
    500,
  ))
  use source_id <- result.try(bounded_text(
    field <> ".sourceId",
    value.source_id,
    200,
  ))
  use source_record <- result.try(find_source(source_id, sources, field))
  use report_currency <- result.try(parse_currency(
    field <> ".currency",
    value.currency,
  ))
  use provider_timestamp <- result.try(bounded_text(
    field <> ".providerTimestamp",
    value.provider_timestamp,
    500,
  ))
  use provider_time <- result.try(instant(
    field <> ".providerTimeUnixMilliseconds",
    value.provider_time_unix_ms,
  ))
  use received_at <- result.try(instant(
    field <> ".receivedAtUnixMilliseconds",
    value.received_at_unix_ms,
  ))
  use _ <- result.try(
    case value.provider_time_unix_ms <= value.received_at_unix_ms {
      True -> Ok(Nil)
      False ->
        Error(InvalidField(
          field <> ".receivedAtUnixMilliseconds",
          "must not precede providerTimeUnixMilliseconds",
        ))
    },
  )
  use exchange_time <- result.try(parse_exchange_time(
    value.exchange_time,
    field <> ".exchangeTime",
  ))
  use sequence <- result.try(parse_sequence(
    value.sequence,
    field <> ".sequence",
  ))
  use gap <- result.try(parse_gap(value.gap, field <> ".gap"))
  use aggregation <- result.try(parse_aggregation(
    value.aggregation,
    track,
    field <> ".aggregation",
  ))
  use size_unit <- result.try(parse_size_unit(
    value.size_unit,
    field <> ".sizeUnit",
  ))
  use condition_codes <- result.try(parse_condition_codes(
    value.condition_codes,
    field <> ".conditionCodes",
  ))
  use bid <- result.try(parse_side(value.bid, track, field <> ".bid"))
  use ask <- result.try(parse_side(value.ask, track, field <> ".ask"))
  use _ <- result.try(validate_side_venues(bid, aggregation, field <> ".bid"))
  use _ <- result.try(validate_side_venues(ask, aggregation, field <> ".ask"))
  let book =
    TopOfBook(
      report_currency,
      provider_timestamp,
      exchange_time,
      sequence,
      gap,
      aggregation,
      size_unit,
      condition_codes,
      bid,
      ask,
    )
  let quality = case bid, ask {
    UnavailableSide(_), UnavailableSide(_) ->
      observation.Missing(observation.Unavailable)
    _, _ -> observation.Reported
  }
  let observed =
    observation.Observation(
      value: book,
      as_of: provider_time,
      retrieved_at: received_at,
      timezone: Some(market_timezone(track)),
      source: source_record.safe.value,
      evidence_id: Some(source_record.receipt_hash),
      freshness: observation.UnknownFreshness,
      entitlement: source_record.entitlement,
      quality: quality,
      unit: Some(market.CurrencyPerShare(report_currency)),
      adjustment: None,
      session: None,
    )
  Ok(Report(
    report_id,
    source_record,
    observed,
    currency.code(report_currency) == currency.code(listing.currency),
  ))
}

fn validate_unique_reports(values: List(Report)) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case list.any(rest, fn(other) { other.report_id == current.report_id }) {
        True -> Error(InvalidField("reports", "reportId values must be unique"))
        False -> validate_unique_reports(rest)
      }
  }
}

fn parse_exchange_time(
  value: decode.ExchangeTimeInput,
  field: String,
) -> Result(ExchangeTime, DomainError) {
  case value.state, value.unix_milliseconds, value.source_lexeme, value.reason {
    "reported", Some(unix_milliseconds), Some(source_lexeme), None -> {
      use _ <- result.try(integer_range(
        field <> ".unixMilliseconds",
        unix_milliseconds,
        0,
        maximum_safe_integer,
      ))
      use exact <- result.try(bounded_text(
        field <> ".sourceLexeme",
        source_lexeme,
        500,
      ))
      Ok(ReportedExchangeTime(unix_milliseconds, exact))
    }
    "unknown", None, None, Some(reason) -> {
      use exact <- result.try(bounded_text(field <> ".reason", reason, 500))
      Ok(UnknownExchangeTime(exact))
    }
    _, _, _, _ ->
      Error(InvalidField(
        field,
        "reported requires unixMilliseconds and sourceLexeme only; unknown requires reason only",
      ))
  }
}

fn parse_sequence(
  value: decode.SequenceInput,
  field: String,
) -> Result(SequenceState, DomainError) {
  case value.state, value.value, value.scope, value.reason {
    "reported", Some(number), "listing", None
    | "reported", Some(number), "feed_global", None
    -> {
      use _ <- result.try(integer_range(
        field <> ".value",
        number,
        0,
        maximum_safe_integer,
      ))
      Ok(ReportedSequence(number, value.scope))
    }
    "unknown", None, "unknown", Some(reason) -> {
      use exact <- result.try(bounded_text(field <> ".reason", reason, 500))
      Ok(UnknownSequence(exact))
    }
    _, _, _, _ ->
      Error(InvalidField(
        field,
        "reported requires value and listing or feed_global scope only; unknown requires unknown scope and reason only",
      ))
  }
}

fn parse_gap(
  value: decode.GapInput,
  field: String,
) -> Result(GapState, DomainError) {
  case value.state, value.from_sequence, value.to_sequence, value.reason {
    "no_gap_reported", None, None, None -> Ok(NoGapReported)
    "sequence_gap", Some(from_sequence), Some(to_sequence), None -> {
      use _ <- result.try(integer_range(
        field <> ".fromSequence",
        from_sequence,
        0,
        maximum_safe_integer,
      ))
      use _ <- result.try(integer_range(
        field <> ".toSequence",
        to_sequence,
        0,
        maximum_safe_integer,
      ))
      case from_sequence <= to_sequence {
        True -> Ok(SequenceGap(from_sequence, to_sequence))
        False ->
          Error(InvalidField(
            field,
            "sequence_gap fromSequence must not exceed toSequence",
          ))
      }
    }
    "sequence_reset", Some(previous), Some(reset_at), None -> {
      use _ <- result.try(integer_range(
        field <> ".fromSequence",
        previous,
        0,
        maximum_safe_integer,
      ))
      use _ <- result.try(integer_range(
        field <> ".toSequence",
        reset_at,
        0,
        maximum_safe_integer,
      ))
      Ok(SequenceReset(previous, reset_at))
    }
    "unknown", None, None, Some(reason) -> {
      use exact <- result.try(bounded_text(field <> ".reason", reason, 500))
      Ok(UnknownGap(exact))
    }
    _, _, _, _ ->
      Error(InvalidField(
        field,
        "no_gap_reported forbids details; sequence_gap and sequence_reset require from/to only; unknown requires reason only",
      ))
  }
}

fn parse_aggregation(
  value: decode.AggregationInput,
  track: finance_track.Track,
  field: String,
) -> Result(Aggregation, DomainError) {
  use coverage <- result.try(parse_coverage(
    value.coverage,
    field <> ".coverage",
  ))
  use _ <- result.try(count_range(field <> ".venues", value.venues, 0, 25))
  use venues <- result.try(
    prepare_venues(value.venues, track, field <> ".venues", 0, []),
  )
  use _ <- result.try(validate_unique_venues(venues, field <> ".venues"))
  case value.kind, venues, value.method_label, value.reason, coverage {
    "single_venue", [_], None, None, _ ->
      Ok(Aggregation("single_venue", venues, coverage, None, None))
    "consolidated", [_, ..], None, None, _ ->
      Ok(Aggregation("consolidated", venues, coverage, None, None))
    "provider_defined", [_, ..], Some(label), None, _ -> {
      use exact <- result.try(bounded_text(field <> ".methodLabel", label, 500))
      Ok(Aggregation("provider_defined", venues, coverage, Some(exact), None))
    }
    "unknown", [], None, Some(reason), "unknown" -> {
      use exact <- result.try(bounded_text(field <> ".reason", reason, 500))
      Ok(Aggregation("unknown", [], "unknown", None, Some(exact)))
    }
    _, _, _, _, _ ->
      Error(InvalidField(
        field,
        "single_venue requires exactly one venue; consolidated requires venues; provider_defined requires venues and methodLabel; unknown requires unknown coverage and reason only",
      ))
  }
}

fn parse_coverage(value: String, field: String) -> Result(String, DomainError) {
  case
    list.contains(["declared_complete", "declared_partial", "unknown"], value)
  {
    True -> Ok(value)
    False -> Error(InvalidField(field, "unsupported aggregation coverage"))
  }
}

fn prepare_venues(
  remaining: List(decode.VenueInput),
  track: finance_track.Track,
  field: String,
  index: Int,
  reversed: List(Venue),
) -> Result(List(Venue), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use venue <- result.try(parse_venue(
        value,
        track,
        field <> "[" <> int.to_string(index) <> "]",
      ))
      prepare_venues(rest, track, field, index + 1, [venue, ..reversed])
    }
  }
}

fn parse_venue(
  value: decode.VenueInput,
  track: finance_track.Track,
  field: String,
) -> Result(Venue, DomainError) {
  case value.kind {
    "mic" -> {
      use mic <- result.try(parse_mic(field <> ".code", value.code))
      use _ <- result.try(validate_track_mic(track, mic, field <> ".code"))
      Ok(Venue("mic", identifier.mic_value(mic)))
    }
    "provider_code" -> {
      use code <- result.try(symbol_text(field <> ".code", value.code))
      Ok(Venue("provider_code", code))
    }
    _ -> Error(InvalidField(field <> ".kind", "expected mic or provider_code"))
  }
}

fn validate_unique_venues(
  values: List(Venue),
  field: String,
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case list.any(rest, fn(other) { venue_equal(current, other) }) {
        True -> Error(InvalidField(field, "venue entries must be unique"))
        False -> validate_unique_venues(rest, field)
      }
  }
}

fn parse_size_unit(
  value: decode.SizeUnitInput,
  field: String,
) -> Result(SizeUnit, DomainError) {
  case value.kind, value.label, value.reason {
    "shares", None, None -> Ok(SizeUnit("shares", None, None))
    "round_lots", None, None -> Ok(SizeUnit("round_lots", None, None))
    "provider_units", Some(label), None -> {
      use exact <- result.try(bounded_text(field <> ".label", label, 200))
      Ok(SizeUnit("provider_units", Some(exact), None))
    }
    "unknown", None, Some(reason) -> {
      use exact <- result.try(bounded_text(field <> ".reason", reason, 500))
      Ok(SizeUnit("unknown", None, Some(exact)))
    }
    _, _, _ ->
      Error(InvalidField(
        field,
        "shares and round_lots forbid details; provider_units requires label; unknown requires reason",
      ))
  }
}

fn parse_condition_codes(
  values: List(String),
  field: String,
) -> Result(List(String), DomainError) {
  use _ <- result.try(count_range(field, values, 0, 100))
  prepare_condition_codes(values, field, 0, [])
}

fn prepare_condition_codes(
  remaining: List(String),
  field: String,
  index: Int,
  reversed: List(String),
) -> Result(List(String), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use exact <- result.try(bounded_text(
        field <> "[" <> int.to_string(index) <> "]",
        value,
        200,
      ))
      prepare_condition_codes(rest, field, index + 1, [exact, ..reversed])
    }
  }
}

fn parse_side(
  value: decode.SideInput,
  track: finance_track.Track,
  field: String,
) -> Result(SideState, DomainError) {
  case value.state, value.candidate, value.reason, value.alternatives {
    "observed", Some(candidate), None, [] -> {
      use parsed <- result.try(parse_candidate(
        candidate,
        track,
        field <> ".candidate",
      ))
      Ok(ObservedSide(parsed))
    }
    "unavailable", None, Some(reason), [] -> {
      use exact <- result.try(bounded_text(field <> ".reason", reason, 500))
      Ok(UnavailableSide(exact))
    }
    "conflicting", None, Some(reason), alternatives -> {
      use exact_reason <- result.try(bounded_text(
        field <> ".reason",
        reason,
        500,
      ))
      use _ <- result.try(count_range(
        field <> ".alternatives",
        alternatives,
        2,
        maximum_alternatives,
      ))
      use parsed <- result.try(
        prepare_alternatives(
          alternatives,
          track,
          field <> ".alternatives",
          0,
          [],
        ),
      )
      use _ <- result.try(validate_distinct_alternatives(
        parsed,
        field <> ".alternatives",
      ))
      Ok(ConflictingSide(exact_reason, parsed))
    }
    _, _, _, _ ->
      Error(InvalidField(
        field,
        "observed requires candidate only; unavailable requires reason only; conflicting requires reason and two to ten alternatives",
      ))
  }
}

fn parse_candidate(
  value: decode.CandidateInput,
  track: finance_track.Track,
  field: String,
) -> Result(Candidate, DomainError) {
  use raw_price <- result.try(bounded_text(
    field <> ".rawPrice",
    value.raw_price,
    500,
  ))
  use normalized_price <- result.try(non_negative_decimal(
    field <> ".rawPrice",
    raw_price,
  ))
  use raw_size <- result.try(bounded_text(
    field <> ".rawSize",
    value.raw_size,
    500,
  ))
  use normalized_size <- result.try(non_negative_decimal(
    field <> ".rawSize",
    raw_size,
  ))
  use venue <- result.try(parse_venue(value.venue, track, field <> ".venue"))
  Ok(Candidate(raw_price, normalized_price, raw_size, normalized_size, venue))
}

fn prepare_alternatives(
  remaining: List(decode.AlternativeInput),
  track: finance_track.Track,
  field: String,
  index: Int,
  reversed: List(Alternative),
) -> Result(List(Alternative), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      let item_field = field <> "[" <> int.to_string(index) <> "]"
      use candidate <- result.try(parse_candidate(
        decode.CandidateInput(value.raw_price, value.raw_size, value.venue),
        track,
        item_field,
      ))
      use evidence_id <- result.try(sha(
        item_field <> ".evidenceId",
        value.evidence_id,
      ))
      prepare_alternatives(rest, track, field, index + 1, [
        Alternative(candidate, identity.sha256_value(evidence_id)),
        ..reversed
      ])
    }
  }
}

fn validate_distinct_alternatives(
  values: List(Alternative),
  field: String,
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] -> {
      let duplicate_candidate =
        list.any(rest, fn(other) {
          candidate_signature(other.candidate)
          == candidate_signature(current.candidate)
        })
      let duplicate_evidence =
        list.any(rest, fn(other) { other.evidence_id == current.evidence_id })
      case duplicate_candidate || duplicate_evidence {
        True ->
          Error(InvalidField(
            field,
            "conflicting alternatives require distinct candidates and evidenceId values",
          ))
        False -> validate_distinct_alternatives(rest, field)
      }
    }
  }
}

fn validate_side_venues(
  value: SideState,
  aggregation: Aggregation,
  field: String,
) -> Result(Nil, DomainError) {
  case aggregation.kind {
    "unknown" -> Ok(Nil)
    _ -> {
      let candidates = case value {
        ObservedSide(candidate) -> [candidate]
        UnavailableSide(_) -> []
        ConflictingSide(_, alternatives) ->
          list.map(alternatives, fn(alternative) { alternative.candidate })
      }
      case
        list.all(candidates, fn(candidate) {
          list.any(aggregation.venues, fn(venue) {
            venue_equal(candidate.venue, venue)
          })
        })
      {
        True -> Ok(Nil)
        False ->
          Error(InvalidField(
            field,
            "every candidate venue must occur in the declared aggregation venue set",
          ))
      }
    }
  }
}

fn venue_equal(left: Venue, right: Venue) -> Bool {
  left.kind == right.kind && left.code == right.code
}

fn candidate_signature(value: Candidate) -> String {
  value.raw_price
  <> "\u{1f}"
  <> value.raw_size
  <> "\u{1f}"
  <> value.venue.kind
  <> "\u{1f}"
  <> value.venue.code
}

fn non_negative_decimal(
  field: String,
  value: String,
) -> Result(decimal.Decimal, DomainError) {
  use parsed <- result.try(
    decimal.parse(value)
    |> result.map_error(fn(_) {
      InvalidField(field, "expected an exact decimal source lexeme")
    }),
  )
  case decimal.compare(parsed, decimal.zero()) {
    Lt -> Error(InvalidField(field, "decimal must be non-negative"))
    Eq | Gt -> Ok(parsed)
  }
}

fn count_reports(values: List(Report)) -> Counts {
  list.fold(values, Counts(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0), fn(counts, report) {
    let book = report.observed.value
    let counted = Counts(..counts, reports: counts.reports + 1)
    let counted = case book.bid {
      ObservedSide(_) ->
        Counts(..counted, bids_observed: counted.bids_observed + 1)
      UnavailableSide(_) ->
        Counts(..counted, bids_unavailable: counted.bids_unavailable + 1)
      ConflictingSide(_, _) ->
        Counts(..counted, bids_conflicting: counted.bids_conflicting + 1)
    }
    let counted = case book.ask {
      ObservedSide(_) ->
        Counts(..counted, asks_observed: counted.asks_observed + 1)
      UnavailableSide(_) ->
        Counts(..counted, asks_unavailable: counted.asks_unavailable + 1)
      ConflictingSide(_, _) ->
        Counts(..counted, asks_conflicting: counted.asks_conflicting + 1)
    }
    let counted = case book.bid, book.ask {
      ObservedSide(_), ObservedSide(_) ->
        Counts(..counted, fully_observed: counted.fully_observed + 1)
      _, _ -> counted
    }
    let counted = case book.sequence {
      ReportedSequence(_, _) ->
        Counts(..counted, sequences_reported: counted.sequences_reported + 1)
      UnknownSequence(_) -> counted
    }
    case book.gap {
      SequenceGap(_, _) ->
        Counts(..counted, gaps_reported: counted.gaps_reported + 1)
      SequenceReset(_, _) ->
        Counts(..counted, resets_reported: counted.resets_reported + 1)
      NoGapReported | UnknownGap(_) -> counted
    }
  })
}

fn counts_json(value: Counts) -> Json {
  json.object([
    #("reports", json.int(value.reports)),
    #("fullyObserved", json.int(value.fully_observed)),
    #(
      "bidStates",
      json.object([
        #("observed", json.int(value.bids_observed)),
        #("unavailable", json.int(value.bids_unavailable)),
        #("conflicting", json.int(value.bids_conflicting)),
      ]),
    ),
    #(
      "askStates",
      json.object([
        #("observed", json.int(value.asks_observed)),
        #("unavailable", json.int(value.asks_unavailable)),
        #("conflicting", json.int(value.asks_conflicting)),
      ]),
    ),
    #("reportedSequences", json.int(value.sequences_reported)),
    #("reportedSequenceGaps", json.int(value.gaps_reported)),
    #("reportedSequenceResets", json.int(value.resets_reported)),
  ])
}

fn listing_json(value: Listing) -> Json {
  json.object([
    #("listingId", json.string(value.listing_id)),
    #("mic", json.string(identifier.mic_value(value.mic))),
    #("symbol", json.string(value.symbol)),
    #("currency", json.string(currency.code(value.currency))),
    #("identityStatus", json.string("caller_supplied_unverified")),
  ])
}

fn report_json(value: Report) -> Json {
  json.object([
    #("reportId", json.string(value.report_id)),
    #("sourceId", json.string(value.source_record.source_id)),
    #("provider", json.string(source.provider(value.source_record.safe.value))),
    #("feed", json.string(value.source_record.feed)),
    #("currencyMatchesListing", json.bool(value.currency_matches_listing)),
    #("observation", observation_json(value.observed)),
  ])
}

fn report_receipt_json(value: Report) -> Json {
  json.object([
    #("reportId", json.string(value.report_id)),
    #("sourceId", json.string(value.source_record.source_id)),
    #("currencyMatchesListing", json.bool(value.currency_matches_listing)),
    #("observation", observation_receipt_json(value.observed)),
  ])
}

fn observation_json(value: observation.Observation(TopOfBook)) -> Json {
  let book = value.value
  json.object([
    #("kind", json.string("top_of_book_report")),
    #("currency", json.string(currency.code(book.currency))),
    #("providerTimestamp", json.string(book.provider_timestamp)),
    #(
      "providerTimeUnixMilliseconds",
      json.int(time.unix_milliseconds(value.as_of)),
    ),
    #(
      "receivedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(value.retrieved_at)),
    ),
    #("exchangeTime", exchange_time_json(book.exchange_time)),
    #("sequence", sequence_json(book.sequence)),
    #("gap", gap_json(book.gap)),
    #("aggregation", aggregation_json(book.aggregation)),
    #("sizeUnit", size_unit_json(book.size_unit)),
    #("conditionCodes", json.array(book.condition_codes, json.string)),
    #("bid", side_json(book.bid)),
    #("ask", side_json(book.ask)),
    #("evidenceId", json.nullable(value.evidence_id, json.string)),
    #("freshness", json.string("unknown_not_assessed")),
    #("entitlement", entitlement_json(value.entitlement)),
    #("quality", json.string(quality_name(value.quality))),
    #(
      "unit",
      json.object([
        #("kind", json.string("currency_per_share")),
        #("currency", json.string(currency.code(book.currency))),
      ]),
    ),
    #("adjustment", json.null()),
    #("session", json.null()),
  ])
}

fn observation_receipt_json(value: observation.Observation(TopOfBook)) -> Json {
  let book = value.value
  json.object([
    #("currency", json.string(currency.code(book.currency))),
    #("providerTimestamp", json.string(book.provider_timestamp)),
    #(
      "providerTimeUnixMilliseconds",
      json.int(time.unix_milliseconds(value.as_of)),
    ),
    #(
      "receivedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(value.retrieved_at)),
    ),
    #("exchangeTime", exchange_time_json(book.exchange_time)),
    #("sequence", sequence_json(book.sequence)),
    #("gap", gap_json(book.gap)),
    #("aggregation", aggregation_json(book.aggregation)),
    #("sizeUnit", size_unit_json(book.size_unit)),
    #("conditionCodes", json.array(book.condition_codes, json.string)),
    #("bid", side_json(book.bid)),
    #("ask", side_json(book.ask)),
    #("evidenceId", json.nullable(value.evidence_id, json.string)),
  ])
}

fn exchange_time_json(value: ExchangeTime) -> Json {
  case value {
    ReportedExchangeTime(unix_milliseconds, source_lexeme) ->
      json.object([
        #("state", json.string("reported")),
        #("unixMilliseconds", json.int(unix_milliseconds)),
        #("sourceLexeme", json.string(source_lexeme)),
        #("reason", json.null()),
      ])
    UnknownExchangeTime(reason) ->
      json.object([
        #("state", json.string("unknown")),
        #("unixMilliseconds", json.null()),
        #("sourceLexeme", json.null()),
        #("reason", json.string(reason)),
      ])
  }
}

fn sequence_json(value: SequenceState) -> Json {
  case value {
    ReportedSequence(number, scope) ->
      json.object([
        #("state", json.string("reported")),
        #("value", json.int(number)),
        #("scope", json.string(scope)),
        #("reason", json.null()),
      ])
    UnknownSequence(reason) ->
      json.object([
        #("state", json.string("unknown")),
        #("value", json.null()),
        #("scope", json.string("unknown")),
        #("reason", json.string(reason)),
      ])
  }
}

fn gap_json(value: GapState) -> Json {
  case value {
    NoGapReported ->
      json.object([
        #("state", json.string("no_gap_reported")),
        #("fromSequence", json.null()),
        #("toSequence", json.null()),
        #("reason", json.null()),
        #("sequenceSemantics", json.string("none_reported_no_proof")),
        #("continuityProven", json.bool(False)),
      ])
    SequenceGap(from_sequence, to_sequence) ->
      json.object([
        #("state", json.string("sequence_gap")),
        #("fromSequence", json.int(from_sequence)),
        #("toSequence", json.int(to_sequence)),
        #("reason", json.null()),
        #("sequenceSemantics", json.string("inclusive_missing_range")),
        #("continuityProven", json.bool(False)),
      ])
    SequenceReset(previous, reset_at) ->
      json.object([
        #("state", json.string("sequence_reset")),
        #("fromSequence", json.int(previous)),
        #("toSequence", json.int(reset_at)),
        #("reason", json.null()),
        #("sequenceSemantics", json.string("previous_and_reset_at")),
        #("continuityProven", json.bool(False)),
      ])
    UnknownGap(reason) ->
      json.object([
        #("state", json.string("unknown")),
        #("fromSequence", json.null()),
        #("toSequence", json.null()),
        #("reason", json.string(reason)),
        #("sequenceSemantics", json.string("unknown")),
        #("continuityProven", json.bool(False)),
      ])
  }
}

fn aggregation_json(value: Aggregation) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("venues", json.array(value.venues, venue_json)),
    #("coverage", json.string(value.coverage)),
    #("methodLabel", json.nullable(value.method_label, json.string)),
    #("reason", json.nullable(value.reason, json.string)),
    #("declarationStatus", json.string("caller_supplied_unverified")),
    #("nbboClaim", json.bool(False)),
  ])
}

fn size_unit_json(value: SizeUnit) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("label", json.nullable(value.label, json.string)),
    #("reason", json.nullable(value.reason, json.string)),
    #("semanticsStatus", json.string("caller_supplied_unverified")),
  ])
}

fn side_json(value: SideState) -> Json {
  case value {
    ObservedSide(candidate) ->
      json.object([
        #("state", json.string("observed")),
        #("candidate", candidate_json(candidate)),
        #("reason", json.null()),
        #(
          "alternatives",
          json.array([], fn(value: Alternative) { alternative_json(value) }),
        ),
        #("resolution", json.string("not_needed")),
      ])
    UnavailableSide(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("candidate", json.null()),
        #("reason", json.string(reason)),
        #(
          "alternatives",
          json.array([], fn(value: Alternative) { alternative_json(value) }),
        ),
        #("resolution", json.string("not_performed")),
      ])
    ConflictingSide(reason, alternatives) ->
      json.object([
        #("state", json.string("conflicting")),
        #("candidate", json.null()),
        #("reason", json.string(reason)),
        #("alternatives", json.array(alternatives, alternative_json)),
        #("resolution", json.string("not_performed")),
      ])
  }
}

fn candidate_json(value: Candidate) -> Json {
  json.object([
    #("rawPrice", json.string(value.raw_price)),
    #("normalizedPrice", json.string(decimal.to_string(value.normalized_price))),
    #("rawSize", json.string(value.raw_size)),
    #("normalizedSize", json.string(decimal.to_string(value.normalized_size))),
    #("venue", venue_json(value.venue)),
    #("displayed", json.bool(True)),
  ])
}

fn alternative_json(value: Alternative) -> Json {
  json.object([
    #("candidate", candidate_json(value.candidate)),
    #("evidenceId", json.string(value.evidence_id)),
  ])
}

fn venue_json(value: Venue) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("code", json.string(value.code)),
    #("identityStatus", json.string("reported_unverified")),
  ])
}

fn quality_name(value: observation.Quality) -> String {
  case value {
    observation.Reported -> "reported"
    observation.Estimated -> "estimated"
    observation.Restated -> "restated"
    observation.Revised -> "revised"
    observation.Missing(_) -> "missing_unavailable"
  }
}

fn source_record_json(value: SourceRecord) -> Json {
  json.object([
    #("sourceId", json.string(value.source_id)),
    #("provider", json.string(source.provider(value.safe.value))),
    #("reference", json.string(source.reference(value.safe.value))),
    #("referenceRedacted", json.bool(value.safe.reference_redacted)),
    #("kind", json.string(source_kind_name(value.kind))),
    #("otherKind", json.nullable(source_other_kind(value.kind), json.string)),
    #("feed", json.string(value.feed)),
    #("receiptHash", json.string(value.receipt_hash)),
    #("receiptBinding", json.string("caller_supplied_unverified")),
    #("entitlement", entitlement_json(value.entitlement)),
    #("licence", licence_json(value.licence)),
  ])
}

fn source_receipt_json(value: SourceRecord) -> Json {
  json.object([
    #("sourceId", json.string(value.source_id)),
    #("provider", json.string(source.provider(value.safe.value))),
    #("reference", json.string(source.reference(value.safe.value))),
    #("referenceRedacted", json.bool(value.safe.reference_redacted)),
    #("kind", json.string(source_kind_name(value.kind))),
    #("otherKind", json.nullable(source_other_kind(value.kind), json.string)),
    #("feed", json.string(value.feed)),
    #("receiptHash", json.string(value.receipt_hash)),
    #("entitlement", entitlement_json(value.entitlement)),
    #("licence", licence_json(value.licence)),
  ])
}

fn parse_source_kind(
  value: decode.SourceInput,
  field: String,
) -> Result(source.SourceKind, DomainError) {
  case value.kind, value.other_kind {
    "official", None -> Ok(source.Official)
    "exchange", None -> Ok(source.Exchange)
    "regulator", None -> Ok(source.Regulator)
    "licensed_vendor", None -> Ok(source.LicensedVendor)
    "user_supplied", None -> Ok(source.UserSupplied)
    "synthetic", None -> Ok(source.Synthetic)
    "other", Some(kind) -> {
      use exact <- result.try(bounded_text(field <> ".otherKind", kind, 200))
      Ok(source.Other(exact))
    }
    "other", None ->
      Error(InvalidField(
        field <> ".otherKind",
        "other source kind requires exact otherKind text",
      ))
    _, Some(_) ->
      Error(InvalidField(
        field <> ".otherKind",
        "otherKind is only allowed when kind is other",
      ))
    _, None ->
      Error(InvalidField(field <> ".kind", "unsupported explicit source kind"))
  }
}

fn make_safe_source(
  provider: String,
  raw_reference: String,
  kind: source.SourceKind,
  field: String,
) -> Result(SafeSource, DomainError) {
  use _ <- result.try(bounded_text(field <> ".reference", raw_reference, 8000))
  let projected = redact.url(raw_reference, [])
  case source.new(provider, projected, kind) {
    Ok(value) -> Ok(SafeSource(value, projected != raw_reference))
    Error(source.UnsafeReference) -> {
      use digest <- result.try(
        hash.text(raw_reference)
        |> result.map_error(fn(_) {
          InvalidField(field <> ".reference", "safe reference hashing failed")
        }),
      )
      let fallback =
        "redacted-reference:sha256:" <> identity.sha256_value(digest)
      source.new(provider, fallback, kind)
      |> result.map(fn(value) { SafeSource(value, True) })
      |> result.map_error(fn(_) {
        InvalidField(field <> ".reference", "could not construct a safe source")
      })
    }
    Error(_) ->
      Error(InvalidField(
        field <> ".reference",
        "expected trimmed non-empty source reference",
      ))
  }
}

fn parse_entitlement(
  value: decode.EntitlementInput,
  field: String,
) -> Result(observation.Entitlement, DomainError) {
  case value.state, value.delay_milliseconds {
    "real_time", None -> Ok(observation.RealTime)
    "end_of_day", None -> Ok(observation.EndOfDay)
    "unknown", None -> Ok(observation.UnknownEntitlement)
    "delayed", Some(milliseconds) -> {
      use _ <- result.try(integer_range(
        field <> ".delayMilliseconds",
        milliseconds,
        1,
        maximum_safe_integer,
      ))
      time.duration(milliseconds)
      |> result.map(observation.Delayed)
      |> result.map_error(fn(_) {
        InvalidField(field <> ".delayMilliseconds", "delay is out of range")
      })
    }
    _, _ ->
      Error(InvalidField(
        field,
        "real_time, end_of_day, and unknown forbid delayMilliseconds; delayed requires it",
      ))
  }
}

fn parse_licence(
  value: decode.LicenceInput,
  field: String,
) -> Result(evidence.Licence, DomainError) {
  use label <- result.try(bounded_text(field <> ".label", value.label, 500))
  use notes <- result.try(optional_bounded_text(
    field <> ".notes",
    value.notes,
    4000,
  ))
  use redistribution <- result.try(parse_redistribution(
    value.redistribution,
    field <> ".redistribution",
  ))
  Ok(evidence.Licence(label, redistribution, notes))
}

fn parse_redistribution(
  value: String,
  field: String,
) -> Result(evidence.Redistribution, DomainError) {
  case value {
    "public_domain" -> Ok(evidence.PublicDomain)
    "attribution_required" -> Ok(evidence.AttributionRequired)
    "internal_use_only" -> Ok(evidence.InternalUseOnly)
    "no_redistribution" -> Ok(evidence.NoRedistribution)
    "unknown" -> Ok(evidence.UnknownRedistribution)
    _ -> Error(InvalidField(field, "unsupported explicit redistribution state"))
  }
}

fn source_kind_name(value: source.SourceKind) -> String {
  case value {
    source.Official -> "official"
    source.Exchange -> "exchange"
    source.Regulator -> "regulator"
    source.LicensedVendor -> "licensed_vendor"
    source.UserSupplied -> "user_supplied"
    source.Synthetic -> "synthetic"
    source.Other(_) -> "other"
  }
}

fn source_other_kind(value: source.SourceKind) -> Option(String) {
  case value {
    source.Other(kind) -> Some(kind)
    _ -> None
  }
}

fn entitlement_json(value: observation.Entitlement) -> Json {
  let #(state, delay) = case value {
    observation.RealTime -> #("real_time", None)
    observation.Delayed(value) -> #(
      "delayed",
      Some(time.duration_milliseconds(value)),
    )
    observation.EndOfDay -> #("end_of_day", None)
    observation.UnknownEntitlement -> #("unknown", None)
  }
  json.object([
    #("state", json.string(state)),
    #("delayMilliseconds", json.nullable(delay, json.int)),
    #("status", json.string("caller_or_provider_adapter_declared_unverified")),
  ])
}

fn licence_json(value: evidence.Licence) -> Json {
  json.object([
    #("label", json.string(value.label)),
    #("redistribution", json.string(redistribution_name(value.redistribution))),
    #("notes", json.nullable(value.notes, json.string)),
    #("status", json.string("caller_or_provider_adapter_declared_unverified")),
  ])
}

fn redistribution_name(value: evidence.Redistribution) -> String {
  case value {
    evidence.PublicDomain -> "public_domain"
    evidence.AttributionRequired -> "attribution_required"
    evidence.InternalUseOnly -> "internal_use_only"
    evidence.NoRedistribution -> "no_redistribution"
    evidence.UnknownRedistribution -> "unknown"
  }
}

fn parse_mic(
  field: String,
  value: String,
) -> Result(identifier.Mic, DomainError) {
  use parsed <- result.try(
    identifier.mic(value)
    |> result.map_error(fn(_) {
      InvalidField(field, "expected an exact four-character MIC")
    }),
  )
  case identifier.mic_value(parsed) == value {
    True -> Ok(parsed)
    False ->
      Error(InvalidField(
        field,
        "MIC must already use its exact uppercase representation",
      ))
  }
}

fn validate_track_mic(
  track: finance_track.Track,
  mic: identifier.Mic,
  field: String,
) -> Result(Nil, DomainError) {
  let value = identifier.mic_value(mic)
  let allowed = case track {
    finance_track.Cn -> ["XSHG", "XSHE", "XBSE"]
    finance_track.Hk -> ["XHKG"]
    finance_track.Us -> ["XNYS", "XNAS"]
  }
  case list.contains(allowed, value) {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "MIC is outside the first-slice allowlist for explicit track "
          <> finance_track.name(track)
          <> ": "
          <> string.join(allowed, ", "),
      ))
  }
}

fn parse_currency(
  field: String,
  value: String,
) -> Result(currency.Currency, DomainError) {
  use parsed <- result.try(
    currency.from_code(value)
    |> result.map_error(fn(_) {
      InvalidField(field, "expected a three-letter currency code")
    }),
  )
  case currency.code(parsed) == value {
    True -> Ok(parsed)
    False ->
      Error(InvalidField(
        field,
        "currency must already use its exact uppercase representation",
      ))
  }
}

fn find_source(
  source_id: String,
  values: List(SourceRecord),
  field: String,
) -> Result(SourceRecord, DomainError) {
  values
  |> list.find(fn(value) { value.source_id == source_id })
  |> result.map_error(fn(_) {
    InvalidField(field <> ".sourceId", "must reference one supplied sourceId")
  })
}

fn parse_page(value: decode.PageInput) -> Result(Page, DomainError) {
  use _ <- result.try(integer_range(
    "page.offset",
    value.offset,
    0,
    maximum_reports,
  ))
  use _ <- result.try(integer_range(
    "page.limit",
    value.limit,
    1,
    maximum_page_size,
  ))
  Ok(Page(value.offset, value.limit))
}

fn instant(field: String, value: Int) -> Result(time.Instant, DomainError) {
  use _ <- result.try(integer_range(field, value, 0, maximum_safe_integer))
  time.instant(value)
  |> result.map_error(fn(_) { InvalidField(field, "instant is out of range") })
}

fn sha(field: String, value: String) -> Result(identity.Sha256, DomainError) {
  use parsed <- result.try(
    identity.sha256(value)
    |> result.map_error(fn(_) {
      InvalidField(field, "expected an exact SHA-256 hexadecimal string")
    }),
  )
  case identity.sha256_value(parsed) == value {
    True -> Ok(parsed)
    False ->
      Error(InvalidField(
        field,
        "SHA-256 must already use its canonical lowercase representation",
      ))
  }
}

fn bounded_text(
  field: String,
  value: String,
  maximum: Int,
) -> Result(String, DomainError) {
  case
    value != ""
    && string.trim(value) == value
    && string.length(value) <= maximum
    && !string.contains(value, "\r")
    && !string.contains(value, "\n")
    && !string.contains(value, "\t")
  {
    True -> Ok(value)
    False ->
      Error(InvalidField(
        field,
        "expected trimmed non-empty text within "
          <> int.to_string(maximum)
          <> " characters",
      ))
  }
}

fn optional_bounded_text(
  field: String,
  value: Option(String),
  maximum: Int,
) -> Result(Option(String), DomainError) {
  case value {
    None -> Ok(None)
    Some(value) -> {
      use exact <- result.try(bounded_text(field, value, maximum))
      Ok(Some(exact))
    }
  }
}

fn symbol_text(field: String, value: String) -> Result(String, DomainError) {
  use exact <- result.try(bounded_text(field, value, 100))
  case
    exact
    |> string.to_graphemes
    |> list.all(fn(character) { string.trim(character) == character })
  {
    True -> Ok(exact)
    False ->
      Error(InvalidField(field, "expected exact code without whitespace"))
  }
}

fn integer_range(
  field: String,
  value: Int,
  minimum: Int,
  maximum: Int,
) -> Result(Nil, DomainError) {
  case value >= minimum && value <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "expected integer from "
          <> int.to_string(minimum)
          <> " through "
          <> int.to_string(maximum),
      ))
  }
}

fn count_range(
  field: String,
  values: List(value),
  minimum: Int,
  maximum: Int,
) -> Result(Nil, DomainError) {
  let count = list.length(values)
  case count >= minimum && count <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "expected from "
          <> int.to_string(minimum)
          <> " through "
          <> int.to_string(maximum)
          <> " entries",
      ))
  }
}

fn market_timezone(track: finance_track.Track) -> time.Timezone {
  let name = case track {
    finance_track.Cn -> "Asia/Shanghai"
    finance_track.Hk -> "Asia/Hong_Kong"
    finance_track.Us -> "America/New_York"
  }
  let assert Ok(value) = time.timezone(name)
  value
}

fn source_language(track: finance_track.Track) -> String {
  case track {
    finance_track.Cn -> "zh-CN"
    finance_track.Hk -> "zh-HK"
    finance_track.Us -> "en-US"
  }
}

fn unique_providers(values: List(SourceRecord)) -> List(String) {
  list.fold(values, [], fn(providers, value) {
    append_unique(providers, source.provider(value.safe.value))
  })
}

fn append_unique(values: List(String), value: String) -> List(String) {
  case list.contains(values, value) {
    True -> values
    False -> list.append(values, [value])
  }
}

fn limitations() -> List(String) {
  [
    "caller_supplied_listing_currency_and_venue_identity_not_verified",
    "source_receipt_hash_is_not_origin_authentication",
    "licence_entitlement_size_unit_and_aggregation_are_unverified_declarations",
    "exchange_provider_and_receipt_clocks_are_not_synchronized",
    "no_gap_reported_does_not_prove_sequence_continuity",
    "unavailable_and_conflicting_sides_are_not_resolved",
    "displayed_size_is_not_hidden_durable_or_executable_liquidity",
    "no_provider_choice_report_merge_nbbo_gap_repair_or_depth_reconstruction",
    "no_fetch_persistence_signal_ranking_recommendation_order_or_trade",
  ]
}
