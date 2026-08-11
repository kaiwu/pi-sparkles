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
import pi_sparkles_stock_market_calendar/decode

const maximum_safe_integer = 9_007_199_254_740_991

const maximum_sources = 25

const maximum_facts = 500

const maximum_alternatives = 10

const maximum_output_rows = 100

pub opaque type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
}

type SafeSource {
  SafeSource(value: source.SourceRef, reference_redacted: Bool)
}

type Scope {
  Scope(
    kind: String,
    scope_id: String,
    mic: identifier.Mic,
    symbol: Option(String),
  )
}

type Query {
  Query(
    date: String,
    local_time: String,
    local_timestamp: String,
    timezone: time.Timezone,
    at_unix_ms: Int,
  )
}

type Coverage {
  ExactCoverage(start_unix_ms: Int, end_unix_ms: Int)
  UnknownCoverage(reason: String)
}

type SourceRecord {
  SourceRecord(
    source_id: String,
    safe: SafeSource,
    kind: source.SourceKind,
    feed: String,
    coverage: Coverage,
    entitlement: observation.Entitlement,
    licence: evidence.Licence,
    receipt_hash: String,
  )
}

type TypedValue {
  TypedValue(
    category: String,
    other_label: Option(String),
    starts_at_local: Option(String),
    ends_at_local: Option(String),
  )
}

type Alternative {
  Alternative(value: TypedValue, evidence_id: String)
}

type ValueState {
  ObservedValue(value: TypedValue)
  UnavailableValue(reason: String)
  ConflictingValue(reason: String, alternatives: List(Alternative))
}

type Fact {
  Fact(
    fact_id: String,
    kind: String,
    source_record: SourceRecord,
    date: Option(String),
    observed: observation.Observation(ValueState),
  )
}

type ComparisonPoint {
  ComparisonPoint(
    fact_id: String,
    source_id: String,
    provider: String,
    value: TypedValue,
  )
}

type ReportComparison {
  NoReports
  SingleReport(point: ComparisonPoint)
  ExactAgreement(signature: String, points: List(ComparisonPoint))
  ExactDisagreement(points: List(ComparisonPoint))
  IndeterminateComparison(reason: String, facts: List(Fact))
}

type PhaseAlternativeMatch {
  PhaseAlternativeMatch(
    fact_id: String,
    source_id: String,
    provider: String,
    value: TypedValue,
    evidence_id: String,
  )
}

type Counts {
  Counts(
    facts: Int,
    schedules: Int,
    phases: Int,
    market_statuses: Int,
    listing_halts: Int,
    observed: Int,
    unavailable: Int,
    conflicting: Int,
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
  "Invalid exact stock-market-calendar field " <> field <> ": " <> reason
}

pub fn run(input: decode.Input) -> Result(Response, DomainError) {
  use track <- result.try(parse_track(input.track))
  use scope <- result.try(parse_scope(input.scope, track))
  use query <- result.try(parse_query(input.query, track))
  use _ <- result.try(count_range("sources", input.sources, 1, maximum_sources))
  use _ <- result.try(count_range("facts", input.facts, 1, maximum_facts))
  use sources <- result.try(prepare_sources(input.sources, 0, []))
  use _ <- result.try(validate_unique_sources(sources))
  use facts <- result.try(
    prepare_facts(input.facts, sources, scope, query, 0, []),
  )
  use _ <- result.try(validate_unique_fact_ids(facts))
  use page <- result.try(parse_page(input.page))
  let counts = count_facts(facts)
  let selected = facts |> list.drop(page.offset) |> list.take(page.limit)
  let returned = list.length(selected)
  let next_offset = case page.offset + returned < counts.facts {
    True -> Some(page.offset + returned)
    False -> None
  }
  let schedule_comparison = compare_reports(facts_of_kind(facts, "schedule"))
  let status_comparison = compare_reports(facts_of_kind(facts, "market_status"))
  let halt_comparison = compare_reports(facts_of_kind(facts, "listing_halt"))
  let active_phases = active_observed_phases(facts, query.local_timestamp)
  let active_conflicts = active_conflicting_phases(facts, query.local_timestamp)
  let shortened = explicit_shortened_facts(facts)
  let limitations = limitations()
  use context <- result.try(
    track_context.new(
      track: track,
      market_scope: finance_track.name(track) <> "_stock_market_calendar",
      venue_mic: Some(scope.mic),
      board: None,
      timezone: Some(query.timezone),
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
      #("scope", scope_json(scope)),
      #("query", query_json(query)),
      #("sources", json.array(sources, source_receipt_json)),
      #("facts", json.array(facts, fact_receipt_json)),
      #(
        "assessment",
        assessment_receipt_json(
          schedule_comparison,
          status_comparison,
          halt_comparison,
          active_phases,
          active_conflicts,
          shortened,
        ),
      ),
    ])
  let assert Ok(calculation_receipt) =
    receipt_projection |> json.to_string |> hash.text
  Ok(Response(
    finance_track.name(track)
      <> " stock session | "
      <> identifier.mic_value(scope.mic)
      <> " | "
      <> query.date
      <> " "
      <> query.local_time
      <> " | "
      <> int.to_string(counts.facts)
      <> " facts / "
      <> int.to_string(list.length(active_phases))
      <> " active observed phases",
    json.object(
      list.append(track_json.result_fields(context), [
        #("schemaVersion", json.int(1)),
        #("operation", json.string("stock_session_status")),
        #("scope", scope_json(scope)),
        #("query", query_json(query)),
        #("summary", counts_json(counts)),
        #(
          "assessment",
          assessment_json(
            schedule_comparison,
            status_comparison,
            halt_comparison,
            active_phases,
            active_conflicts,
            shortened,
          ),
        ),
        #(
          "calculation",
          json.object([
            #(
              "phaseInterval",
              json.string("half_open_local_start_inclusive_end_exclusive"),
            ),
            #("overlapResolution", json.string("not_performed")),
            #("sourceSelection", json.string("not_performed")),
            #("calendarOrHaltInference", json.string("not_performed")),
            #(
              "receiptHash",
              json.string(identity.sha256_value(calculation_receipt)),
            ),
          ]),
        ),
        #(
          "page",
          json.object([
            #("offset", json.int(page.offset)),
            #("limit", json.int(page.limit)),
            #("returned", json.int(returned)),
            #("total", json.int(counts.facts)),
            #("nextOffset", json.nullable(next_offset, json.int)),
            #("order", json.string("caller_supplied_fact_order")),
          ]),
        ),
        #("facts", json.array(selected, fn(fact) { fact_json(fact, query) })),
        #(
          "sources",
          json.array(sources, fn(value) {
            source_record_json(value, query.at_unix_ms)
          }),
        ),
        #(
          "unknownFacts",
          json.array(
            [
              "scope_identity_authority",
              "source_receipt_origin_authentication",
              "licence_and_entitlement_verification",
              "local_timestamp_to_unix_instant_coherence",
              "calendar_completeness_and_exception_notices",
              "phase_or_halt_state_not_explicitly_reported",
              "source_correctness_or_preference",
            ],
            json.string,
          ),
        ),
        #(
          "assessmentStatus",
          json.string("reported_facts_only_no_session_verdict"),
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

fn parse_scope(
  value: decode.ScopeInput,
  track: finance_track.Track,
) -> Result(Scope, DomainError) {
  use scope_id <- result.try(bounded_text("scope.scopeId", value.scope_id, 2000))
  use mic <- result.try(parse_mic("scope.mic", value.mic))
  use _ <- result.try(validate_track_mic(track, mic, "scope.mic"))
  case value.kind, value.symbol {
    "market", None -> Ok(Scope("market", scope_id, mic, None))
    "listing", Some(symbol) -> {
      use exact <- result.try(symbol_text("scope.symbol", symbol))
      Ok(Scope("listing", scope_id, mic, Some(exact)))
    }
    "market", Some(_) ->
      Error(InvalidField("scope.symbol", "market scope forbids symbol"))
    "listing", None ->
      Error(InvalidField("scope.symbol", "listing scope requires symbol"))
    _, _ -> Error(InvalidField("scope.kind", "expected market or listing"))
  }
}

fn parse_query(
  value: decode.QueryInput,
  track: finance_track.Track,
) -> Result(Query, DomainError) {
  use date <- result.try(canonical_date("query.date", value.date))
  use local_time <- result.try(canonical_time(
    "query.localTime",
    value.local_time,
  ))
  use _ <- result.try(integer_range(
    "query.atUnixMilliseconds",
    value.at_unix_ms,
    0,
    maximum_safe_integer,
  ))
  let expected = market_timezone_name(track)
  use _ <- result.try(case value.timezone == expected {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "query.timezone",
        "expected exact first-slice MIC timezone " <> expected,
      ))
  })
  let assert Ok(timezone) = time.timezone(expected)
  Ok(Query(
    date,
    local_time,
    date <> "T" <> local_time,
    timezone,
    value.at_unix_ms,
  ))
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
      use coverage <- result.try(parse_coverage(
        value.coverage,
        field <> ".coverage",
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
          coverage,
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

fn parse_coverage(
  value: decode.CoverageInput,
  field: String,
) -> Result(Coverage, DomainError) {
  case value.state, value.start_unix_ms, value.end_unix_ms, value.reason {
    "exact_range", Some(start), Some(end), None -> {
      use _ <- result.try(integer_range(
        field <> ".startUnixMilliseconds",
        start,
        0,
        maximum_safe_integer,
      ))
      use _ <- result.try(integer_range(
        field <> ".endUnixMilliseconds",
        end,
        0,
        maximum_safe_integer,
      ))
      case start <= end {
        True -> Ok(ExactCoverage(start, end))
        False ->
          Error(InvalidField(field, "coverage start must not follow end"))
      }
    }
    "unknown", None, None, Some(reason) -> {
      use exact <- result.try(bounded_text(field <> ".reason", reason, 500))
      Ok(UnknownCoverage(exact))
    }
    _, _, _, _ ->
      Error(InvalidField(
        field,
        "exact_range requires inclusive start/end only; unknown requires reason only",
      ))
  }
}

fn prepare_facts(
  remaining: List(decode.FactInput),
  sources: List(SourceRecord),
  scope: Scope,
  query: Query,
  index: Int,
  reversed: List(Fact),
) -> Result(List(Fact), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use fact <- result.try(prepare_fact(value, sources, scope, query, index))
      prepare_facts(rest, sources, scope, query, index + 1, [fact, ..reversed])
    }
  }
}

fn prepare_fact(
  value: decode.FactInput,
  sources: List(SourceRecord),
  scope: Scope,
  query: Query,
  index: Int,
) -> Result(Fact, DomainError) {
  let field = "facts[" <> int.to_string(index) <> "]"
  use fact_id <- result.try(bounded_text(field <> ".factId", value.fact_id, 500))
  use kind <- result.try(parse_fact_kind(field <> ".kind", value.kind))
  use source_id <- result.try(bounded_text(
    field <> ".sourceId",
    value.source_id,
    200,
  ))
  use source_record <- result.try(find_source(source_id, sources, field))
  use date <- result.try(parse_fact_date(value.date, kind, query.date, field))
  use _ <- result.try(case kind == "listing_halt" && scope.kind != "listing" {
    True ->
      Error(InvalidField(
        field <> ".kind",
        "listing_halt facts require an exact listing scope",
      ))
    False -> Ok(Nil)
  })
  use as_of <- result.try(instant(
    field <> ".asOfUnixMilliseconds",
    value.as_of_unix_ms,
  ))
  use retrieved <- result.try(instant(
    field <> ".retrievedAtUnixMilliseconds",
    value.retrieved_at_unix_ms,
  ))
  use _ <- result.try(case value.retrieved_at_unix_ms >= value.as_of_unix_ms {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field <> ".retrievedAtUnixMilliseconds",
        "must not precede asOfUnixMilliseconds",
      ))
  })
  use state <- result.try(parse_value(value.value, kind, field <> ".value"))
  let quality = case state {
    UnavailableValue(_) -> observation.Missing(observation.Unavailable)
    ObservedValue(_) | ConflictingValue(_, _) -> observation.Reported
  }
  let observed =
    observation.Observation(
      value: state,
      as_of: as_of,
      retrieved_at: retrieved,
      timezone: Some(query.timezone),
      source: source_record.safe.value,
      evidence_id: Some(source_record.receipt_hash),
      freshness: observation.UnknownFreshness,
      entitlement: source_record.entitlement,
      quality: quality,
      unit: None,
      adjustment: None,
      session: session_for(kind, state),
    )
  Ok(Fact(fact_id, kind, source_record, date, observed))
}

fn parse_fact_kind(
  field: String,
  value: String,
) -> Result(String, DomainError) {
  case
    list.contains(["schedule", "phase", "market_status", "listing_halt"], value)
  {
    True -> Ok(value)
    False -> Error(InvalidField(field, "unsupported exact fact kind"))
  }
}

fn parse_fact_date(
  value: Option(String),
  kind: String,
  query_date: String,
  field: String,
) -> Result(Option(String), DomainError) {
  case kind, value {
    "schedule", Some(value) -> {
      use exact <- result.try(canonical_date(field <> ".date", value))
      case exact == query_date {
        True -> Ok(Some(exact))
        False ->
          Error(InvalidField(
            field <> ".date",
            "schedule date must equal the exact query date",
          ))
      }
    }
    "schedule", None ->
      Error(InvalidField(
        field <> ".date",
        "schedule facts require the exact query date",
      ))
    _, None -> Ok(None)
    _, Some(_) ->
      Error(InvalidField(field <> ".date", "only schedule facts accept a date"))
  }
}

fn parse_value(
  value: decode.ValueInput,
  kind: String,
  field: String,
) -> Result(ValueState, DomainError) {
  use _ <- result.try(count_bound(
    field <> ".alternatives",
    value.alternatives,
    maximum_alternatives,
  ))
  case
    value.state,
    value.category,
    value.other_label,
    value.starts_at_local,
    value.ends_at_local,
    value.reason,
    value.alternatives
  {
    "observed", Some(category), other, starts, ends, None, [] -> {
      use exact <- result.try(parse_typed_value(
        kind,
        category,
        other,
        starts,
        ends,
        field,
      ))
      Ok(ObservedValue(exact))
    }
    "unavailable", None, None, None, None, Some(reason), [] -> {
      use exact <- result.try(bounded_text(field <> ".reason", reason, 500))
      Ok(UnavailableValue(exact))
    }
    "conflicting", None, None, None, None, Some(reason), alternatives -> {
      use exact_reason <- result.try(bounded_text(
        field <> ".reason",
        reason,
        500,
      ))
      use _ <- result.try(case list.length(alternatives) >= 2 {
        True -> Ok(Nil)
        False ->
          Error(InvalidField(
            field <> ".alternatives",
            "conflicting value requires at least two alternatives",
          ))
      })
      use prepared <- result.try(
        prepare_alternatives(alternatives, kind, field, 0, []),
      )
      use _ <- result.try(validate_distinct_alternatives(prepared, field))
      Ok(ConflictingValue(exact_reason, prepared))
    }
    _, _, _, _, _, _, _ ->
      Error(InvalidField(
        field,
        "observed requires one direct typed value; unavailable requires reason only; conflicting requires reason and at least two alternatives only",
      ))
  }
}

fn prepare_alternatives(
  remaining: List(decode.AlternativeInput),
  kind: String,
  field: String,
  index: Int,
  reversed: List(Alternative),
) -> Result(List(Alternative), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      let current = field <> ".alternatives[" <> int.to_string(index) <> "]"
      use typed <- result.try(parse_typed_value(
        kind,
        value.category,
        value.other_label,
        value.starts_at_local,
        value.ends_at_local,
        current,
      ))
      use evidence_id <- result.try(sha(
        current <> ".evidenceId",
        value.evidence_id,
      ))
      let evidence_text = identity.sha256_value(evidence_id)
      use _ <- result.try(
        case
          list.any(reversed, fn(existing) {
            existing.evidence_id == evidence_text
          })
        {
          True ->
            Error(InvalidField(
              field <> ".alternatives",
              "alternative evidence IDs must be unique",
            ))
          False -> Ok(Nil)
        },
      )
      prepare_alternatives(rest, kind, field, index + 1, [
        Alternative(typed, evidence_text),
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
    [] | [_] ->
      Error(InvalidField(
        field <> ".alternatives",
        "conflicting value requires at least two alternatives",
      ))
    _ -> validate_unique_alternative_signatures(values, field, [])
  }
}

fn validate_unique_alternative_signatures(
  values: List(Alternative),
  field: String,
  seen: List(String),
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      let signature = typed_signature(value.value)
      case list.contains(seen, signature) {
        True ->
          Error(InvalidField(
            field <> ".alternatives",
            "conflicting alternatives must contain distinct exact values",
          ))
        False ->
          validate_unique_alternative_signatures(rest, field, [
            signature,
            ..seen
          ])
      }
    }
  }
}

fn parse_typed_value(
  kind: String,
  category: String,
  other_label: Option(String),
  starts_at_local: Option(String),
  ends_at_local: Option(String),
  field: String,
) -> Result(TypedValue, DomainError) {
  use exact_category <- result.try(validate_category(
    kind,
    category,
    field <> ".category",
  ))
  use exact_other <- result.try(parse_other_label(
    exact_category,
    other_label,
    field <> ".otherLabel",
  ))
  case kind, starts_at_local, ends_at_local {
    "phase", Some(starts), Some(ends) -> {
      use exact_start <- result.try(canonical_local_timestamp(
        field <> ".startsAtLocal",
        starts,
      ))
      use exact_end <- result.try(canonical_local_timestamp(
        field <> ".endsAtLocal",
        ends,
      ))
      case string.compare(exact_start, exact_end) {
        Lt ->
          Ok(TypedValue(
            exact_category,
            exact_other,
            Some(exact_start),
            Some(exact_end),
          ))
        Eq | Gt ->
          Error(InvalidField(
            field,
            "phase start must strictly precede phase end",
          ))
      }
    }
    "phase", _, _ ->
      Error(InvalidField(
        field,
        "phase values require exact startsAtLocal and endsAtLocal",
      ))
    _, None, None -> Ok(TypedValue(exact_category, exact_other, None, None))
    _, _, _ ->
      Error(InvalidField(
        field,
        "only phase values accept startsAtLocal and endsAtLocal",
      ))
  }
}

fn validate_category(
  kind: String,
  category: String,
  field: String,
) -> Result(String, DomainError) {
  let allowed = case kind {
    "schedule" -> ["regular_full", "regular_shortened", "closed", "other"]
    "phase" -> [
      "pre_market",
      "opening_auction",
      "continuous",
      "midday_break",
      "closing_auction",
      "after_hours",
      "other",
    ]
    "market_status" -> [
      "pre_market",
      "opening_auction",
      "continuous",
      "midday_break",
      "closing_auction",
      "after_hours",
      "closed",
      "other",
    ]
    "listing_halt" -> ["halted", "not_halted"]
    _ -> []
  }
  case list.contains(allowed, category) {
    True -> Ok(category)
    False ->
      Error(InvalidField(
        field,
        "category is outside the exact allowlist for "
          <> kind
          <> ": "
          <> string.join(allowed, ", "),
      ))
  }
}

fn parse_other_label(
  category: String,
  value: Option(String),
  field: String,
) -> Result(Option(String), DomainError) {
  case category, value {
    "other", Some(value) -> {
      use exact <- result.try(bounded_text(field, value, 200))
      Ok(Some(exact))
    }
    "other", None -> Error(InvalidField(field, "other requires otherLabel"))
    _, None -> Ok(None)
    _, Some(_) ->
      Error(InvalidField(
        field,
        "otherLabel is only allowed when category is other",
      ))
  }
}

fn session_for(kind: String, value: ValueState) -> Option(market.Session) {
  case value {
    UnavailableValue(_) | ConflictingValue(_, _) -> None
    ObservedValue(value) -> session_for_category(kind, value)
  }
}

fn session_for_category(
  kind: String,
  value: TypedValue,
) -> Option(market.Session) {
  case kind, value.category {
    "schedule", "regular_full" | "schedule", "regular_shortened" ->
      Some(market.Regular)
    "schedule", "closed" | "market_status", "closed" -> Some(market.Closed)
    "phase", "pre_market" | "market_status", "pre_market" ->
      Some(market.PreMarket)
    "phase", "after_hours" | "market_status", "after_hours" ->
      Some(market.AfterHours)
    "phase", "opening_auction"
    | "phase", "closing_auction"
    | "market_status", "opening_auction"
    | "market_status", "closing_auction"
    -> Some(market.Auction)
    "phase", "continuous" | "market_status", "continuous" ->
      Some(market.Regular)
    _, "other" -> {
      let assert Some(label) = value.other_label
      let assert Ok(session) = market.other_session(label)
      Some(session)
    }
    _, _ -> None
  }
}

fn validate_unique_fact_ids(values: List(Fact)) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case list.any(rest, fn(other) { other.fact_id == current.fact_id }) {
        True -> Error(InvalidField("facts", "factId values must be unique"))
        False -> validate_unique_fact_ids(rest)
      }
  }
}

fn find_source(
  source_id: String,
  sources: List(SourceRecord),
  field: String,
) -> Result(SourceRecord, DomainError) {
  case list.find(sources, fn(value) { value.source_id == source_id }) {
    Ok(value) -> Ok(value)
    Error(_) ->
      Error(InvalidField(
        field <> ".sourceId",
        "must reference one exact source catalogue entry",
      ))
  }
}

fn facts_of_kind(values: List(Fact), kind: String) -> List(Fact) {
  list.filter(values, fn(value) { value.kind == kind })
}

fn compare_reports(facts: List(Fact)) -> ReportComparison {
  case facts {
    [] -> NoReports
    _ -> {
      let points =
        list.filter_map(facts, fn(fact) {
          case fact.observed.value {
            ObservedValue(value) ->
              Ok(ComparisonPoint(
                fact.fact_id,
                fact.source_record.source_id,
                source.provider(fact.source_record.safe.value),
                value,
              ))
            UnavailableValue(_) | ConflictingValue(_, _) -> Error(Nil)
          }
        })
      case list.length(points) == list.length(facts), points {
        False, _ ->
          IndeterminateComparison(
            "unavailable_or_conflicting_reported_fact",
            facts,
          )
        True, [only] -> SingleReport(only)
        True, [first, ..rest] -> {
          case comparison_source_count(points) == list.length(points) {
            False -> IndeterminateComparison("duplicate_source_reports", facts)
            True -> {
              let signature = typed_signature(first.value)
              case
                list.all(rest, fn(point) {
                  typed_signature(point.value) == signature
                })
              {
                True -> ExactAgreement(signature, points)
                False -> ExactDisagreement(points)
              }
            }
          }
        }
        True, [] -> NoReports
      }
    }
  }
}

fn active_observed_phases(
  facts: List(Fact),
  query_local: String,
) -> List(Fact) {
  facts
  |> facts_of_kind("phase")
  |> list.filter(fn(fact) {
    case fact.observed.value {
      ObservedValue(value) -> interval_contains(value, query_local)
      UnavailableValue(_) | ConflictingValue(_, _) -> False
    }
  })
}

fn active_conflicting_phases(
  facts: List(Fact),
  query_local: String,
) -> List(PhaseAlternativeMatch) {
  facts
  |> facts_of_kind("phase")
  |> list.flat_map(fn(fact) {
    case fact.observed.value {
      ConflictingValue(_, alternatives) ->
        alternatives
        |> list.filter(fn(alternative) {
          interval_contains(alternative.value, query_local)
        })
        |> list.map(fn(alternative) {
          PhaseAlternativeMatch(
            fact.fact_id,
            fact.source_record.source_id,
            source.provider(fact.source_record.safe.value),
            alternative.value,
            alternative.evidence_id,
          )
        })
      ObservedValue(_) | UnavailableValue(_) -> []
    }
  })
}

fn interval_contains(value: TypedValue, query_local: String) -> Bool {
  case value.starts_at_local, value.ends_at_local {
    Some(starts), Some(ends) ->
      string.compare(starts, query_local) != Gt
      && string.compare(query_local, ends) == Lt
    _, _ -> False
  }
}

fn explicit_shortened_facts(facts: List(Fact)) -> List(Fact) {
  facts
  |> facts_of_kind("schedule")
  |> list.filter(fn(fact) {
    case fact.observed.value {
      ObservedValue(value) -> value.category == "regular_shortened"
      UnavailableValue(_) | ConflictingValue(_, _) -> False
    }
  })
}

fn count_facts(facts: List(Fact)) -> Counts {
  list.fold(facts, Counts(0, 0, 0, 0, 0, 0, 0, 0), fn(counts, fact) {
    let by_kind = case fact.kind {
      "schedule" -> Counts(..counts, schedules: counts.schedules + 1)
      "phase" -> Counts(..counts, phases: counts.phases + 1)
      "market_status" ->
        Counts(..counts, market_statuses: counts.market_statuses + 1)
      "listing_halt" ->
        Counts(..counts, listing_halts: counts.listing_halts + 1)
      _ -> counts
    }
    let by_state = case fact.observed.value {
      ObservedValue(_) -> Counts(..by_kind, observed: by_kind.observed + 1)
      UnavailableValue(_) ->
        Counts(..by_kind, unavailable: by_kind.unavailable + 1)
      ConflictingValue(_, _) ->
        Counts(..by_kind, conflicting: by_kind.conflicting + 1)
    }
    Counts(..by_state, facts: by_state.facts + 1)
  })
}

fn typed_signature(value: TypedValue) -> String {
  value.category
  <> ":"
  <> option_text(value.other_label)
  <> ":"
  <> option_text(value.starts_at_local)
  <> ":"
  <> option_text(value.ends_at_local)
}

fn option_text(value: Option(String)) -> String {
  case value {
    Some(value) -> value
    None -> ""
  }
}

fn scope_json(value: Scope) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("scopeId", json.string(value.scope_id)),
    #("mic", json.string(identifier.mic_value(value.mic))),
    #("symbol", json.nullable(value.symbol, json.string)),
    #("identityStatus", json.string("caller_supplied_unverified")),
  ])
}

fn query_json(value: Query) -> Json {
  json.object([
    #("date", json.string(value.date)),
    #("localTime", json.string(value.local_time)),
    #("localTimestamp", json.string(value.local_timestamp)),
    #("timezone", json.string(time.timezone_name(value.timezone))),
    #("atUnixMilliseconds", json.int(value.at_unix_ms)),
    #(
      "localToUnixCoherence",
      json.string("caller_declared_unverified_no_offset_conversion"),
    ),
  ])
}

fn counts_json(value: Counts) -> Json {
  json.object([
    #("facts", json.int(value.facts)),
    #("scheduleFacts", json.int(value.schedules)),
    #("phaseFacts", json.int(value.phases)),
    #("marketStatusFacts", json.int(value.market_statuses)),
    #("listingHaltFacts", json.int(value.listing_halts)),
    #("observed", json.int(value.observed)),
    #("unavailable", json.int(value.unavailable)),
    #("conflicting", json.int(value.conflicting)),
  ])
}

fn assessment_json(
  schedule: ReportComparison,
  status: ReportComparison,
  halt: ReportComparison,
  active_phases: List(Fact),
  active_conflicts: List(PhaseAlternativeMatch),
  shortened: List(Fact),
) -> Json {
  json.object([
    #("scheduleReports", comparison_json(schedule)),
    #("marketStatusReports", comparison_json(status)),
    #("listingHaltReports", comparison_json(halt)),
    #("activeObservedPhases", json.array(active_phases, phase_match_json)),
    #(
      "activeConflictingPhaseAlternatives",
      json.array(active_conflicts, phase_alternative_match_json),
    ),
    #(
      "explicitShortenedScheduleFactIds",
      json.array(shortened, fn(fact) { json.string(fact.fact_id) }),
    ),
    #("phaseSelection", json.string("not_performed_all_matches_retained")),
    #("inferredScheduleState", json.null()),
    #("inferredMarketStatus", json.null()),
    #("inferredListingHalt", json.null()),
    #("correctnessVerdict", json.null()),
  ])
}

fn assessment_receipt_json(
  schedule: ReportComparison,
  status: ReportComparison,
  halt: ReportComparison,
  active_phases: List(Fact),
  active_conflicts: List(PhaseAlternativeMatch),
  shortened: List(Fact),
) -> Json {
  json.object([
    #("schedule", comparison_receipt_json(schedule)),
    #("marketStatus", comparison_receipt_json(status)),
    #("listingHalt", comparison_receipt_json(halt)),
    #(
      "activeObservedPhaseIds",
      json.array(active_phases, fn(fact) { json.string(fact.fact_id) }),
    ),
    #(
      "activeConflictingPhaseAlternatives",
      json.array(active_conflicts, phase_alternative_match_json),
    ),
    #(
      "shortenedScheduleIds",
      json.array(shortened, fn(fact) { json.string(fact.fact_id) }),
    ),
  ])
}

fn comparison_json(value: ReportComparison) -> Json {
  case value {
    NoReports ->
      json.object([
        #("state", json.string("not_reported")),
        #("factCount", json.int(0)),
        #("sourceCount", json.int(0)),
        #("points", json.array([], comparison_point_json)),
        #("reason", json.string("no_supplied_facts")),
      ])
    SingleReport(point) ->
      json.object([
        #("state", json.string("single_report")),
        #("factCount", json.int(1)),
        #("sourceCount", json.int(1)),
        #("points", json.array([point], comparison_point_json)),
        #(
          "reason",
          json.string("one_observed_report_no_cross_source_comparison"),
        ),
      ])
    ExactAgreement(_, points) ->
      json.object([
        #("state", json.string("exact_agreement")),
        #("factCount", json.int(list.length(points))),
        #("sourceCount", json.int(comparison_source_count(points))),
        #("points", json.array(points, comparison_point_json)),
        #(
          "reason",
          json.string("all_supplied_reports_have_identical_exact_values"),
        ),
      ])
    ExactDisagreement(points) ->
      json.object([
        #("state", json.string("exact_disagreement")),
        #("factCount", json.int(list.length(points))),
        #("sourceCount", json.int(comparison_source_count(points))),
        #("points", json.array(points, comparison_point_json)),
        #(
          "reason",
          json.string("supplied_observed_reports_have_distinct_exact_values"),
        ),
      ])
    IndeterminateComparison(reason, facts) ->
      json.object([
        #("state", json.string("indeterminate")),
        #("factCount", json.int(list.length(facts))),
        #("sourceCount", json.int(fact_source_count(facts))),
        #("points", json.array([], comparison_point_json)),
        #("factIds", json.array(facts, fn(fact) { json.string(fact.fact_id) })),
        #("reason", json.string(reason)),
      ])
  }
}

fn comparison_receipt_json(value: ReportComparison) -> Json {
  case value {
    NoReports -> json.object([#("state", json.string("not_reported"))])
    SingleReport(point) ->
      json.object([
        #("state", json.string("single_report")),
        #("factId", json.string(point.fact_id)),
        #("value", typed_value_json(point.value)),
      ])
    ExactAgreement(signature, points) ->
      json.object([
        #("state", json.string("exact_agreement")),
        #("signature", json.string(signature)),
        #(
          "factIds",
          json.array(points, fn(point) { json.string(point.fact_id) }),
        ),
      ])
    ExactDisagreement(points) ->
      json.object([
        #("state", json.string("exact_disagreement")),
        #("points", json.array(points, comparison_point_json)),
      ])
    IndeterminateComparison(reason, facts) ->
      json.object([
        #("state", json.string("indeterminate")),
        #("reason", json.string(reason)),
        #("factIds", json.array(facts, fn(fact) { json.string(fact.fact_id) })),
      ])
  }
}

fn comparison_point_json(value: ComparisonPoint) -> Json {
  json.object([
    #("factId", json.string(value.fact_id)),
    #("sourceId", json.string(value.source_id)),
    #("provider", json.string(value.provider)),
    #("value", typed_value_json(value.value)),
  ])
}

fn comparison_source_count(values: List(ComparisonPoint)) -> Int {
  values
  |> list.fold([], fn(source_ids, point) {
    append_unique(source_ids, point.source_id)
  })
  |> list.length
}

fn fact_source_count(values: List(Fact)) -> Int {
  values
  |> list.fold([], fn(source_ids, fact) {
    append_unique(source_ids, fact.source_record.source_id)
  })
  |> list.length
}

fn phase_match_json(value: Fact) -> Json {
  let assert ObservedValue(typed) = value.observed.value
  json.object([
    #("factId", json.string(value.fact_id)),
    #("sourceId", json.string(value.source_record.source_id)),
    #("provider", json.string(source.provider(value.source_record.safe.value))),
    #("value", typed_value_json(typed)),
  ])
}

fn phase_alternative_match_json(value: PhaseAlternativeMatch) -> Json {
  json.object([
    #("factId", json.string(value.fact_id)),
    #("sourceId", json.string(value.source_id)),
    #("provider", json.string(value.provider)),
    #("value", typed_value_json(value.value)),
    #("evidenceId", json.string(value.evidence_id)),
    #("conflictResolution", json.string("not_performed")),
  ])
}

fn fact_json(value: Fact, query: Query) -> Json {
  json.object([
    #("factId", json.string(value.fact_id)),
    #("kind", json.string(value.kind)),
    #("date", json.nullable(value.date, json.string)),
    #("value", value_state_json(value.observed.value)),
    #("observation", observation_json(value, query)),
    #(
      "queryIntervalRelation",
      json.nullable(
        query_interval_relation(value, query.local_timestamp),
        json.string,
      ),
    ),
  ])
}

fn fact_receipt_json(value: Fact) -> Json {
  json.object([
    #("factId", json.string(value.fact_id)),
    #("kind", json.string(value.kind)),
    #("date", json.nullable(value.date, json.string)),
    #("sourceId", json.string(value.source_record.source_id)),
    #("receiptHash", json.string(value.source_record.receipt_hash)),
    #(
      "asOfUnixMilliseconds",
      json.int(time.unix_milliseconds(value.observed.as_of)),
    ),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(value.observed.retrieved_at)),
    ),
    #("value", value_state_json(value.observed.value)),
  ])
}

fn observation_json(value: Fact, query: Query) -> Json {
  json.object([
    #("sourceId", json.string(value.source_record.source_id)),
    #("provider", json.string(source.provider(value.observed.source))),
    #("evidenceId", json.nullable(value.observed.evidence_id, json.string)),
    #(
      "asOfUnixMilliseconds",
      json.int(time.unix_milliseconds(value.observed.as_of)),
    ),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(value.observed.retrieved_at)),
    ),
    #("timezone", json.string(time.timezone_name(query.timezone))),
    #(
      "queryTemporalRelation",
      json.string(instant_relation(
        time.unix_milliseconds(value.observed.as_of),
        query.at_unix_ms,
      )),
    ),
    #("freshness", json.string("unknown_not_assessed")),
    #("entitlement", entitlement_json(value.observed.entitlement)),
    #("quality", json.string(quality_name(value.observed.quality))),
    #("unit", json.null()),
    #("adjustment", json.null()),
    #("session", json.nullable(value.observed.session, session_json)),
  ])
}

fn query_interval_relation(value: Fact, query_local: String) -> Option(String) {
  case value.kind, value.observed.value {
    "phase", ObservedValue(typed) -> Some(interval_relation(typed, query_local))
    _, _ -> None
  }
}

fn interval_relation(value: TypedValue, query_local: String) -> String {
  let assert Some(starts) = value.starts_at_local
  let assert Some(ends) = value.ends_at_local
  case string.compare(query_local, starts), string.compare(query_local, ends) {
    Lt, _ -> "query_before_interval"
    _, Lt -> "active_at_query"
    _, Eq | _, Gt -> "query_at_or_after_interval_end"
  }
}

fn instant_relation(as_of: Int, query_at: Int) -> String {
  case int.compare(as_of, query_at) {
    Lt -> "before_query"
    Eq -> "at_query"
    Gt -> "after_query"
  }
}

fn value_state_json(value: ValueState) -> Json {
  case value {
    ObservedValue(value) ->
      json.object([
        #("state", json.string("observed")),
        #("reported", typed_value_json(value)),
        #("reason", json.null()),
        #("alternatives", json.array([], alternative_json)),
      ])
    UnavailableValue(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("reported", json.null()),
        #("reason", json.string(reason)),
        #("alternatives", json.array([], alternative_json)),
      ])
    ConflictingValue(reason, alternatives) ->
      json.object([
        #("state", json.string("conflicting")),
        #("reported", json.null()),
        #("reason", json.string(reason)),
        #("alternatives", json.array(alternatives, alternative_json)),
        #("resolution", json.string("not_performed")),
      ])
  }
}

fn typed_value_json(value: TypedValue) -> Json {
  json.object([
    #("category", json.string(value.category)),
    #("otherLabel", json.nullable(value.other_label, json.string)),
    #("startsAtLocal", json.nullable(value.starts_at_local, json.string)),
    #("endsAtLocal", json.nullable(value.ends_at_local, json.string)),
  ])
}

fn alternative_json(value: Alternative) -> Json {
  json.object([
    #("value", typed_value_json(value.value)),
    #("evidenceId", json.string(value.evidence_id)),
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

fn session_json(value: market.Session) -> Json {
  json.string(case value {
    market.PreMarket -> "pre_market"
    market.Regular -> "regular"
    market.AfterHours -> "after_hours"
    market.Auction -> "auction"
    market.Closed -> "closed"
    market.OtherSession(label) -> "other:" <> market.label(label)
  })
}

fn source_record_json(value: SourceRecord, query_at: Int) -> Json {
  json.object([
    #("sourceId", json.string(value.source_id)),
    #("provider", json.string(source.provider(value.safe.value))),
    #("reference", json.string(source.reference(value.safe.value))),
    #("referenceRedacted", json.bool(value.safe.reference_redacted)),
    #("kind", json.string(source_kind_name(value.kind))),
    #("otherKind", json.nullable(source_other_kind(value.kind), json.string)),
    #("feed", json.string(value.feed)),
    #("coverage", coverage_json(value.coverage, query_at)),
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
    #("feed", json.string(value.feed)),
    #("coverage", coverage_receipt_json(value.coverage)),
    #("receiptHash", json.string(value.receipt_hash)),
  ])
}

fn coverage_json(value: Coverage, query_at: Int) -> Json {
  case value {
    ExactCoverage(start, end) ->
      json.object([
        #("state", json.string("exact_range")),
        #("startUnixMilliseconds", json.int(start)),
        #("endUnixMilliseconds", json.int(end)),
        #("reason", json.null()),
        #("coversQuery", json.bool(query_at >= start && query_at <= end)),
      ])
    UnknownCoverage(reason) ->
      json.object([
        #("state", json.string("unknown")),
        #("startUnixMilliseconds", json.null()),
        #("endUnixMilliseconds", json.null()),
        #("reason", json.string(reason)),
        #("coversQuery", json.null()),
      ])
  }
}

fn coverage_receipt_json(value: Coverage) -> Json {
  case value {
    ExactCoverage(start, end) ->
      json.object([
        #("state", json.string("exact_range")),
        #("startUnixMilliseconds", json.int(start)),
        #("endUnixMilliseconds", json.int(end)),
      ])
    UnknownCoverage(reason) ->
      json.object([
        #("state", json.string("unknown")),
        #("reason", json.string(reason)),
      ])
  }
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

fn market_timezone_name(track: finance_track.Track) -> String {
  case track {
    finance_track.Cn -> "Asia/Shanghai"
    finance_track.Hk -> "Asia/Hong_Kong"
    finance_track.Us -> "America/New_York"
  }
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

fn symbol_text(field: String, value: String) -> Result(String, DomainError) {
  use exact <- result.try(bounded_text(field, value, 100))
  case
    exact
    |> string.to_graphemes
    |> list.all(fn(character) { string.trim(character) == character })
  {
    True -> Ok(exact)
    False ->
      Error(InvalidField(field, "expected exact symbol without whitespace"))
  }
}

fn canonical_local_timestamp(
  field: String,
  value: String,
) -> Result(String, DomainError) {
  case string.split(value, "T") {
    [date, local_time] -> {
      use exact_date <- result.try(canonical_date(field, date))
      use exact_time <- result.try(canonical_time(field, local_time))
      Ok(exact_date <> "T" <> exact_time)
    }
    _ ->
      Error(InvalidField(field, "expected canonical local YYYY-MM-DDTHH:MM:SS"))
  }
}

fn canonical_date(field: String, value: String) -> Result(String, DomainError) {
  case string.split(value, "-") {
    [year_text, month_text, day_text] -> {
      use year <- result.try(parse_integer(field, year_text))
      use month <- result.try(parse_integer(field, month_text))
      use day <- result.try(parse_integer(field, day_text))
      let expected =
        pad_four(year) <> "-" <> pad_two(month) <> "-" <> pad_two(day)
      case
        value == expected
        && year >= 1
        && year <= 9999
        && month >= 1
        && month <= 12
        && day >= 1
        && day <= days_in_month(year, month)
      {
        True -> Ok(value)
        False ->
          Error(InvalidField(
            field,
            "expected canonical valid Gregorian YYYY-MM-DD",
          ))
      }
    }
    _ ->
      Error(InvalidField(field, "expected canonical valid Gregorian YYYY-MM-DD"))
  }
}

fn canonical_time(field: String, value: String) -> Result(String, DomainError) {
  case string.split(value, ":") {
    [hour_text, minute_text, second_text] -> {
      use hour <- result.try(parse_integer(field, hour_text))
      use minute <- result.try(parse_integer(field, minute_text))
      use second <- result.try(parse_integer(field, second_text))
      let expected =
        pad_two(hour) <> ":" <> pad_two(minute) <> ":" <> pad_two(second)
      case
        value == expected
        && hour >= 0
        && hour <= 23
        && minute >= 0
        && minute <= 59
        && second >= 0
        && second <= 59
      {
        True -> Ok(value)
        False -> Error(InvalidField(field, "expected canonical valid HH:MM:SS"))
      }
    }
    _ -> Error(InvalidField(field, "expected canonical valid HH:MM:SS"))
  }
}

fn parse_integer(field: String, value: String) -> Result(Int, DomainError) {
  int.parse(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "expected canonical numeric date or time components")
  })
}

fn days_in_month(year: Int, month: Int) -> Int {
  case month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
    4 | 6 | 9 | 11 -> 30
    2 ->
      case is_leap_year(year) {
        True -> 29
        False -> 28
      }
    _ -> 0
  }
}

fn is_leap_year(year: Int) -> Bool {
  year % 400 == 0 || { year % 4 == 0 && year % 100 != 0 }
}

fn pad_two(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn pad_four(value: Int) -> String {
  case value {
    value if value < 10 -> "000" <> int.to_string(value)
    value if value < 100 -> "00" <> int.to_string(value)
    value if value < 1000 -> "0" <> int.to_string(value)
    value -> int.to_string(value)
  }
}

fn parse_page(value: decode.PageInput) -> Result(Page, DomainError) {
  use _ <- result.try(integer_range(
    "page.offset",
    value.offset,
    0,
    maximum_facts,
  ))
  use _ <- result.try(integer_range(
    "page.limit",
    value.limit,
    1,
    maximum_output_rows,
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

fn count_bound(
  field: String,
  values: List(value),
  maximum: Int,
) -> Result(Nil, DomainError) {
  case list.length(values) <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "expected at most " <> int.to_string(maximum) <> " entries",
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

fn limitations() -> List(String) {
  [
    "caller_supplied_scope_and_source_identity_not_verified",
    "source_receipt_hash_is_not_origin_authentication",
    "licence_entitlement_and_coverage_are_caller_or_adapter_declarations",
    "mic_local_timestamp_and_unix_instant_coherence_is_not_proved",
    "only_supplied_schedule_phase_status_and_listing_halt_facts_are_retained",
    "unavailable_conflicting_and_overlapping_facts_are_not_resolved",
    "no_calendar_completion_phase_or_halt_inference_or_source_selection",
    "no_fetch_scheduling_alert_readiness_judgment_or_trade",
  ]
}
