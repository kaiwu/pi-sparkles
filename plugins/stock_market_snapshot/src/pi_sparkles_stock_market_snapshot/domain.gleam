import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/market
import finance_core/observation
import finance_core/source
import finance_core/time
import finance_math/exact as exact_math
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
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_stock_market_snapshot/decode

const maximum_safe_integer = 9_007_199_254_740_991

const maximum_members = 1000

const maximum_groups_per_member = 10

const maximum_alternatives = 10

const maximum_output_rows = 200

pub opaque type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
}

type SafeSource {
  SafeSource(value: source.SourceRef, reference_redacted: Bool)
}

type Coverage {
  CompleteCoverage(expected_members: Int)
  PartialCoverage(expected_members: Int, reason: String)
  UnknownCoverage(reason: String)
}

type ExactValue {
  ExactValue(raw: String, normalized: decimal.Decimal)
}

type PricePair {
  PricePair(
    current: ExactValue,
    previous_close: ExactValue,
    evidence_id: Option(String),
  )
}

type Direction {
  Advancing
  Declining
  Unchanged
}

type PriceState {
  ObservedPrice(
    pair: PricePair,
    delta: decimal.Decimal,
    change_fraction: decimal.Decimal,
    direction: Direction,
  )
  UnavailablePrice(reason: String)
  ConflictingPrice(reason: String, alternatives: List(PricePair))
}

type Measurement {
  ReportedMeasurement(value: ExactValue, unit: String, method: Option(String))
  UnavailableMeasurement(reason: String)
}

type Group {
  Group(kind: String, id: String, label: String)
}

type Member {
  Member(
    listing_id: String,
    mic: identifier.Mic,
    symbol: String,
    label: Option(String),
    groups: List(Group),
    price: PriceState,
    volume: Measurement,
    volatility: Measurement,
  )
}

type Counts {
  Counts(
    total: Int,
    observed: Int,
    advancing: Int,
    declining: Int,
    unchanged: Int,
    unavailable: Int,
    conflicting: Int,
  )
}

type GroupAggregate {
  GroupAggregate(group: Group, counts: Counts)
}

type Candidate {
  Candidate(member: Member, change_fraction: decimal.Decimal)
}

type Calculation {
  Calculation(
    scale: Int,
    rounding: decimal.RoundingMode,
    rounding_name: String,
    extrema_limit: Int,
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
  "Invalid exact market-snapshot field " <> field <> ": " <> reason
}

pub fn run(input: decode.Input) -> Result(Response, DomainError) {
  use track <- result.try(parse_track(input.track))
  use market_mic <- result.try(parse_mic("market.mic", input.market.mic))
  use _ <- result.try(validate_track_mic(track, market_mic, "market.mic"))
  use scope_kind <- result.try(scope_kind(input.market.scope_kind))
  use scope_id <- result.try(bounded_text(
    "market.scopeId",
    input.market.scope_id,
    200,
  ))
  use market_label <- result.try(bounded_text(
    "market.label",
    input.market.label,
    500,
  ))
  use calculation <- result.try(calculation(input.calculation))
  use _ <- result.try(count_bound("members", input.members, maximum_members))
  use provider <- result.try(bounded_text(
    "source.provider",
    input.source.provider,
    200,
  ))
  use feed <- result.try(bounded_text("source.feed", input.source.feed, 200))
  use kind <- result.try(source_kind(input.source))
  use safe_source <- result.try(make_safe_source(
    provider,
    input.source.reference,
    kind,
  ))
  use receipt <- result.try(sha("source.receiptHash", input.source.receipt_hash))
  use licence <- result.try(licence(input.source.licence))
  use entitlement <- result.try(entitlement(input.source.entitlement))
  use provider_timestamp <- result.try(bounded_text(
    "snapshot.providerTimestamp",
    input.snapshot.provider_timestamp,
    100,
  ))
  use as_of <- result.try(instant(
    "snapshot.asOfUnixMilliseconds",
    input.snapshot.as_of_unix_ms,
  ))
  use retrieved_at <- result.try(instant(
    "snapshot.retrievedAtUnixMilliseconds",
    input.snapshot.retrieved_at_unix_ms,
  ))
  use _ <- result.try(
    case input.snapshot.retrieved_at_unix_ms >= input.snapshot.as_of_unix_ms {
      True -> Ok(Nil)
      False ->
        Error(InvalidField(
          "snapshot.retrievedAtUnixMilliseconds",
          "must not precede snapshot.asOfUnixMilliseconds",
        ))
    },
  )
  use snapshot_currency <- result.try(parse_currency(input.snapshot.currency))
  use snapshot_session <- result.try(session(input.snapshot.session))
  use coverage <- result.try(coverage(
    input.snapshot.coverage,
    list.length(input.members),
  ))
  use members <- result.try(
    prepare_members(input.members, market_mic, calculation, 0, []),
  )
  use _ <- result.try(validate_unique_listings(members))
  let receipt_text = identity.sha256_value(receipt)
  let timezone = market_timezone(track)
  let observations =
    observe_members(
      members,
      as_of,
      retrieved_at,
      timezone,
      safe_source.value,
      receipt_text,
      entitlement,
      snapshot_session,
    )
  let overall = counts(observations)
  use groups <- result.try(group_aggregates(observations, []))
  let candidates = candidates(observations, [])
  let maximum = extreme(candidates, Gt)
  let minimum = extreme(candidates, Lt)
  use page <- result.try(page(input.page))
  let total = list.length(observations)
  let selected = observations |> list.drop(page.offset) |> list.take(page.limit)
  let returned = list.length(selected)
  let next_offset = case page.offset + returned < total {
    True -> Some(page.offset + returned)
    False -> None
  }
  let aggregate_projection =
    json.object([
      #("track", json.string(finance_track.name(track))),
      #("mic", json.string(identifier.mic_value(market_mic))),
      #("scopeKind", json.string(scope_kind)),
      #("scopeId", json.string(scope_id)),
      #("asOfUnixMilliseconds", json.int(time.unix_milliseconds(as_of))),
      #("sourceReceiptHash", json.string(receipt_text)),
      #("coverage", coverage_json(coverage, total)),
      #("overall", aggregate_json(overall, calculation)),
      #(
        "groups",
        json.array(groups, fn(value) {
          group_aggregate_json(value, calculation)
        }),
      ),
      #(
        "changeExtrema",
        extrema_json(candidates, maximum, minimum, calculation.extrema_limit),
      ),
    ])
  let assert Ok(calculation_receipt) =
    aggregate_projection |> json.to_string |> hash.text
  let limitations = limitations()
  use context <- result.try(
    track_context.new(
      track: track,
      market_scope: finance_track.name(track) <> "_stock_market_snapshot",
      venue_mic: Some(market_mic),
      board: None,
      timezone: Some(timezone),
      source_language: source_language(track),
      providers: [provider],
      entitlement: context_entitlement(entitlement),
      limitations: limitations,
    )
    |> result.map_error(fn(error) {
      InvalidField("trackContext", string.inspect(error))
    }),
  )
  Ok(Response(
    finance_track.name(track)
      <> " market snapshot | "
      <> scope_id
      <> " @ "
      <> identifier.mic_value(market_mic)
      <> " | advancing "
      <> int.to_string(overall.advancing)
      <> ", declining "
      <> int.to_string(overall.declining)
      <> ", unchanged "
      <> int.to_string(overall.unchanged)
      <> "; interpretation belongs to the LLM",
    json.object(
      list.append(track_json.result_fields(context), [
        #("schemaVersion", json.int(1)),
        #("operation", json.string("market_snapshot")),
        #(
          "market",
          json.object([
            #("mic", json.string(identifier.mic_value(market_mic))),
            #("scopeKind", json.string(scope_kind)),
            #("scopeId", json.string(scope_id)),
            #("label", json.string(market_label)),
            #("identityStatus", json.string("caller_supplied_unverified")),
          ]),
        ),
        #(
          "snapshot",
          json.object([
            #("providerTimestamp", json.string(provider_timestamp)),
            #("asOfUnixMilliseconds", json.int(time.unix_milliseconds(as_of))),
            #(
              "retrievedAtUnixMilliseconds",
              json.int(time.unix_milliseconds(retrieved_at)),
            ),
            #("timezone", json.string(time.timezone_name(timezone))),
            #("currency", json.string(currency.code(snapshot_currency))),
            #("session", session_json(snapshot_session)),
            #("coverage", coverage_json(coverage, total)),
          ]),
        ),
        #(
          "calculation",
          json.object([
            #(
              "changeBasis",
              json.string("current_minus_previous_close_over_previous_close"),
            ),
            #("changeFractionScale", json.int(calculation.scale)),
            #("rounding", json.string(calculation.rounding_name)),
            #("directionDenominator", json.string("observed_price_rows_only")),
            #(
              "extremaPolicy",
              json.string("exact_maximum_and_minimum_with_input_order_ties"),
            ),
            #("extremaLimit", json.int(calculation.extrema_limit)),
            #(
              "receiptHash",
              json.string(identity.sha256_value(calculation_receipt)),
            ),
          ]),
        ),
        #("overall", aggregate_json(overall, calculation)),
        #(
          "groupAggregates",
          json.array(groups, fn(value) {
            group_aggregate_json(value, calculation)
          }),
        ),
        #(
          "changeExtrema",
          extrema_json(candidates, maximum, minimum, calculation.extrema_limit),
        ),
        #(
          "page",
          json.object([
            #("offset", json.int(page.offset)),
            #("limit", json.int(page.limit)),
            #("returned", json.int(returned)),
            #("total", json.int(total)),
            #("nextOffset", json.nullable(next_offset, json.int)),
            #("order", json.string("caller_or_provider_adapter_input_order")),
          ]),
        ),
        #(
          "members",
          json.array(selected, fn(value) {
            member_observation_json(value, snapshot_currency)
          }),
        ),
        #("source", source_json(safe_source, kind, feed, receipt_text)),
        #("licence", licence_json(licence)),
        #(
          "unknownFacts",
          json.array(
            [
              "listing_identity_authority",
              "membership_and_coverage_authority",
              "source_receipt_origin_authentication",
              "freshness_and_latency",
              "benchmark_selection",
              "fund_flow",
              "rotation_or_regime",
              "investment_rank_or_signal",
            ],
            json.string,
          ),
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

fn scope_kind(value: String) -> Result(String, DomainError) {
  case value {
    "venue" | "index" | "sector" | "industry" | "other" -> Ok(value)
    _ -> Error(InvalidField("market.scopeKind", "unsupported exact scope kind"))
  }
}

fn calculation(
  value: decode.CalculationInput,
) -> Result(Calculation, DomainError) {
  use _ <- result.try(integer_range(
    "calculation.changeFractionScale",
    value.change_fraction_scale,
    0,
    18,
  ))
  use rounding <- result.try(rounding(value.rounding))
  use _ <- result.try(integer_range(
    "calculation.extremaLimit",
    value.extrema_limit,
    1,
    50,
  ))
  Ok(Calculation(
    value.change_fraction_scale,
    rounding,
    value.rounding,
    value.extrema_limit,
  ))
}

fn rounding(value: String) -> Result(decimal.RoundingMode, DomainError) {
  case value {
    "half_even" -> Ok(decimal.HalfEven)
    "half_up" -> Ok(decimal.HalfUp)
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    _ ->
      Error(InvalidField("calculation.rounding", "unsupported rounding mode"))
  }
}

fn parse_currency(value: String) -> Result(currency.Currency, DomainError) {
  use parsed <- result.try(
    currency.from_code(value)
    |> result.map_error(fn(_) {
      InvalidField("snapshot.currency", "expected a three-letter currency code")
    }),
  )
  case currency.code(parsed) == value {
    True -> Ok(parsed)
    False ->
      Error(InvalidField(
        "snapshot.currency",
        "currency must already use its exact uppercase representation",
      ))
  }
}

fn session(value: decode.SessionInput) -> Result(market.Session, DomainError) {
  case value.state, value.other_label {
    "pre_market", None -> Ok(market.PreMarket)
    "regular", None -> Ok(market.Regular)
    "after_hours", None -> Ok(market.AfterHours)
    "auction", None -> Ok(market.Auction)
    "closed", None -> Ok(market.Closed)
    "other", Some(label) -> {
      use exact <- result.try(bounded_text(
        "snapshot.session.otherLabel",
        label,
        200,
      ))
      market.other_session(exact)
      |> result.map_error(fn(_) {
        InvalidField(
          "snapshot.session.otherLabel",
          "invalid exact session label",
        )
      })
    }
    "other", None ->
      Error(InvalidField(
        "snapshot.session.otherLabel",
        "other session requires otherLabel",
      ))
    _, Some(_) ->
      Error(InvalidField(
        "snapshot.session.otherLabel",
        "otherLabel is only allowed when session state is other",
      ))
    _, None ->
      Error(InvalidField("snapshot.session.state", "unsupported session state"))
  }
}

fn coverage(
  value: decode.CoverageInput,
  received_members: Int,
) -> Result(Coverage, DomainError) {
  case value.state, value.expected_members, value.reason {
    "complete", Some(expected), None -> {
      use _ <- result.try(integer_range(
        "snapshot.coverage.expectedMembers",
        expected,
        0,
        1_000_000,
      ))
      case expected == received_members {
        True -> Ok(CompleteCoverage(expected))
        False ->
          Error(InvalidField(
            "snapshot.coverage.expectedMembers",
            "complete coverage requires expectedMembers to equal supplied member count",
          ))
      }
    }
    "partial", Some(expected), Some(reason) -> {
      use _ <- result.try(integer_range(
        "snapshot.coverage.expectedMembers",
        expected,
        1,
        1_000_000,
      ))
      use exact_reason <- result.try(bounded_text(
        "snapshot.coverage.reason",
        reason,
        500,
      ))
      case expected > received_members {
        True -> Ok(PartialCoverage(expected, exact_reason))
        False ->
          Error(InvalidField(
            "snapshot.coverage.expectedMembers",
            "partial coverage requires expectedMembers greater than supplied member count",
          ))
      }
    }
    "unknown", None, Some(reason) -> {
      use exact_reason <- result.try(bounded_text(
        "snapshot.coverage.reason",
        reason,
        500,
      ))
      Ok(UnknownCoverage(exact_reason))
    }
    _, _, _ ->
      Error(InvalidField(
        "snapshot.coverage",
        "complete requires matching expectedMembers only; partial requires a larger expectedMembers and reason; unknown requires reason only",
      ))
  }
}

fn prepare_members(
  remaining: List(decode.MemberInput),
  market_mic: identifier.Mic,
  calculation: Calculation,
  index: Int,
  reversed: List(Member),
) -> Result(List(Member), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use member <- result.try(prepare_member(
        value,
        market_mic,
        calculation,
        index,
      ))
      prepare_members(rest, market_mic, calculation, index + 1, [
        member,
        ..reversed
      ])
    }
  }
}

fn prepare_member(
  value: decode.MemberInput,
  market_mic: identifier.Mic,
  calculation: Calculation,
  index: Int,
) -> Result(Member, DomainError) {
  let field = "members[" <> int.to_string(index) <> "]"
  use listing_id <- result.try(bounded_text(
    field <> ".listingId",
    value.listing_id,
    2000,
  ))
  use mic <- result.try(parse_mic(field <> ".mic", value.mic))
  use _ <- result.try(
    case identifier.mic_value(mic) == identifier.mic_value(market_mic) {
      True -> Ok(Nil)
      False ->
        Error(InvalidField(
          field <> ".mic",
          "must exactly match market.mic; this slice does not cross venues",
        ))
    },
  )
  use symbol <- result.try(symbol(field <> ".symbol", value.symbol))
  use label <- result.try(optional_bounded_text(
    field <> ".label",
    value.label,
    500,
  ))
  use _ <- result.try(count_bound(
    field <> ".groups",
    value.groups,
    maximum_groups_per_member,
  ))
  use groups <- result.try(prepare_groups(value.groups, field, 0, []))
  use price <- result.try(price(value.price, calculation, field <> ".price"))
  use volume <- result.try(volume(value.volume, field <> ".volume"))
  use volatility <- result.try(volatility(
    value.volatility,
    field <> ".volatility",
  ))
  Ok(Member(listing_id, mic, symbol, label, groups, price, volume, volatility))
}

fn prepare_groups(
  remaining: List(decode.GroupInput),
  member_field: String,
  index: Int,
  reversed: List(Group),
) -> Result(List(Group), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      let field = member_field <> ".groups[" <> int.to_string(index) <> "]"
      use kind <- result.try(group_kind(field <> ".kind", value.kind))
      use id <- result.try(bounded_text(field <> ".id", value.id, 200))
      use label <- result.try(bounded_text(field <> ".label", value.label, 500))
      use _ <- result.try(
        case
          list.any(reversed, fn(existing) {
            existing.kind == kind && existing.id == id
          })
        {
          False -> Ok(Nil)
          True ->
            Error(InvalidField(
              member_field <> ".groups",
              "duplicate group kind/id within one member",
            ))
        },
      )
      prepare_groups(rest, member_field, index + 1, [
        Group(kind, id, label),
        ..reversed
      ])
    }
  }
}

fn group_kind(field: String, value: String) -> Result(String, DomainError) {
  case value {
    "index" | "sector" | "industry" | "other" -> Ok(value)
    _ -> Error(InvalidField(field, "unsupported exact group kind"))
  }
}

fn price(
  value: decode.PriceInput,
  calculation: Calculation,
  field: String,
) -> Result(PriceState, DomainError) {
  use _ <- result.try(count_bound(
    field <> ".alternatives",
    value.alternatives,
    maximum_alternatives,
  ))
  case
    value.state,
    value.raw_current,
    value.raw_previous_close,
    value.reason,
    value.alternatives
  {
    "observed", Some(current), Some(previous), None, [] -> {
      use pair <- result.try(price_pair(current, previous, None, field))
      let delta =
        decimal.subtract(
          pair.current.normalized,
          pair.previous_close.normalized,
        )
      let assert Ok(change_fraction) =
        exact_math.growth(
          pair.current.normalized,
          pair.previous_close.normalized,
          calculation.scale,
          calculation.rounding,
        )
      let direction = case
        decimal.compare(pair.current.normalized, pair.previous_close.normalized)
      {
        Gt -> Advancing
        Lt -> Declining
        Eq -> Unchanged
      }
      Ok(ObservedPrice(pair, delta, change_fraction, direction))
    }
    "unavailable", None, None, Some(reason), [] -> {
      use exact <- result.try(bounded_text(field <> ".reason", reason, 500))
      Ok(UnavailablePrice(exact))
    }
    "conflicting", None, None, Some(reason), alternatives -> {
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
            "conflicting price requires at least two alternatives",
          ))
      })
      use parsed <- result.try(price_alternatives(alternatives, field, 0, []))
      Ok(ConflictingPrice(exact_reason, parsed))
    }
    _, _, _, _, _ ->
      Error(InvalidField(
        field,
        "observed requires direct current/previous values only; unavailable requires reason only; conflicting requires reason and at least two alternatives only",
      ))
  }
}

fn price_alternatives(
  remaining: List(decode.PriceAlternativeInput),
  field: String,
  index: Int,
  reversed: List(PricePair),
) -> Result(List(PricePair), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      let alternative_field =
        field <> ".alternatives[" <> int.to_string(index) <> "]"
      use evidence_id <- result.try(sha(
        alternative_field <> ".evidenceId",
        value.evidence_id,
      ))
      use pair <- result.try(price_pair(
        value.raw_current,
        value.raw_previous_close,
        Some(identity.sha256_value(evidence_id)),
        alternative_field,
      ))
      use _ <- result.try(
        case
          list.any(reversed, fn(existing) {
            existing.evidence_id == pair.evidence_id
          })
        {
          False -> Ok(Nil)
          True ->
            Error(InvalidField(
              field <> ".alternatives",
              "alternative evidence IDs must be unique",
            ))
        },
      )
      price_alternatives(rest, field, index + 1, [pair, ..reversed])
    }
  }
}

fn price_pair(
  raw_current: String,
  raw_previous: String,
  evidence_id: Option(String),
  field: String,
) -> Result(PricePair, DomainError) {
  use current <- result.try(positive_exact(field <> ".rawCurrent", raw_current))
  use previous <- result.try(positive_exact(
    field <> ".rawPreviousClose",
    raw_previous,
  ))
  Ok(PricePair(current, previous, evidence_id))
}

fn volume(
  value: decode.MeasurementInput,
  field: String,
) -> Result(Measurement, DomainError) {
  case value.state, value.raw_value, value.unit, value.method, value.reason {
    "reported", Some(raw), Some(unit), None, None -> {
      use exact <- result.try(non_negative_exact(field <> ".rawValue", raw))
      use exact_unit <- result.try(volume_unit(field <> ".unit", unit))
      Ok(ReportedMeasurement(exact, exact_unit, None))
    }
    "unavailable", None, None, None, Some(reason) -> {
      use exact_reason <- result.try(bounded_text(
        field <> ".reason",
        reason,
        500,
      ))
      Ok(UnavailableMeasurement(exact_reason))
    }
    _, _, _, _, _ ->
      Error(InvalidField(
        field,
        "reported volume requires rawValue and unit only; unavailable requires reason only",
      ))
  }
}

fn volume_unit(field: String, value: String) -> Result(String, DomainError) {
  case value {
    "shares" | "contracts" | "provider_reported_unknown" -> Ok(value)
    _ -> Error(InvalidField(field, "unsupported explicit volume unit"))
  }
}

fn volatility(
  value: decode.MeasurementInput,
  field: String,
) -> Result(Measurement, DomainError) {
  case value.state, value.raw_value, value.unit, value.method, value.reason {
    "reported", Some(raw), Some(unit), Some(method), None -> {
      use exact <- result.try(non_negative_exact(field <> ".rawValue", raw))
      use exact_unit <- result.try(volatility_unit(field <> ".unit", unit))
      use exact_method <- result.try(bounded_text(
        field <> ".method",
        method,
        200,
      ))
      Ok(ReportedMeasurement(exact, exact_unit, Some(exact_method)))
    }
    "unavailable", None, None, None, Some(reason) -> {
      use exact_reason <- result.try(bounded_text(
        field <> ".reason",
        reason,
        500,
      ))
      Ok(UnavailableMeasurement(exact_reason))
    }
    _, _, _, _, _ ->
      Error(InvalidField(
        field,
        "reported volatility requires rawValue, unit, and method; unavailable requires reason only",
      ))
  }
}

fn volatility_unit(
  field: String,
  value: String,
) -> Result(String, DomainError) {
  case value {
    "fraction" | "percentage_points" -> Ok(value)
    _ -> Error(InvalidField(field, "unsupported explicit volatility unit"))
  }
}

fn positive_exact(
  field: String,
  value: String,
) -> Result(ExactValue, DomainError) {
  use exact <- result.try(exact(field, value))
  case decimal.compare(exact.normalized, decimal.zero()) {
    Gt -> Ok(exact)
    Eq | Lt -> Error(InvalidField(field, "expected a positive exact decimal"))
  }
}

fn non_negative_exact(
  field: String,
  value: String,
) -> Result(ExactValue, DomainError) {
  use exact <- result.try(exact(field, value))
  case decimal.compare(exact.normalized, decimal.zero()) {
    Gt | Eq -> Ok(exact)
    Lt -> Error(InvalidField(field, "expected a non-negative exact decimal"))
  }
}

fn exact(field: String, value: String) -> Result(ExactValue, DomainError) {
  use raw <- result.try(bounded_text(field, value, 500))
  decimal.parse(raw)
  |> result.map(fn(value) { ExactValue(raw, value) })
  |> result.map_error(fn(_) {
    InvalidField(field, "expected an exact decimal lexeme")
  })
}

fn validate_unique_listings(values: List(Member)) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [current, ..rest] ->
      case
        list.any(rest, fn(other) { other.listing_id == current.listing_id })
      {
        True ->
          Error(InvalidField(
            "members",
            "listingId values must be unique within one snapshot",
          ))
        False -> validate_unique_listings(rest)
      }
  }
}

fn observe_members(
  members: List(Member),
  as_of: time.Instant,
  retrieved_at: time.Instant,
  timezone: time.Timezone,
  source_ref: source.SourceRef,
  evidence_id: String,
  entitlement: observation.Entitlement,
  session: market.Session,
) -> List(observation.Observation(Member)) {
  list.map(members, fn(member) {
    observation.Observation(
      value: member,
      as_of: as_of,
      retrieved_at: retrieved_at,
      timezone: Some(timezone),
      source: source_ref,
      evidence_id: Some(evidence_id),
      freshness: observation.UnknownFreshness,
      entitlement: entitlement,
      quality: observation.Reported,
      unit: None,
      adjustment: None,
      session: Some(session),
    )
  })
}

fn counts(values: List(observation.Observation(Member))) -> Counts {
  list.fold(values, empty_counts(), fn(accumulator, observed) {
    add_price(accumulator, observed.value.price)
  })
}

fn empty_counts() -> Counts {
  Counts(0, 0, 0, 0, 0, 0, 0)
}

fn add_price(value: Counts, price: PriceState) -> Counts {
  case price {
    ObservedPrice(_, _, _, Advancing) ->
      Counts(
        ..value,
        total: value.total + 1,
        observed: value.observed + 1,
        advancing: value.advancing + 1,
      )
    ObservedPrice(_, _, _, Declining) ->
      Counts(
        ..value,
        total: value.total + 1,
        observed: value.observed + 1,
        declining: value.declining + 1,
      )
    ObservedPrice(_, _, _, Unchanged) ->
      Counts(
        ..value,
        total: value.total + 1,
        observed: value.observed + 1,
        unchanged: value.unchanged + 1,
      )
    UnavailablePrice(_) ->
      Counts(
        ..value,
        total: value.total + 1,
        unavailable: value.unavailable + 1,
      )
    ConflictingPrice(_, _) ->
      Counts(
        ..value,
        total: value.total + 1,
        conflicting: value.conflicting + 1,
      )
  }
}

fn group_aggregates(
  remaining: List(observation.Observation(Member)),
  aggregates: List(GroupAggregate),
) -> Result(List(GroupAggregate), DomainError) {
  case remaining {
    [] -> Ok(aggregates)
    [observed, ..rest] -> {
      use updated <- result.try(add_groups(
        observed.value.groups,
        observed.value.price,
        aggregates,
      ))
      group_aggregates(rest, updated)
    }
  }
}

fn add_groups(
  remaining: List(Group),
  price: PriceState,
  aggregates: List(GroupAggregate),
) -> Result(List(GroupAggregate), DomainError) {
  case remaining {
    [] -> Ok(aggregates)
    [group, ..rest] -> {
      use updated <- result.try(upsert_group(aggregates, group, price))
      add_groups(rest, price, updated)
    }
  }
}

fn upsert_group(
  aggregates: List(GroupAggregate),
  group: Group,
  price: PriceState,
) -> Result(List(GroupAggregate), DomainError) {
  case aggregates {
    [] -> Ok([GroupAggregate(group, add_price(empty_counts(), price))])
    [current, ..rest]
      if current.group.kind == group.kind && current.group.id == group.id
    ->
      case current.group.label == group.label {
        True ->
          Ok([
            GroupAggregate(current.group, add_price(current.counts, price)),
            ..rest
          ])
        False ->
          Error(InvalidField(
            "members.groups",
            "one group kind/id has conflicting labels",
          ))
      }
    [current, ..rest] -> {
      use updated <- result.try(upsert_group(rest, group, price))
      Ok([current, ..updated])
    }
  }
}

fn candidates(
  remaining: List(observation.Observation(Member)),
  reversed: List(Candidate),
) -> List(Candidate) {
  case remaining {
    [] -> list.reverse(reversed)
    [observed, ..rest] ->
      case observed.value.price {
        ObservedPrice(_, _, fraction, _) ->
          candidates(rest, [Candidate(observed.value, fraction), ..reversed])
        _ -> candidates(rest, reversed)
      }
  }
}

fn extreme(values: List(Candidate), wanted: Order) -> Option(decimal.Decimal) {
  case values {
    [] -> None
    [first, ..rest] -> Some(extreme_loop(rest, first.change_fraction, wanted))
  }
}

fn extreme_loop(
  remaining: List(Candidate),
  selected: decimal.Decimal,
  wanted: Order,
) -> decimal.Decimal {
  case remaining {
    [] -> selected
    [current, ..rest] ->
      case decimal.compare(current.change_fraction, selected) == wanted {
        True -> extreme_loop(rest, current.change_fraction, wanted)
        False -> extreme_loop(rest, selected, wanted)
      }
  }
}

fn page(value: decode.PageInput) -> Result(Page, DomainError) {
  use _ <- result.try(integer_range(
    "page.offset",
    value.offset,
    0,
    maximum_members,
  ))
  use _ <- result.try(integer_range(
    "page.limit",
    value.limit,
    1,
    maximum_output_rows,
  ))
  Ok(Page(value.offset, value.limit))
}

fn aggregate_json(value: Counts, calculation: Calculation) -> Json {
  json.object([
    #("totalMembers", json.int(value.total)),
    #("observedPriceMembers", json.int(value.observed)),
    #("advancing", json.int(value.advancing)),
    #("declining", json.int(value.declining)),
    #("unchanged", json.int(value.unchanged)),
    #("unavailable", json.int(value.unavailable)),
    #("conflicting", json.int(value.conflicting)),
    #("advanceDeclineDifference", json.int(value.advancing - value.declining)),
    #(
      "fractions",
      fraction_json(value, calculation.scale, calculation.rounding),
    ),
  ])
}

fn fraction_json(
  value: Counts,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> Json {
  case value.observed {
    0 ->
      json.object([
        #("denominator", json.string("observed_price_rows_only")),
        #("observedRows", json.int(0)),
        #("advancing", json.null()),
        #("declining", json.null()),
        #("unchanged", json.null()),
        #("unavailableReason", json.string("no_observed_price_rows")),
      ])
    observed ->
      json.object([
        #("denominator", json.string("observed_price_rows_only")),
        #("observedRows", json.int(observed)),
        #(
          "advancing",
          count_fraction(value.advancing, observed, scale, rounding),
        ),
        #(
          "declining",
          count_fraction(value.declining, observed, scale, rounding),
        ),
        #(
          "unchanged",
          count_fraction(value.unchanged, observed, scale, rounding),
        ),
        #("unavailableReason", json.null()),
      ])
  }
}

fn count_fraction(
  numerator: Int,
  denominator: Int,
  scale: Int,
  rounding: decimal.RoundingMode,
) -> Json {
  let assert Ok(value) =
    exact_math.ratio(
      decimal_from_int(numerator),
      decimal_from_int(denominator),
      scale,
      rounding,
    )
  json.string(decimal.to_string(value))
}

fn decimal_from_int(value: Int) -> decimal.Decimal {
  let assert Ok(parsed) = value |> int.to_string |> decimal.parse
  parsed
}

fn group_aggregate_json(
  value: GroupAggregate,
  calculation: Calculation,
) -> Json {
  json.object([
    #("kind", json.string(value.group.kind)),
    #("id", json.string(value.group.id)),
    #("label", json.string(value.group.label)),
    #("breadth", aggregate_json(value.counts, calculation)),
  ])
}

fn extrema_json(
  candidates: List(Candidate),
  maximum: Option(decimal.Decimal),
  minimum: Option(decimal.Decimal),
  limit: Int,
) -> Json {
  json.object([
    #("scope", json.string("supplied_observed_rows_only")),
    #("order", json.string("caller_or_provider_adapter_input_order_for_ties")),
    #("maximum", extreme_side_json(candidates, maximum, limit)),
    #("minimum", extreme_side_json(candidates, minimum, limit)),
  ])
}

fn extreme_side_json(
  candidates: List(Candidate),
  value: Option(decimal.Decimal),
  limit: Int,
) -> Json {
  case value {
    None ->
      json.object([
        #("changeFraction", json.null()),
        #("matchingCount", json.int(0)),
        #("returned", json.int(0)),
        #("omitted", json.int(0)),
        #("members", json.array([], fn(value: Json) { value })),
        #("unavailableReason", json.string("no_observed_price_rows")),
      ])
    Some(value) -> {
      let matches =
        list.filter(candidates, fn(candidate) {
          decimal.compare(candidate.change_fraction, value) == Eq
        })
      let selected = list.take(matches, limit)
      json.object([
        #("changeFraction", json.string(decimal.to_string(value))),
        #("matchingCount", json.int(list.length(matches))),
        #("returned", json.int(list.length(selected))),
        #("omitted", json.int(list.length(matches) - list.length(selected))),
        #("members", json.array(selected, candidate_json)),
        #("unavailableReason", json.null()),
      ])
    }
  }
}

fn candidate_json(value: Candidate) -> Json {
  json.object([
    #("listingId", json.string(value.member.listing_id)),
    #("mic", json.string(identifier.mic_value(value.member.mic))),
    #("symbol", json.string(value.member.symbol)),
    #("changeFraction", json.string(decimal.to_string(value.change_fraction))),
  ])
}

fn member_observation_json(
  observed: observation.Observation(Member),
  snapshot_currency: currency.Currency,
) -> Json {
  let member = observed.value
  json.object([
    #(
      "listing",
      json.object([
        #("listingId", json.string(member.listing_id)),
        #("mic", json.string(identifier.mic_value(member.mic))),
        #("symbol", json.string(member.symbol)),
        #("label", json.nullable(member.label, json.string)),
        #("identityStatus", json.string("caller_supplied_unverified")),
      ]),
    ),
    #("groups", json.array(member.groups, group_json)),
    #("price", price_json(member.price, snapshot_currency)),
    #("volume", measurement_json(member.volume)),
    #("volatility", measurement_json(member.volatility)),
    #(
      "observation",
      json.object([
        #(
          "asOfUnixMilliseconds",
          json.int(time.unix_milliseconds(observed.as_of)),
        ),
        #(
          "retrievedAtUnixMilliseconds",
          json.int(time.unix_milliseconds(observed.retrieved_at)),
        ),
        #(
          "timezone",
          json.nullable(observed.timezone, fn(zone) {
            json.string(time.timezone_name(zone))
          }),
        ),
        #("evidenceId", json.nullable(observed.evidence_id, json.string)),
        #("freshness", json.object([#("state", json.string("unknown"))])),
        #("entitlement", entitlement_json(observed.entitlement)),
        #("quality", json.string("reported")),
      ]),
    ),
  ])
}

fn group_json(value: Group) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("id", json.string(value.id)),
    #("label", json.string(value.label)),
  ])
}

fn price_json(value: PriceState, snapshot_currency: currency.Currency) -> Json {
  case value {
    ObservedPrice(pair, delta, fraction, direction) ->
      json.object([
        #("state", json.string("observed")),
        #("rawCurrent", json.string(pair.current.raw)),
        #(
          "normalizedCurrent",
          json.string(decimal.to_string(pair.current.normalized)),
        ),
        #("rawPreviousClose", json.string(pair.previous_close.raw)),
        #(
          "normalizedPreviousClose",
          json.string(decimal.to_string(pair.previous_close.normalized)),
        ),
        #("normalizedDelta", json.string(decimal.to_string(delta))),
        #("changeFraction", json.string(decimal.to_string(fraction))),
        #("direction", json.string(direction_name(direction))),
        #("currency", json.string(currency.code(snapshot_currency))),
        #("changeBasis", json.string("previous_close")),
        #("reason", json.null()),
        #("alternatives", json.array([], fn(value: Json) { value })),
      ])
    UnavailablePrice(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("rawCurrent", json.null()),
        #("normalizedCurrent", json.null()),
        #("rawPreviousClose", json.null()),
        #("normalizedPreviousClose", json.null()),
        #("normalizedDelta", json.null()),
        #("changeFraction", json.null()),
        #("direction", json.null()),
        #("currency", json.string(currency.code(snapshot_currency))),
        #("changeBasis", json.string("previous_close")),
        #("reason", json.string(reason)),
        #("alternatives", json.array([], fn(value: Json) { value })),
      ])
    ConflictingPrice(reason, alternatives) ->
      json.object([
        #("state", json.string("conflicting")),
        #("rawCurrent", json.null()),
        #("normalizedCurrent", json.null()),
        #("rawPreviousClose", json.null()),
        #("normalizedPreviousClose", json.null()),
        #("normalizedDelta", json.null()),
        #("changeFraction", json.null()),
        #("direction", json.null()),
        #("currency", json.string(currency.code(snapshot_currency))),
        #("changeBasis", json.string("previous_close")),
        #("reason", json.string(reason)),
        #("alternatives", json.array(alternatives, price_pair_json)),
      ])
  }
}

fn price_pair_json(value: PricePair) -> Json {
  json.object([
    #("rawCurrent", json.string(value.current.raw)),
    #(
      "normalizedCurrent",
      json.string(decimal.to_string(value.current.normalized)),
    ),
    #("rawPreviousClose", json.string(value.previous_close.raw)),
    #(
      "normalizedPreviousClose",
      json.string(decimal.to_string(value.previous_close.normalized)),
    ),
    #("evidenceId", json.nullable(value.evidence_id, json.string)),
  ])
}

fn measurement_json(value: Measurement) -> Json {
  case value {
    ReportedMeasurement(exact, unit, method) ->
      json.object([
        #("state", json.string("reported")),
        #("rawValue", json.string(exact.raw)),
        #("normalizedValue", json.string(decimal.to_string(exact.normalized))),
        #("unit", json.string(unit)),
        #("method", json.nullable(method, json.string)),
        #("reason", json.null()),
        #("interpretation", json.string("not_performed")),
      ])
    UnavailableMeasurement(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("rawValue", json.null()),
        #("normalizedValue", json.null()),
        #("unit", json.null()),
        #("method", json.null()),
        #("reason", json.string(reason)),
        #("interpretation", json.string("not_performed")),
      ])
  }
}

fn direction_name(value: Direction) -> String {
  case value {
    Advancing -> "advancing"
    Declining -> "declining"
    Unchanged -> "unchanged"
  }
}

fn coverage_json(value: Coverage, supplied_members: Int) -> Json {
  let #(state, expected, reason) = case value {
    CompleteCoverage(expected) -> #("complete", Some(expected), None)
    PartialCoverage(expected, reason) -> #(
      "partial",
      Some(expected),
      Some(reason),
    )
    UnknownCoverage(reason) -> #("unknown", None, Some(reason))
  }
  json.object([
    #("state", json.string(state)),
    #("expectedMembers", json.nullable(expected, json.int)),
    #("suppliedMembers", json.int(supplied_members)),
    #("reason", json.nullable(reason, json.string)),
    #("status", json.string("caller_or_provider_adapter_declared_unverified")),
  ])
}

fn session_json(value: market.Session) -> Json {
  let #(state, other_label) = case value {
    market.PreMarket -> #("pre_market", None)
    market.Regular -> #("regular", None)
    market.AfterHours -> #("after_hours", None)
    market.Auction -> #("auction", None)
    market.Closed -> #("closed", None)
    market.OtherSession(label) -> #("other", Some(market.label(label)))
  }
  json.object([
    #("state", json.string(state)),
    #("otherLabel", json.nullable(other_label, json.string)),
  ])
}

fn source_kind(
  value: decode.SourceInput,
) -> Result(source.SourceKind, DomainError) {
  case value.kind, value.other_kind {
    "official", None -> Ok(source.Official)
    "exchange", None -> Ok(source.Exchange)
    "regulator", None -> Ok(source.Regulator)
    "licensed_vendor", None -> Ok(source.LicensedVendor)
    "user_supplied", None -> Ok(source.UserSupplied)
    "synthetic", None -> Ok(source.Synthetic)
    "other", Some(kind) -> {
      use exact <- result.try(bounded_text("source.otherKind", kind, 200))
      Ok(source.Other(exact))
    }
    "other", None ->
      Error(InvalidField(
        "source.otherKind",
        "other source kind requires exact otherKind text",
      ))
    _, Some(_) ->
      Error(InvalidField(
        "source.otherKind",
        "otherKind is only allowed when kind is other",
      ))
    _, None ->
      Error(InvalidField("source.kind", "unsupported explicit source kind"))
  }
}

fn make_safe_source(
  provider: String,
  raw_reference: String,
  kind: source.SourceKind,
) -> Result(SafeSource, DomainError) {
  use _ <- result.try(bounded_text("source.reference", raw_reference, 8000))
  let projected = redact.url(raw_reference, [])
  case source.new(provider, projected, kind) {
    Ok(value) -> Ok(SafeSource(value, projected != raw_reference))
    Error(source.UnsafeReference) -> {
      use digest <- result.try(
        hash.text(raw_reference)
        |> result.map_error(fn(_) {
          InvalidField("source.reference", "safe reference hashing failed")
        }),
      )
      let fallback =
        "redacted-reference:sha256:" <> identity.sha256_value(digest)
      source.new(provider, fallback, kind)
      |> result.map(fn(value) { SafeSource(value, True) })
      |> result.map_error(fn(_) {
        InvalidField("source.reference", "could not construct a safe source")
      })
    }
    Error(_) ->
      Error(InvalidField(
        "source.reference",
        "expected trimmed non-empty source reference",
      ))
  }
}

fn entitlement(
  value: decode.EntitlementInput,
) -> Result(observation.Entitlement, DomainError) {
  case value.state, value.delay_milliseconds {
    "real_time", None -> Ok(observation.RealTime)
    "end_of_day", None -> Ok(observation.EndOfDay)
    "unknown", None -> Ok(observation.UnknownEntitlement)
    "delayed", Some(milliseconds) -> {
      use _ <- result.try(integer_range(
        "source.entitlement.delayMilliseconds",
        milliseconds,
        1,
        maximum_safe_integer,
      ))
      time.duration(milliseconds)
      |> result.map(observation.Delayed)
      |> result.map_error(fn(_) {
        InvalidField(
          "source.entitlement.delayMilliseconds",
          "delay is outside the supported duration range",
        )
      })
    }
    _, _ ->
      Error(InvalidField(
        "source.entitlement",
        "real_time, end_of_day, and unknown forbid delayMilliseconds; delayed requires it",
      ))
  }
}

fn licence(
  value: decode.LicenceInput,
) -> Result(evidence.Licence, DomainError) {
  use label <- result.try(bounded_text("source.licence.label", value.label, 500))
  use notes <- result.try(optional_bounded_text(
    "source.licence.notes",
    value.notes,
    4000,
  ))
  use redistribution <- result.try(redistribution(value.redistribution))
  Ok(evidence.Licence(label, redistribution, notes))
}

fn redistribution(
  value: String,
) -> Result(evidence.Redistribution, DomainError) {
  case value {
    "public_domain" -> Ok(evidence.PublicDomain)
    "attribution_required" -> Ok(evidence.AttributionRequired)
    "internal_use_only" -> Ok(evidence.InternalUseOnly)
    "no_redistribution" -> Ok(evidence.NoRedistribution)
    "unknown" -> Ok(evidence.UnknownRedistribution)
    _ ->
      Error(InvalidField(
        "source.licence.redistribution",
        "unsupported explicit redistribution state",
      ))
  }
}

fn source_json(
  safe: SafeSource,
  kind: source.SourceKind,
  feed: String,
  receipt_hash: String,
) -> Json {
  json.object([
    #("provider", json.string(source.provider(safe.value))),
    #("reference", json.string(source.reference(safe.value))),
    #("referenceRedacted", json.bool(safe.reference_redacted)),
    #("kind", json.string(source_kind_name(kind))),
    #("otherKind", json.nullable(source_other_kind(kind), json.string)),
    #("feed", json.string(feed)),
    #("receiptHash", json.string(receipt_hash)),
    #("receiptBinding", json.string("caller_supplied_unverified")),
  ])
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

fn context_entitlement(value: observation.Entitlement) -> String {
  case value {
    observation.RealTime -> "declared_real_time"
    observation.Delayed(_) -> "declared_delayed"
    observation.EndOfDay -> "declared_end_of_day"
    observation.UnknownEntitlement -> "unknown"
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

fn limitations() -> List(String) {
  [
    "caller_supplied_market_listing_group_and_membership_identity_not_verified",
    "coverage_entitlement_licence_and_receipt_origin_not_authenticated",
    "breadth_denominator_is_only_supplied_observed_price_rows",
    "partial_unknown_unavailable_and_conflicting_facts_are_not_filled",
    "reported_volume_is_not_fund_flow_or_liquidity",
    "reported_volatility_is_not_a_regime_or_risk_judgment",
    "change_extrema_are_not_investment_rankings",
    "no_network_provider_selection_cross_track_fallback_forecast_signal_or_trade",
  ]
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

fn symbol(field: String, value: String) -> Result(String, DomainError) {
  use exact <- result.try(bounded_text(field, value, 100))
  case
    exact
    |> string.to_graphemes
    |> list.all(fn(character) { string.trim(character) == character })
  {
    True -> Ok(exact)
    False ->
      Error(InvalidField(field, "expected an exact symbol without whitespace"))
  }
}

fn instant(field: String, value: Int) -> Result(time.Instant, DomainError) {
  use _ <- result.try(integer_range(field, value, 0, maximum_safe_integer))
  time.instant(value)
  |> result.map_error(fn(_) { InvalidField(field, "instant is out of range") })
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
