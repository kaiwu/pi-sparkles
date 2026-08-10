import finance_core/adjustment
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
import gleam/order.{Eq}
import gleam/result
import gleam/string
import pi_sparkles_finance_data_quality/decode

const maximum_safe_integer = 9_007_199_254_740_991

const maximum_sources = 50

const maximum_facts = 1000

const maximum_expected_coordinates = 1000

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

type FreshnessPolicy {
  AssessFreshness(evaluated_at_unix_ms: Int, maximum_age_milliseconds: Int)
  DoNotAssessFreshness(reason: String)
}

type Coordinate {
  Coordinate(observation_key: String, metric: String)
}

type UnitState {
  UnitState(
    kind: String,
    currency_code: Option(String),
    other_label: Option(String),
    key: String,
    core: Option(market.Unit),
  )
}

type AdjustmentState {
  AdjustmentState(
    kind: String,
    provider: Option(String),
    basis: Option(String),
    key: String,
    core: Option(adjustment.Adjustment),
  )
}

type ExactValue {
  ExactValue(raw: String, normalized: decimal.Decimal)
}

type Alternative {
  Alternative(value: ExactValue, evidence_id: String)
}

type ValueState {
  ObservedValue(value: ExactValue)
  UnavailableValue(reason: String)
  ConflictingValue(reason: String, alternatives: List(Alternative))
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

type Fact {
  Fact(
    fact_id: String,
    coordinate: Coordinate,
    source_record: SourceRecord,
    unit: UnitState,
    adjustment: AdjustmentState,
    observed: observation.Observation(ValueState),
    freshness_age_milliseconds: Option(Int),
  )
}

type DuplicateGroup {
  DuplicateGroup(
    source_id: String,
    provider: String,
    classification: String,
    fact_ids: List(String),
  )
}

type ProviderPoint {
  ProviderPoint(
    provider: String,
    source_id: String,
    fact_id: String,
    raw: String,
    normalized: decimal.Decimal,
    evidence_id: String,
  )
}

type ProviderGroup {
  ProviderGroup(provider: String, facts: List(Fact))
}

type ProviderComparison {
  ExactAgreement(normalized_value: String, points: List(ProviderPoint))
  ExactDisagreement(points: List(ProviderPoint))
  InsufficientProviders(provider_count: Int)
  IncompatibleContext(reason: String, provider_count: Int)
  IndeterminateComparison(reason: String, provider_count: Int)
}

type FreshnessCounts {
  FreshnessCounts(fresh: Int, stale: Int, unknown: Int)
}

type Assessment {
  Assessment(
    coordinate: Coordinate,
    expected: Bool,
    facts: List(Fact),
    duplicates: List(DuplicateGroup),
    unit_keys: List(String),
    adjustment_keys: List(String),
    freshness: FreshnessCounts,
    comparison: ProviderComparison,
  )
}

type SummaryCounts {
  SummaryCounts(
    coordinates: Int,
    missing: Int,
    duplicate_source_groups: Int,
    fresh: Int,
    stale: Int,
    unknown_freshness: Int,
    unit_incompatible: Int,
    adjustment_incompatible: Int,
    exact_agreements: Int,
    exact_disagreements: Int,
    insufficient_providers: Int,
    indeterminate_comparisons: Int,
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
  "Invalid exact finance-data-quality field " <> field <> ": " <> reason
}

pub fn run(input: decode.Input) -> Result(Response, DomainError) {
  use track <- result.try(parse_track(input.track))
  use scope <- result.try(parse_scope(input.scope, track))
  use freshness_policy <- result.try(parse_freshness_policy(
    input.freshness_policy,
  ))
  use _ <- result.try(count_range("sources", input.sources, 1, maximum_sources))
  use _ <- result.try(count_bound(
    "expectedCoordinates",
    input.expected_coordinates,
    maximum_expected_coordinates,
  ))
  use _ <- result.try(count_bound("facts", input.facts, maximum_facts))
  use sources <- result.try(prepare_sources(input.sources, 0, []))
  use _ <- result.try(validate_unique_sources(sources))
  use expected <- result.try(
    prepare_coordinates(
      input.expected_coordinates,
      "expectedCoordinates",
      0,
      [],
    ),
  )
  use _ <- result.try(validate_unique_coordinates(expected))
  use facts <- result.try(
    prepare_facts(
      input.facts,
      sources,
      freshness_policy,
      market_timezone(track),
      0,
      [],
    ),
  )
  use _ <- result.try(validate_unique_fact_ids(facts))
  let coordinates = coordinate_union(expected, facts)
  let assessments =
    list.map(coordinates, fn(coordinate) {
      assess_coordinate(coordinate, expected, facts)
    })
  let counts = summary_counts(assessments)
  use page <- result.try(parse_page(input.page))
  let selected = assessments |> list.drop(page.offset) |> list.take(page.limit)
  let returned = list.length(selected)
  let next_offset = case page.offset + returned < counts.coordinates {
    True -> Some(page.offset + returned)
    False -> None
  }
  let limitations = limitations()
  use context <- result.try(
    track_context.new(
      track: track,
      market_scope: finance_track.name(track) <> "_finance_data_quality",
      venue_mic: Some(scope.mic),
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
      #("scopeId", json.string(scope.scope_id)),
      #("mic", json.string(identifier.mic_value(scope.mic))),
      #("freshnessPolicy", freshness_policy_json(freshness_policy)),
      #("summary", summary_counts_json(counts, list.length(expected))),
      #("coordinates", json.array(assessments, assessment_receipt_json)),
    ])
  let assert Ok(calculation_receipt) =
    receipt_projection |> json.to_string |> hash.text
  Ok(Response(
    finance_track.name(track)
      <> " data quality | "
      <> scope.scope_id
      <> " | "
      <> int.to_string(list.length(facts))
      <> " facts / "
      <> int.to_string(counts.coordinates)
      <> " coordinates / "
      <> int.to_string(counts.exact_disagreements)
      <> " exact provider disagreements",
    json.object(
      list.append(track_json.result_fields(context), [
        #("schemaVersion", json.int(1)),
        #("operation", json.string("data_quality_check")),
        #("scope", scope_json(scope)),
        #("freshnessPolicy", freshness_policy_json(freshness_policy)),
        #(
          "expectation",
          json.object([
            #(
              "state",
              json.string(case expected {
                [] -> "not_assessed_no_expected_coordinates"
                _ -> "assessed_against_explicit_coordinates"
              }),
            ),
            #("expectedCoordinates", json.int(list.length(expected))),
            #("inference", json.string("not_performed")),
          ]),
        ),
        #("summary", summary_counts_json(counts, list.length(expected))),
        #(
          "calculation",
          json.object([
            #(
              "duplicateIdentity",
              json.string("same_observation_key_metric_and_source_id"),
            ),
            #(
              "providerComparison",
              json.string(
                "one_exact_observed_decimal_per_provider_with_identical_known_unit_and_adjustment",
              ),
            ),
            #("numericTolerance", json.string("none_exact_normalized_decimal")),
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
            #("total", json.int(counts.coordinates)),
            #("nextOffset", json.nullable(next_offset, json.int)),
            #(
              "order",
              json.string(
                "explicit_expected_order_then_first_seen_additional_coordinates",
              ),
            ),
          ]),
        ),
        #("coordinates", json.array(selected, assessment_json)),
        #("sources", json.array(sources, source_record_json)),
        #(
          "unknownFacts",
          json.array(
            [
              "listing_or_market_identity_authority",
              "source_receipt_origin_authentication",
              "licence_and_entitlement_verification",
              "expected_periods_when_not_explicitly_supplied",
              "calendar_and_corporate_action_truth",
              "source_correctness_or_preference",
            ],
            json.string,
          ),
        ),
        #("assessmentStatus", json.string("findings_only_no_quality_verdict")),
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
    "listing", Some(symbol) -> {
      use exact_symbol <- result.try(symbol_text("scope.symbol", symbol))
      Ok(Scope("listing", scope_id, mic, Some(exact_symbol)))
    }
    "market", None -> Ok(Scope("market", scope_id, mic, None))
    "listing", None ->
      Error(InvalidField("scope.symbol", "listing scope requires symbol"))
    "market", Some(_) ->
      Error(InvalidField("scope.symbol", "market scope forbids symbol"))
    _, _ -> Error(InvalidField("scope.kind", "expected listing or market"))
  }
}

fn parse_freshness_policy(
  value: decode.FreshnessPolicyInput,
) -> Result(FreshnessPolicy, DomainError) {
  case
    value.state,
    value.evaluated_at_unix_ms,
    value.maximum_age_milliseconds,
    value.reason
  {
    "assess", Some(evaluated), Some(maximum_age), None -> {
      use _ <- result.try(integer_range(
        "freshnessPolicy.evaluatedAtUnixMilliseconds",
        evaluated,
        0,
        maximum_safe_integer,
      ))
      use _ <- result.try(integer_range(
        "freshnessPolicy.maximumAgeMilliseconds",
        maximum_age,
        0,
        maximum_safe_integer,
      ))
      Ok(AssessFreshness(evaluated, maximum_age))
    }
    "not_assessed", None, None, Some(reason) -> {
      use exact <- result.try(bounded_text(
        "freshnessPolicy.reason",
        reason,
        500,
      ))
      Ok(DoNotAssessFreshness(exact))
    }
    _, _, _, _ ->
      Error(InvalidField(
        "freshnessPolicy",
        "assess requires evaluatedAtUnixMilliseconds and maximumAgeMilliseconds only; not_assessed requires reason only",
      ))
  }
}

fn prepare_coordinates(
  remaining: List(decode.CoordinateInput),
  prefix: String,
  index: Int,
  reversed: List(Coordinate),
) -> Result(List(Coordinate), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      let field = prefix <> "[" <> int.to_string(index) <> "]"
      use key <- result.try(bounded_text(
        field <> ".observationKey",
        value.observation_key,
        500,
      ))
      use metric <- result.try(bounded_text(
        field <> ".metric",
        value.metric,
        200,
      ))
      prepare_coordinates(rest, prefix, index + 1, [
        Coordinate(key, metric),
        ..reversed
      ])
    }
  }
}

fn validate_unique_coordinates(
  values: List(Coordinate),
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case list.any(rest, fn(other) { same_coordinate(current, other) }) {
        True ->
          Error(InvalidField(
            "expectedCoordinates",
            "observationKey and metric pairs must be unique",
          ))
        False -> validate_unique_coordinates(rest)
      }
  }
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

fn prepare_facts(
  remaining: List(decode.FactInput),
  sources: List(SourceRecord),
  freshness_policy: FreshnessPolicy,
  timezone: time.Timezone,
  index: Int,
  reversed: List(Fact),
) -> Result(List(Fact), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use fact <- result.try(prepare_fact(
        value,
        sources,
        freshness_policy,
        timezone,
        index,
      ))
      prepare_facts(rest, sources, freshness_policy, timezone, index + 1, [
        fact,
        ..reversed
      ])
    }
  }
}

fn prepare_fact(
  value: decode.FactInput,
  sources: List(SourceRecord),
  freshness_policy: FreshnessPolicy,
  timezone: time.Timezone,
  index: Int,
) -> Result(Fact, DomainError) {
  let field = "facts[" <> int.to_string(index) <> "]"
  use fact_id <- result.try(bounded_text(field <> ".factId", value.fact_id, 500))
  use key <- result.try(bounded_text(
    field <> ".observationKey",
    value.observation_key,
    500,
  ))
  use metric <- result.try(bounded_text(field <> ".metric", value.metric, 200))
  use source_id <- result.try(bounded_text(
    field <> ".sourceId",
    value.source_id,
    200,
  ))
  use source_record <- result.try(find_source(source_id, sources, field))
  use as_of <- result.try(instant(
    field <> ".asOfUnixMilliseconds",
    value.as_of_unix_ms,
  ))
  use retrieved_at <- result.try(instant(
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
  use unit <- result.try(parse_unit(value.unit, field <> ".unit"))
  use adjustment <- result.try(parse_adjustment(
    value.adjustment,
    field <> ".adjustment",
  ))
  use state <- result.try(parse_value(value.value, field <> ".value"))
  use freshness <- result.try(freshness(
    freshness_policy,
    value.as_of_unix_ms,
    field,
  ))
  let freshness_age_milliseconds = case freshness_policy {
    AssessFreshness(evaluated, _) -> Some(evaluated - value.as_of_unix_ms)
    DoNotAssessFreshness(_) -> None
  }
  let quality = case state {
    UnavailableValue(_) -> observation.Missing(observation.Unavailable)
    ObservedValue(_) | ConflictingValue(_, _) -> observation.Reported
  }
  let observed =
    observation.Observation(
      value: state,
      as_of: as_of,
      retrieved_at: retrieved_at,
      timezone: Some(timezone),
      source: source_record.safe.value,
      evidence_id: Some(source_record.receipt_hash),
      freshness: freshness,
      entitlement: source_record.entitlement,
      quality: quality,
      unit: unit.core,
      adjustment: adjustment.core,
      session: None,
    )
  Ok(Fact(
    fact_id,
    Coordinate(key, metric),
    source_record,
    unit,
    adjustment,
    observed,
    freshness_age_milliseconds,
  ))
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

fn parse_unit(
  value: decode.UnitInput,
  field: String,
) -> Result(UnitState, DomainError) {
  case value.kind, value.currency_code, value.other_label {
    "currency", Some(code), None -> {
      use exact <- result.try(parse_currency(field <> ".currencyCode", code))
      Ok(UnitState(
        "currency",
        Some(currency.code(exact)),
        None,
        "currency:" <> currency.code(exact),
        Some(market.Currency(exact)),
      ))
    }
    "currency_per_share", Some(code), None -> {
      use exact <- result.try(parse_currency(field <> ".currencyCode", code))
      Ok(UnitState(
        "currency_per_share",
        Some(currency.code(exact)),
        None,
        "currency_per_share:" <> currency.code(exact),
        Some(market.CurrencyPerShare(exact)),
      ))
    }
    "other", None, Some(label) -> {
      use exact <- result.try(bounded_text(field <> ".otherLabel", label, 200))
      use core <- result.try(
        market.custom_unit(exact)
        |> result.map_error(fn(_) {
          InvalidField(field <> ".otherLabel", "invalid exact custom unit")
        }),
      )
      Ok(UnitState("other", None, Some(exact), "other:" <> exact, Some(core)))
    }
    kind, None, None ->
      case kind {
        "scalar" -> Ok(UnitState(kind, None, None, kind, Some(market.Scalar)))
        "shares" -> Ok(UnitState(kind, None, None, kind, Some(market.Shares)))
        "contracts" ->
          Ok(UnitState(kind, None, None, kind, Some(market.Contracts)))
        "percent" -> Ok(UnitState(kind, None, None, kind, Some(market.Percent)))
        "basis_points" ->
          Ok(UnitState(kind, None, None, kind, Some(market.BasisPoints)))
        "ratio" -> Ok(UnitState(kind, None, None, kind, Some(market.Ratio)))
        "unknown" -> Ok(UnitState(kind, None, None, kind, None))
        _ ->
          Error(InvalidField(field <> ".kind", "unsupported exact unit kind"))
      }
    _, _, _ ->
      Error(InvalidField(
        field,
        "currency kinds require currencyCode; other requires otherLabel; all remaining kinds forbid both",
      ))
  }
}

fn parse_adjustment(
  value: decode.AdjustmentInput,
  field: String,
) -> Result(AdjustmentState, DomainError) {
  case value.kind, value.provider, value.basis {
    "provider_adjusted", Some(provider), Some(basis) -> {
      use exact_provider <- result.try(bounded_text(
        field <> ".provider",
        provider,
        200,
      ))
      use exact_basis <- result.try(bounded_text(field <> ".basis", basis, 500))
      use core <- result.try(
        adjustment.provider_adjusted(
          provider: exact_provider,
          basis: exact_basis,
        )
        |> result.map_error(fn(_) {
          InvalidField(field, "invalid exact provider adjustment basis")
        }),
      )
      Ok(AdjustmentState(
        "provider_adjusted",
        Some(exact_provider),
        Some(exact_basis),
        "provider_adjusted:" <> exact_provider <> ":" <> exact_basis,
        Some(core),
      ))
    }
    kind, None, None ->
      case kind {
        "raw" ->
          Ok(AdjustmentState(kind, None, None, kind, Some(adjustment.Raw)))
        "split_adjusted" ->
          Ok(AdjustmentState(
            kind,
            None,
            None,
            kind,
            Some(adjustment.SplitAdjusted),
          ))
        "dividend_adjusted" ->
          Ok(AdjustmentState(
            kind,
            None,
            None,
            kind,
            Some(adjustment.DividendAdjusted),
          ))
        "total_return_adjusted" ->
          Ok(AdjustmentState(
            kind,
            None,
            None,
            kind,
            Some(adjustment.TotalReturnAdjusted),
          ))
        "not_applicable" | "unknown" ->
          Ok(AdjustmentState(kind, None, None, kind, None))
        _ ->
          Error(InvalidField(
            field <> ".kind",
            "unsupported exact adjustment kind",
          ))
      }
    _, _, _ ->
      Error(InvalidField(
        field,
        "provider_adjusted requires provider and basis; all other states forbid both",
      ))
  }
}

fn parse_value(
  value: decode.ValueInput,
  field: String,
) -> Result(ValueState, DomainError) {
  use _ <- result.try(count_bound(
    field <> ".alternatives",
    value.alternatives,
    maximum_alternatives,
  ))
  case value.state, value.raw_value, value.reason, value.alternatives {
    "observed", Some(raw), None, [] -> {
      use exact <- result.try(exact_value(field <> ".rawValue", raw))
      Ok(ObservedValue(exact))
    }
    "unavailable", None, Some(reason), [] -> {
      use exact <- result.try(bounded_text(field <> ".reason", reason, 500))
      Ok(UnavailableValue(exact))
    }
    "conflicting", None, Some(reason), alternatives -> {
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
      use parsed <- result.try(prepare_alternatives(alternatives, field, 0, []))
      use _ <- result.try(validate_distinct_alternative_values(parsed, field))
      Ok(ConflictingValue(exact_reason, parsed))
    }
    _, _, _, _ ->
      Error(InvalidField(
        field,
        "observed requires rawValue only; unavailable requires reason only; conflicting requires reason and at least two alternatives only",
      ))
  }
}

fn prepare_alternatives(
  remaining: List(decode.AlternativeInput),
  field: String,
  index: Int,
  reversed: List(Alternative),
) -> Result(List(Alternative), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      let alternative_field =
        field <> ".alternatives[" <> int.to_string(index) <> "]"
      use exact <- result.try(exact_value(
        alternative_field <> ".rawValue",
        value.raw_value,
      ))
      use evidence_id <- result.try(sha(
        alternative_field <> ".evidenceId",
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
      prepare_alternatives(rest, field, index + 1, [
        Alternative(exact, evidence_text),
        ..reversed
      ])
    }
  }
}

fn validate_distinct_alternative_values(
  values: List(Alternative),
  field: String,
) -> Result(Nil, DomainError) {
  case values {
    [] | [_] ->
      Error(InvalidField(
        field <> ".alternatives",
        "conflicting value requires at least two alternatives",
      ))
    [first, ..rest] ->
      case
        list.any(rest, fn(value) {
          decimal.compare(value.value.normalized, first.value.normalized) != Eq
        })
      {
        True -> Ok(Nil)
        False ->
          Error(InvalidField(
            field <> ".alternatives",
            "conflicting alternatives must contain distinct normalized values",
          ))
      }
  }
}

fn freshness(
  policy: FreshnessPolicy,
  as_of_unix_ms: Int,
  field: String,
) -> Result(observation.Freshness, DomainError) {
  case policy {
    DoNotAssessFreshness(_) -> Ok(observation.UnknownFreshness)
    AssessFreshness(evaluated, maximum_age) ->
      case evaluated >= as_of_unix_ms {
        False ->
          Error(InvalidField(
            field <> ".asOfUnixMilliseconds",
            "must not follow freshnessPolicy.evaluatedAtUnixMilliseconds when freshness is assessed",
          ))
        True -> {
          let age = evaluated - as_of_unix_ms
          use age_duration <- result.try(duration(field <> ".freshnessAge", age))
          use maximum_duration <- result.try(duration(
            "freshnessPolicy.maximumAgeMilliseconds",
            maximum_age,
          ))
          case age > maximum_age {
            True -> Ok(observation.Stale(age_duration, maximum_duration))
            False -> Ok(observation.Fresh(maximum_duration))
          }
        }
      }
  }
}

fn coordinate_union(
  expected: List(Coordinate),
  facts: List(Fact),
) -> List(Coordinate) {
  list.fold(facts, expected, fn(accumulator, fact) {
    case
      list.any(accumulator, fn(value) {
        same_coordinate(value, fact.coordinate)
      })
    {
      True -> accumulator
      False -> list.append(accumulator, [fact.coordinate])
    }
  })
}

fn assess_coordinate(
  coordinate: Coordinate,
  expected: List(Coordinate),
  all_facts: List(Fact),
) -> Assessment {
  let facts =
    list.filter(all_facts, fn(fact) {
      same_coordinate(coordinate, fact.coordinate)
    })
  let unit_keys = unique_unit_keys(facts)
  let adjustment_keys = unique_adjustment_keys(facts)
  Assessment(
    coordinate,
    list.any(expected, fn(value) { same_coordinate(value, coordinate) }),
    facts,
    duplicate_groups(facts),
    unit_keys,
    adjustment_keys,
    freshness_counts(facts),
    provider_comparison(facts, unit_keys, adjustment_keys),
  )
}

fn duplicate_groups(facts: List(Fact)) -> List(DuplicateGroup) {
  let source_ids = unique_source_ids(facts)
  source_ids
  |> list.filter_map(fn(source_id) {
    let matches =
      list.filter(facts, fn(fact) { fact.source_record.source_id == source_id })
    case matches {
      [_, _, ..] -> {
        let provider = case matches {
          [first, ..] -> source.provider(first.source_record.safe.value)
          [] -> "unreachable"
        }
        Ok(DuplicateGroup(
          source_id,
          provider,
          duplicate_classification(matches),
          list.map(matches, fn(fact) { fact.fact_id }),
        ))
      }
      _ -> Error(Nil)
    }
  })
}

fn duplicate_classification(facts: List(Fact)) -> String {
  case facts {
    [] | [_] -> "not_duplicate"
    [first, ..rest] -> {
      let signature = duplicate_signature(first)
      case list.all(rest, fn(fact) { duplicate_signature(fact) == signature }) {
        True -> "exact_repeated_fact"
        False -> "divergent_or_mixed_rows"
      }
    }
  }
}

fn duplicate_signature(fact: Fact) -> String {
  int.to_string(time.unix_milliseconds(fact.observed.as_of))
  <> "|"
  <> int.to_string(time.unix_milliseconds(fact.observed.retrieved_at))
  <> "|"
  <> fact.unit.key
  <> "|"
  <> fact.adjustment.key
  <> "|"
  <> value_signature(fact.observed.value)
}

fn value_signature(value: ValueState) -> String {
  case value {
    ObservedValue(exact) -> "observed:" <> decimal.to_string(exact.normalized)
    UnavailableValue(reason) -> "unavailable:" <> reason
    ConflictingValue(reason, alternatives) ->
      "conflicting:"
      <> reason
      <> ":"
      <> {
        alternatives
        |> list.map(fn(value) {
          decimal.to_string(value.value.normalized) <> "@" <> value.evidence_id
        })
        |> string.join(",")
      }
  }
}

fn unique_source_ids(facts: List(Fact)) -> List(String) {
  list.fold(facts, [], fn(accumulator, fact) {
    append_unique(accumulator, fact.source_record.source_id)
  })
}

fn unique_unit_keys(facts: List(Fact)) -> List(String) {
  list.fold(facts, [], fn(accumulator, fact) {
    append_unique(accumulator, fact.unit.key)
  })
}

fn unique_adjustment_keys(facts: List(Fact)) -> List(String) {
  list.fold(facts, [], fn(accumulator, fact) {
    append_unique(accumulator, fact.adjustment.key)
  })
}

fn append_unique(values: List(String), value: String) -> List(String) {
  case list.contains(values, value) {
    True -> values
    False -> list.append(values, [value])
  }
}

fn freshness_counts(facts: List(Fact)) -> FreshnessCounts {
  list.fold(facts, FreshnessCounts(0, 0, 0), fn(accumulator, fact) {
    case fact.observed.freshness {
      observation.Fresh(_) ->
        FreshnessCounts(..accumulator, fresh: accumulator.fresh + 1)
      observation.Stale(_, _) ->
        FreshnessCounts(..accumulator, stale: accumulator.stale + 1)
      observation.UnknownFreshness ->
        FreshnessCounts(..accumulator, unknown: accumulator.unknown + 1)
    }
  })
}

fn provider_comparison(
  facts: List(Fact),
  unit_keys: List(String),
  adjustment_keys: List(String),
) -> ProviderComparison {
  let groups = provider_groups(facts)
  let provider_count = list.length(groups)
  case provider_count < 2 {
    True -> InsufficientProviders(provider_count)
    False ->
      case list.length(unit_keys) > 1, list.length(adjustment_keys) > 1 {
        True, _ -> IncompatibleContext("unit_incompatibility", provider_count)
        _, True ->
          IncompatibleContext("adjustment_incompatibility", provider_count)
        False, False ->
          case has_unknown_context(facts) {
            True ->
              IndeterminateComparison(
                "unknown_unit_or_adjustment",
                provider_count,
              )
            False ->
              case provider_points(groups, []) {
                Error(reason) -> IndeterminateComparison(reason, provider_count)
                Ok(points) ->
                  case points {
                    [] -> InsufficientProviders(0)
                    [first, ..rest] ->
                      case
                        list.all(rest, fn(point) {
                          decimal.compare(point.normalized, first.normalized)
                          == Eq
                        })
                      {
                        True ->
                          ExactAgreement(
                            decimal.to_string(first.normalized),
                            points,
                          )
                        False -> ExactDisagreement(points)
                      }
                  }
              }
          }
      }
  }
}

fn has_unknown_context(facts: List(Fact)) -> Bool {
  list.any(facts, fn(fact) {
    fact.unit.kind == "unknown" || fact.adjustment.kind == "unknown"
  })
}

fn provider_groups(facts: List(Fact)) -> List(ProviderGroup) {
  list.fold(facts, [], fn(groups, fact) { upsert_provider(groups, fact) })
}

fn upsert_provider(
  groups: List(ProviderGroup),
  fact: Fact,
) -> List(ProviderGroup) {
  let provider = source.provider(fact.source_record.safe.value)
  case groups {
    [] -> [ProviderGroup(provider, [fact])]
    [current, ..rest] if current.provider == provider -> [
      ProviderGroup(provider, list.append(current.facts, [fact])),
      ..rest
    ]
    [current, ..rest] -> [current, ..upsert_provider(rest, fact)]
  }
}

fn provider_points(
  groups: List(ProviderGroup),
  reversed: List(ProviderPoint),
) -> Result(List(ProviderPoint), String) {
  case groups {
    [] -> Ok(list.reverse(reversed))
    [group, ..rest] ->
      case group.facts {
        [fact] ->
          case fact.observed.value {
            ObservedValue(value) -> {
              let point =
                ProviderPoint(
                  group.provider,
                  fact.source_record.source_id,
                  fact.fact_id,
                  value.raw,
                  value.normalized,
                  fact.source_record.receipt_hash,
                )
              provider_points(rest, [point, ..reversed])
            }
            UnavailableValue(_) | ConflictingValue(_, _) ->
              Error("unavailable_or_conflicting_provider_fact")
          }
        _ -> Error("duplicate_provider_rows")
      }
  }
}

fn summary_counts(assessments: List(Assessment)) -> SummaryCounts {
  list.fold(
    assessments,
    SummaryCounts(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    fn(accumulator, assessment) {
      let missing = case assessment.facts {
        [] -> 1
        _ -> 0
      }
      let unit_incompatible = case list.length(assessment.unit_keys) > 1 {
        True -> 1
        False -> 0
      }
      let adjustment_incompatible = case
        list.length(assessment.adjustment_keys) > 1
      {
        True -> 1
        False -> 0
      }
      let #(agreements, disagreements, insufficient, indeterminate) = case
        assessment.comparison
      {
        ExactAgreement(_, _) -> #(1, 0, 0, 0)
        ExactDisagreement(_) -> #(0, 1, 0, 0)
        InsufficientProviders(_) -> #(0, 0, 1, 0)
        IncompatibleContext(_, _) | IndeterminateComparison(_, _) -> #(
          0,
          0,
          0,
          1,
        )
      }
      SummaryCounts(
        coordinates: accumulator.coordinates + 1,
        missing: accumulator.missing + missing,
        duplicate_source_groups: accumulator.duplicate_source_groups
          + list.length(assessment.duplicates),
        fresh: accumulator.fresh + assessment.freshness.fresh,
        stale: accumulator.stale + assessment.freshness.stale,
        unknown_freshness: accumulator.unknown_freshness
          + assessment.freshness.unknown,
        unit_incompatible: accumulator.unit_incompatible + unit_incompatible,
        adjustment_incompatible: accumulator.adjustment_incompatible
          + adjustment_incompatible,
        exact_agreements: accumulator.exact_agreements + agreements,
        exact_disagreements: accumulator.exact_disagreements + disagreements,
        insufficient_providers: accumulator.insufficient_providers
          + insufficient,
        indeterminate_comparisons: accumulator.indeterminate_comparisons
          + indeterminate,
      )
    },
  )
}

fn assessment_json(value: Assessment) -> Json {
  json.object([
    #("observationKey", json.string(value.coordinate.observation_key)),
    #("metric", json.string(value.coordinate.metric)),
    #("expected", json.bool(value.expected)),
    #("missing", json.bool(list.is_empty(value.facts))),
    #("factCount", json.int(list.length(value.facts))),
    #("facts", json.array(value.facts, fact_json)),
    #("duplicateGroups", json.array(value.duplicates, duplicate_group_json)),
    #("unitCompatibility", compatibility_json(value.unit_keys, "unit")),
    #(
      "adjustmentCompatibility",
      compatibility_json(value.adjustment_keys, "adjustment"),
    ),
    #("freshness", freshness_counts_json(value.freshness)),
    #("providerComparison", provider_comparison_json(value.comparison)),
  ])
}

fn assessment_receipt_json(value: Assessment) -> Json {
  json.object([
    #("observationKey", json.string(value.coordinate.observation_key)),
    #("metric", json.string(value.coordinate.metric)),
    #("expected", json.bool(value.expected)),
    #(
      "factIds",
      json.array(value.facts, fn(fact) { json.string(fact.fact_id) }),
    ),
    #(
      "sourceReceipts",
      json.array(value.facts, fn(fact) {
        json.string(fact.source_record.receipt_hash)
      }),
    ),
    #("unitKeys", json.array(value.unit_keys, json.string)),
    #("adjustmentKeys", json.array(value.adjustment_keys, json.string)),
    #(
      "providerComparisonState",
      json.string(provider_comparison_state(value.comparison)),
    ),
  ])
}

fn fact_json(fact: Fact) -> Json {
  json.object([
    #("factId", json.string(fact.fact_id)),
    #("sourceId", json.string(fact.source_record.source_id)),
    #("provider", json.string(source.provider(fact.source_record.safe.value))),
    #("value", value_json(fact.observed.value)),
    #("unit", unit_json(fact.unit)),
    #("adjustment", adjustment_json(fact.adjustment)),
    #(
      "observation",
      json.object([
        #(
          "asOfUnixMilliseconds",
          json.int(time.unix_milliseconds(fact.observed.as_of)),
        ),
        #(
          "retrievedAtUnixMilliseconds",
          json.int(time.unix_milliseconds(fact.observed.retrieved_at)),
        ),
        #(
          "timezone",
          json.nullable(fact.observed.timezone, fn(zone) {
            json.string(time.timezone_name(zone))
          }),
        ),
        #("evidenceId", json.nullable(fact.observed.evidence_id, json.string)),
        #(
          "freshness",
          freshness_json(
            fact.observed.freshness,
            fact.freshness_age_milliseconds,
          ),
        ),
        #("entitlement", entitlement_json(fact.observed.entitlement)),
        #("quality", quality_json(fact.observed.quality)),
      ]),
    ),
  ])
}

fn value_json(value: ValueState) -> Json {
  case value {
    ObservedValue(exact) ->
      json.object([
        #("state", json.string("observed")),
        #("rawValue", json.string(exact.raw)),
        #("normalizedValue", json.string(decimal.to_string(exact.normalized))),
        #("reason", json.null()),
        #("alternatives", json.array([], fn(value: Json) { value })),
      ])
    UnavailableValue(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("rawValue", json.null()),
        #("normalizedValue", json.null()),
        #("reason", json.string(reason)),
        #("alternatives", json.array([], fn(value: Json) { value })),
      ])
    ConflictingValue(reason, alternatives) ->
      json.object([
        #("state", json.string("conflicting")),
        #("rawValue", json.null()),
        #("normalizedValue", json.null()),
        #("reason", json.string(reason)),
        #("alternatives", json.array(alternatives, alternative_json)),
      ])
  }
}

fn alternative_json(value: Alternative) -> Json {
  json.object([
    #("rawValue", json.string(value.value.raw)),
    #("normalizedValue", json.string(decimal.to_string(value.value.normalized))),
    #("evidenceId", json.string(value.evidence_id)),
  ])
}

fn unit_json(value: UnitState) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("currencyCode", json.nullable(value.currency_code, json.string)),
    #("otherLabel", json.nullable(value.other_label, json.string)),
    #("compatibilityKey", json.string(value.key)),
  ])
}

fn adjustment_json(value: AdjustmentState) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("provider", json.nullable(value.provider, json.string)),
    #("basis", json.nullable(value.basis, json.string)),
    #("compatibilityKey", json.string(value.key)),
  ])
}

fn duplicate_group_json(value: DuplicateGroup) -> Json {
  json.object([
    #("sourceId", json.string(value.source_id)),
    #("provider", json.string(value.provider)),
    #("classification", json.string(value.classification)),
    #("count", json.int(list.length(value.fact_ids))),
    #("factIds", json.array(value.fact_ids, json.string)),
    #("resolution", json.string("not_performed")),
  ])
}

fn compatibility_json(keys: List(String), label: String) -> Json {
  let state = case keys {
    [] -> "unavailable_no_facts"
    ["unknown"] -> "unknown"
    [_] -> "compatible_exact_key"
    _ -> "incompatible_distinct_keys"
  }
  json.object([
    #("state", json.string(state)),
    #("distinctKeys", json.array(keys, json.string)),
    #("coercion", json.string("not_performed")),
    #("dimension", json.string(label)),
  ])
}

fn provider_comparison_json(value: ProviderComparison) -> Json {
  let #(reason, count, normalized, points) = case value {
    ExactAgreement(normalized, points) -> #(
      None,
      list.length(points),
      Some(normalized),
      points,
    )
    ExactDisagreement(points) -> #(None, list.length(points), None, points)
    InsufficientProviders(count) -> #(
      Some("fewer_than_two_providers"),
      count,
      None,
      [],
    )
    IncompatibleContext(reason, count) -> #(Some(reason), count, None, [])
    IndeterminateComparison(reason, count) -> #(Some(reason), count, None, [])
  }
  json.object([
    #("state", json.string(provider_comparison_state(value))),
    #("providerCount", json.int(count)),
    #("exactNormalizedValue", json.nullable(normalized, json.string)),
    #("reason", json.nullable(reason, json.string)),
    #("providers", json.array(points, provider_point_json)),
    #("selectedProvider", json.null()),
    #("correctnessVerdict", json.null()),
  ])
}

fn provider_comparison_state(value: ProviderComparison) -> String {
  case value {
    ExactAgreement(_, _) -> "exact_agreement"
    ExactDisagreement(_) -> "exact_disagreement"
    InsufficientProviders(_) -> "insufficient_providers"
    IncompatibleContext(_, _) -> "incompatible_context"
    IndeterminateComparison(_, _) -> "indeterminate"
  }
}

fn provider_point_json(value: ProviderPoint) -> Json {
  json.object([
    #("provider", json.string(value.provider)),
    #("sourceId", json.string(value.source_id)),
    #("factId", json.string(value.fact_id)),
    #("rawValue", json.string(value.raw)),
    #("normalizedValue", json.string(decimal.to_string(value.normalized))),
    #("evidenceId", json.string(value.evidence_id)),
  ])
}

fn freshness_json(
  value: observation.Freshness,
  age_milliseconds: Option(Int),
) -> Json {
  case value {
    observation.Fresh(maximum_age) ->
      json.object([
        #("state", json.string("fresh")),
        #(
          "maximumAgeMilliseconds",
          json.int(time.duration_milliseconds(maximum_age)),
        ),
        #("ageMilliseconds", json.nullable(age_milliseconds, json.int)),
      ])
    observation.Stale(age, maximum_age) ->
      json.object([
        #("state", json.string("stale")),
        #(
          "maximumAgeMilliseconds",
          json.int(time.duration_milliseconds(maximum_age)),
        ),
        #("ageMilliseconds", json.int(time.duration_milliseconds(age))),
      ])
    observation.UnknownFreshness ->
      json.object([
        #("state", json.string("unknown")),
        #("maximumAgeMilliseconds", json.null()),
        #("ageMilliseconds", json.null()),
      ])
  }
}

fn freshness_counts_json(value: FreshnessCounts) -> Json {
  json.object([
    #("fresh", json.int(value.fresh)),
    #("stale", json.int(value.stale)),
    #("unknown", json.int(value.unknown)),
  ])
}

fn quality_json(value: observation.Quality) -> Json {
  case value {
    observation.Reported -> json.string("reported")
    observation.Estimated -> json.string("estimated")
    observation.Restated -> json.string("restated")
    observation.Revised -> json.string("revised")
    observation.Missing(_) -> json.string("missing_unavailable")
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

fn freshness_policy_json(value: FreshnessPolicy) -> Json {
  case value {
    AssessFreshness(evaluated, maximum_age) ->
      json.object([
        #("state", json.string("assess")),
        #("evaluatedAtUnixMilliseconds", json.int(evaluated)),
        #("maximumAgeMilliseconds", json.int(maximum_age)),
        #("basis", json.string("evaluated_at_minus_as_of")),
        #("reason", json.null()),
      ])
    DoNotAssessFreshness(reason) ->
      json.object([
        #("state", json.string("not_assessed")),
        #("evaluatedAtUnixMilliseconds", json.null()),
        #("maximumAgeMilliseconds", json.null()),
        #("basis", json.string("not_performed")),
        #("reason", json.string(reason)),
      ])
  }
}

fn summary_counts_json(value: SummaryCounts, expected_count: Int) -> Json {
  json.object([
    #("facts", json.int(value.fresh + value.stale + value.unknown_freshness)),
    #("coordinates", json.int(value.coordinates)),
    #("expectedCoordinates", json.int(expected_count)),
    #("missingExpectedCoordinates", json.int(value.missing)),
    #("duplicateSourceGroups", json.int(value.duplicate_source_groups)),
    #(
      "freshness",
      json.object([
        #("fresh", json.int(value.fresh)),
        #("stale", json.int(value.stale)),
        #("unknown", json.int(value.unknown_freshness)),
      ]),
    ),
    #("unitIncompatibleCoordinates", json.int(value.unit_incompatible)),
    #(
      "adjustmentIncompatibleCoordinates",
      json.int(value.adjustment_incompatible),
    ),
    #(
      "providerComparisons",
      json.object([
        #("exactAgreements", json.int(value.exact_agreements)),
        #("exactDisagreements", json.int(value.exact_disagreements)),
        #("insufficientProviders", json.int(value.insufficient_providers)),
        #("indeterminate", json.int(value.indeterminate_comparisons)),
      ]),
    ),
    #("overallVerdict", json.null()),
  ])
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
        InvalidField(
          field <> ".delayMilliseconds",
          "delay is outside the supported duration range",
        )
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

fn unique_providers(values: List(SourceRecord)) -> List(String) {
  list.fold(values, [], fn(accumulator, value) {
    append_unique(accumulator, source.provider(value.safe.value))
  })
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

fn exact_value(
  field: String,
  value: String,
) -> Result(ExactValue, DomainError) {
  use raw <- result.try(bounded_text(field, value, 500))
  decimal.parse(raw)
  |> result.map(fn(normalized) { ExactValue(raw, normalized) })
  |> result.map_error(fn(_) {
    InvalidField(field, "expected an exact decimal lexeme")
  })
}

fn same_coordinate(left: Coordinate, right: Coordinate) -> Bool {
  left.observation_key == right.observation_key && left.metric == right.metric
}

fn parse_page(value: decode.PageInput) -> Result(Page, DomainError) {
  use _ <- result.try(integer_range("page.offset", value.offset, 0, 2000))
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

fn duration(field: String, value: Int) -> Result(time.Duration, DomainError) {
  time.duration(value)
  |> result.map_error(fn(_) { InvalidField(field, "duration is out of range") })
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
    "caller_supplied_scope_source_and_expected_coordinate_identity_not_verified",
    "source_receipt_hash_is_not_origin_authentication",
    "licence_and_entitlement_are_caller_or_adapter_declarations",
    "freshness_is_only_evaluated_at_minus_as_of_under_caller_policy",
    "missing_periods_are_only_explicit_expected_coordinate_omissions",
    "unit_and_adjustment_checks_use_exact_compatibility_keys_without_coercion",
    "provider_disagreement_is_not_a_source_correctness_or_preference_verdict",
    "no_network_selection_scoring_repair_interpolation_signal_or_trade",
  ]
}
