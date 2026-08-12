import finance_core/decimal.{type Decimal}
import finance_quant/common.{type Error, type Response}
import finance_replay/manifest
import finance_track
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/result

const maximum_members = 10_000

const maximum_predicates = 100

type PriceFact {
  PriceFact(
    state: String,
    current: Option(String),
    previous: Option(String),
    reason: Option(String),
  )
}

type TurnoverFact {
  TurnoverFact(
    state: String,
    raw: Option(String),
    unit: Option(String),
    reason: Option(String),
  )
}

type SnapshotMember {
  SnapshotMember(
    listing_id: String,
    mic: String,
    board: String,
    share_class: String,
    status: String,
    group_id: String,
    price: PriceFact,
    turnover: TurnoverFact,
    source_receipt: String,
  )
}

type SnapshotRequest {
  SnapshotRequest(
    snapshot_id: String,
    as_of_unix_ms: Int,
    retrieved_at_unix_ms: Int,
    coverage_state: String,
    expected_members: Option(Int),
    coverage_reason: Option(String),
    entitlement: String,
    licence: String,
    source_receipt: String,
    members: List(SnapshotMember),
  )
}

type Direction {
  Advanced
  Declined
  Unchanged
  Unresolved(reason: String)
}

type PreparedSnapshotMember {
  PreparedSnapshotMember(
    member: SnapshotMember,
    direction: Direction,
    turnover: Option(Decimal),
  )
}

type Counts {
  Counts(advanced: Int, declined: Int, unchanged: Int, unresolved: Int)
}

type ValueFact {
  ValueFact(
    field: String,
    unit: String,
    state: String,
    raw: Option(String),
    reason: Option(String),
    alternatives: List(String),
    known_at_unix_ms: Int,
    receipts: List(String),
  )
}

type ScreenRow {
  ScreenRow(
    listing_id: String,
    mic: String,
    board: String,
    share_class: String,
    status: String,
    membership_state: String,
    membership_reason: Option(String),
    membership_receipt: String,
    observation_id: String,
    values: List(ValueFact),
  )
}

type Predicate {
  Predicate(
    id: String,
    field: String,
    operator: String,
    threshold: String,
    unit: String,
  )
}

type ScreenRequest {
  ScreenRequest(
    binding: common.BindingInput,
    rows: List(ScreenRow),
    predicates: List(Predicate),
  )
}

type PreparedPredicate {
  PreparedPredicate(predicate: Predicate, threshold: Decimal)
}

type PredicateResult {
  PredicateResult(
    predicate: Predicate,
    state: String,
    reason: Option(String),
    raw: Option(String),
  )
}

type ScreenResult {
  ScreenResult(
    row: ScreenRow,
    relation: String,
    predicates: List(PredicateResult),
  )
}

pub fn market_snapshot(
  bytes: String,
  expected_sha256: String,
) -> Result(Response, Error) {
  use _ <- result.try(common.verify_packet(
    bytes,
    expected_sha256,
    "cn_market_snapshot_v1",
    "calculate_snapshot",
  ))
  use request <- result.try(common.parse(bytes, snapshot_decoder()))
  use _ <- result.try(common.non_empty("snapshotId", request.snapshot_id))
  use _ <- result.try(common.receipt("sourceReceipt", request.source_receipt))
  use _ <- result.try(common.non_empty("entitlement", request.entitlement))
  use _ <- result.try(common.non_empty("licence", request.licence))
  use _ <- result.try(common.bounded_count(
    "members",
    request.members,
    maximum_members,
  ))
  use _ <- result.try(validate_coverage(request))
  use prepared <- result.try(list.try_map(
    request.members,
    prepare_snapshot_member,
  ))
  let counts = list.fold(prepared, Counts(0, 0, 0, 0), count_direction)
  let duplicate_ids = duplicate_listing_ids(request.members)
  let groups = group_ids(request.members)
  let turnover_values =
    list.filter_map(prepared, fn(value) { value.turnover |> option_to_result })
  let turnover = list.fold(turnover_values, decimal.zero(), decimal.add)
  let fields = [
    #("schema", json.string("pi-sparkles/cn-market-snapshot-result")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string("calculate_snapshot")),
    #("track", json.string("cn")),
    #("snapshotId", json.string(request.snapshot_id)),
    #("asOfUnixMilliseconds", json.int(request.as_of_unix_ms)),
    #("retrievedAtUnixMilliseconds", json.int(request.retrieved_at_unix_ms)),
    #("coverage", coverage_json(request)),
    #("entitlement", json.string(request.entitlement)),
    #("licence", json.string(request.licence)),
    #("sourceReceipt", json.string(request.source_receipt)),
    #("memberCount", json.int(list.length(prepared))),
    #("directionCounts", counts_json(counts)),
    #(
      "observedTurnover",
      json.object([
        #("raw", json.string(decimal.to_string(turnover))),
        #("unit", json.string("CNY")),
        #("knownRowCount", json.int(list.length(turnover_values))),
        #(
          "unresolvedRowCount",
          json.int(list.length(prepared) - list.length(turnover_values)),
        ),
      ]),
    ),
    #("duplicateListingIds", json.array(duplicate_ids, json.string)),
    #(
      "groups",
      json.array(groups, fn(group_id) { group_json(group_id, prepared) }),
    ),
    #("members", json.array(prepared, prepared_snapshot_json)),
    #("availableOperations", json.array(["calculate_snapshot"], json.string)),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], json.string)),
    #(
      "limitations",
      json.array(
        [
          "supplied membership and coverage are retained declarations",
          "unavailable and conflicting prices are excluded from directional arithmetic",
          "turnover is the exact sum of supplied known CNY rows and is not fund flow",
          "no market completion, ranking, forecast, recommendation, or trade action is performed",
        ],
        json.string,
      ),
    ),
  ]
  Ok(common.response(
    "CN snapshot "
      <> request.snapshot_id
      <> " | "
      <> int.to_string(counts.advanced)
      <> " advance, "
      <> int.to_string(counts.declined)
      <> " decline, "
      <> int.to_string(counts.unresolved)
      <> " unresolved",
    common.content_bound(fields),
  ))
}

pub fn stock_screen(
  bytes: String,
  expected_sha256: String,
) -> Result(Response, Error) {
  use _ <- result.try(common.verify_packet(
    bytes,
    expected_sha256,
    "cn_stock_screener_v1",
    "screen",
  ))
  use request <- result.try(common.parse(bytes, screen_decoder()))
  use binding <- result.try(common.prepare_binding(request.binding))
  use _ <- result.try(case binding.track {
    finance_track.Cn -> Ok(Nil)
    _ -> Error(common.TrackMismatch("cn", finance_track.name(binding.track)))
  })
  use _ <- result.try(common.bounded_count(
    "rows",
    request.rows,
    maximum_members,
  ))
  use _ <- result.try(common.bounded_count(
    "predicates",
    request.predicates,
    maximum_predicates,
  ))
  use _ <- result.try(common.require_unique(
    "rows[].listingId",
    list.map(request.rows, fn(row) { row.listing_id }),
  ))
  use _ <- result.try(common.require_unique(
    "predicates[].id",
    list.map(request.predicates, fn(value) { value.id }),
  ))
  use predicates <- result.try(list.try_map(
    request.predicates,
    prepare_predicate,
  ))
  use rows <- result.try(
    list.try_map(request.rows, fn(row) {
      prepare_screen_row(row, binding, predicates)
    }),
  )
  let matched =
    rows |> list.filter(fn(row) { row.relation == "matched" }) |> list.length
  let not_matched =
    rows
    |> list.filter(fn(row) { row.relation == "not_matched" })
    |> list.length
  let unresolved = list.length(rows) - matched - not_matched
  let fields = [
    #("schema", json.string("pi-sparkles/cn-stock-screen-result")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string("screen")),
    #("binding", common.binding_json(binding)),
    #(
      "relationCounts",
      json.object([
        #("matched", json.int(matched)),
        #("notMatched", json.int(not_matched)),
        #("unresolved", json.int(unresolved)),
      ]),
    ),
    #("predicates", json.array(request.predicates, predicate_json)),
    #("rows", json.array(rows, screen_result_json)),
    #("availableOperations", json.array(["screen"], json.string)),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], json.string)),
    #(
      "limitations",
      json.array(
        [
          "membershipState is a caller-supplied projection bound to its exact receipt",
          "every row is retained; missing, late, conflicting, and unavailable facts are unresolved",
          "no default filter, ranking, score, recommendation, or backtest-validity verdict is produced",
        ],
        json.string,
      ),
    ),
  ]
  Ok(common.response(
    "CN point-in-time screen | "
      <> int.to_string(matched)
      <> " matched, "
      <> int.to_string(not_matched)
      <> " not matched, "
      <> int.to_string(unresolved)
      <> " unresolved",
    common.content_bound(fields),
  ))
}

fn snapshot_decoder() -> decode.Decoder(SnapshotRequest) {
  use snapshot_id <- decode.field("snapshotId", decode.string)
  use as_of <- decode.field("asOfUnixMilliseconds", decode.int)
  use retrieved <- decode.field("retrievedAtUnixMilliseconds", decode.int)
  use coverage_state <- decode.field("coverageState", decode.string)
  use expected <- decode.optional_field(
    "expectedMembers",
    None,
    decode.optional(decode.int),
  )
  use reason <- decode.optional_field(
    "coverageReason",
    None,
    decode.optional(decode.string),
  )
  use entitlement <- decode.field("entitlement", decode.string)
  use licence <- decode.field("licence", decode.string)
  use receipt <- decode.field("sourceReceipt", decode.string)
  use members <- decode.field(
    "members",
    decode.list(of: snapshot_member_decoder()),
  )
  decode.success(SnapshotRequest(
    snapshot_id,
    as_of,
    retrieved,
    coverage_state,
    expected,
    reason,
    entitlement,
    licence,
    receipt,
    members,
  ))
}

fn snapshot_member_decoder() -> decode.Decoder(SnapshotMember) {
  use listing_id <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use board <- decode.field("board", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  use status <- decode.field("status", decode.string)
  use group_id <- decode.field("groupId", decode.string)
  use price <- decode.field("price", price_decoder())
  use turnover <- decode.field("turnover", turnover_decoder())
  use receipt <- decode.field("sourceReceipt", decode.string)
  decode.success(SnapshotMember(
    listing_id,
    mic,
    board,
    share_class,
    status,
    group_id,
    price,
    turnover,
    receipt,
  ))
}

fn price_decoder() -> decode.Decoder(PriceFact) {
  use state <- decode.field("state", decode.string)
  use current <- decode.optional_field(
    "current",
    None,
    decode.optional(decode.string),
  )
  use previous <- decode.optional_field(
    "previousClose",
    None,
    decode.optional(decode.string),
  )
  use reason <- decode.optional_field(
    "reason",
    None,
    decode.optional(decode.string),
  )
  decode.success(PriceFact(state, current, previous, reason))
}

fn turnover_decoder() -> decode.Decoder(TurnoverFact) {
  use state <- decode.field("state", decode.string)
  use raw <- decode.optional_field("raw", None, decode.optional(decode.string))
  use unit <- decode.optional_field(
    "unit",
    None,
    decode.optional(decode.string),
  )
  use reason <- decode.optional_field(
    "reason",
    None,
    decode.optional(decode.string),
  )
  decode.success(TurnoverFact(state, raw, unit, reason))
}

fn screen_decoder() -> decode.Decoder(ScreenRequest) {
  use binding <- decode.field("binding", common.binding_decoder())
  use rows <- decode.field("rows", decode.list(of: screen_row_decoder()))
  use predicates <- decode.field(
    "predicates",
    decode.list(of: predicate_decoder()),
  )
  decode.success(ScreenRequest(binding, rows, predicates))
}

fn screen_row_decoder() -> decode.Decoder(ScreenRow) {
  use listing_id <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use board <- decode.field("board", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  use status <- decode.field("status", decode.string)
  use membership_state <- decode.field("membershipState", decode.string)
  use membership_reason <- decode.optional_field(
    "membershipReason",
    None,
    decode.optional(decode.string),
  )
  use membership_receipt <- decode.field("membershipReceipt", decode.string)
  use observation_id <- decode.field("observationId", decode.string)
  use values <- decode.field("values", decode.list(of: value_decoder()))
  decode.success(ScreenRow(
    listing_id,
    mic,
    board,
    share_class,
    status,
    membership_state,
    membership_reason,
    membership_receipt,
    observation_id,
    values,
  ))
}

fn value_decoder() -> decode.Decoder(ValueFact) {
  use field <- decode.field("field", decode.string)
  use unit <- decode.field("unit", decode.string)
  use state <- decode.field("state", decode.string)
  use raw <- decode.optional_field("raw", None, decode.optional(decode.string))
  use reason <- decode.optional_field(
    "reason",
    None,
    decode.optional(decode.string),
  )
  use alternatives <- decode.field(
    "alternatives",
    decode.list(of: decode.string),
  )
  use known_at <- decode.field("knownAtUnixMilliseconds", decode.int)
  use receipts <- decode.field("receipts", decode.list(of: decode.string))
  decode.success(ValueFact(
    field,
    unit,
    state,
    raw,
    reason,
    alternatives,
    known_at,
    receipts,
  ))
}

fn predicate_decoder() -> decode.Decoder(Predicate) {
  use id <- decode.field("id", decode.string)
  use field <- decode.field("field", decode.string)
  use operator <- decode.field("operator", decode.string)
  use threshold <- decode.field("threshold", decode.string)
  use unit <- decode.field("unit", decode.string)
  decode.success(Predicate(id, field, operator, threshold, unit))
}

fn validate_coverage(request: SnapshotRequest) -> Result(Nil, Error) {
  case
    request.coverage_state,
    request.expected_members,
    request.coverage_reason
  {
    "complete", Some(expected), None ->
      case expected == list.length(request.members) {
        True -> Ok(Nil)
        False -> invalid_coverage()
      }
    "partial", Some(expected), Some(_) ->
      case expected > list.length(request.members) {
        True -> Ok(Nil)
        False -> invalid_coverage()
      }
    "unknown", None, Some(_) -> Ok(Nil)
    _, _, _ -> invalid_coverage()
  }
}

fn invalid_coverage() -> Result(Nil, Error) {
  Error(common.InvalidField(
    "coverage",
    "complete requires exact expectedMembers; partial requires a larger expectedMembers and reason; unknown requires reason only",
  ))
}

fn prepare_snapshot_member(
  member: SnapshotMember,
) -> Result(PreparedSnapshotMember, Error) {
  use _ <- result.try(validate_cn_identity(
    member.listing_id,
    member.mic,
    member.board,
    member.share_class,
    member.status,
  ))
  use _ <- result.try(common.non_empty("members[].groupId", member.group_id))
  use _ <- result.try(common.receipt(
    "members[].sourceReceipt",
    member.source_receipt,
  ))
  use direction <- result.try(direction(member.price))
  use turnover <- result.try(turnover_value(member.turnover))
  Ok(PreparedSnapshotMember(member, direction, turnover))
}

fn direction(value: PriceFact) -> Result(Direction, Error) {
  case value.state, value.current, value.previous, value.reason {
    "observed", Some(current), Some(previous), None -> {
      use current <- result.try(parse_decimal(
        "members[].price.current",
        current,
      ))
      use previous <- result.try(parse_decimal(
        "members[].price.previousClose",
        previous,
      ))
      Ok(case decimal.compare(current, previous) {
        Gt -> Advanced
        Lt -> Declined
        Eq -> Unchanged
      })
    }
    "unavailable", None, None, Some(reason) ->
      Ok(Unresolved("unavailable:" <> reason))
    "conflicting", None, None, Some(reason) ->
      Ok(Unresolved("conflicting:" <> reason))
    _, _, _, _ ->
      Error(common.InvalidField(
        "members[].price",
        "fields do not match observed, unavailable, or conflicting state",
      ))
  }
}

fn turnover_value(value: TurnoverFact) -> Result(Option(Decimal), Error) {
  case value.state, value.raw, value.unit, value.reason {
    "known", Some(raw), Some("CNY"), None ->
      parse_decimal("members[].turnover.raw", raw) |> result.map(Some)
    "unknown", None, None, Some(_) -> Ok(None)
    "not_obtained", None, None, Some(_) -> Ok(None)
    "conflicting", None, None, Some(_) -> Ok(None)
    _, _, _, _ ->
      Error(common.InvalidField(
        "members[].turnover",
        "known requires exact CNY raw; unavailable states require reason only",
      ))
  }
}

fn validate_cn_identity(
  listing_id: String,
  mic: String,
  board: String,
  share_class: String,
  status: String,
) -> Result(Nil, Error) {
  use _ <- result.try(common.non_empty("listingId", listing_id))
  use _ <- result.try(case list.contains(["XSHG", "XSHE", "XBSE"], mic) {
    True -> Ok(Nil)
    False -> Error(common.InvalidField("mic", "expected XSHG, XSHE, or XBSE"))
  })
  use _ <- result.try(common.non_empty("board", board))
  use _ <- result.try(common.non_empty("shareClass", share_class))
  common.non_empty("status", status)
}

fn prepare_predicate(value: Predicate) -> Result(PreparedPredicate, Error) {
  use _ <- result.try(common.non_empty("predicates[].id", value.id))
  use _ <- result.try(common.non_empty("predicates[].field", value.field))
  use _ <- result.try(common.non_empty("predicates[].unit", value.unit))
  use _ <- result.try(
    case
      list.contains(
        [
          "less_than",
          "less_or_equal",
          "equal",
          "not_equal",
          "greater_or_equal",
          "greater_than",
        ],
        value.operator,
      )
    {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "predicates[].operator",
          "unsupported exact decimal operator",
        ))
    },
  )
  use threshold <- result.try(parse_decimal(
    "predicates[].threshold",
    value.threshold,
  ))
  Ok(PreparedPredicate(value, threshold))
}

fn prepare_screen_row(
  row: ScreenRow,
  binding: common.Binding,
  predicates: List(PreparedPredicate),
) -> Result(ScreenResult, Error) {
  use _ <- result.try(validate_cn_identity(
    row.listing_id,
    row.mic,
    row.board,
    row.share_class,
    row.status,
  ))
  use _ <- result.try(common.receipt(
    "rows[].membershipReceipt",
    row.membership_receipt,
  ))
  use _ <- result.try(common.non_empty(
    "rows[].observationId",
    row.observation_id,
  ))
  use _ <- result.try(common.require_unique(
    "rows[].values[].field",
    list.map(row.values, fn(value) { value.field }),
  ))
  use _ <- result.try(case dataset_contains(binding.dataset, row) {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "rows[].observationId",
        "is not bound to the exact dataset manifest listing/MIC",
      ))
  })
  use _ <- result.try(list.try_each(row.values, validate_value_fact))
  use _ <- result.try(validate_membership(row))
  let predicate_results =
    list.map(predicates, fn(predicate) {
      evaluate_predicate(row, binding.knowledge_cutoff_unix_ms, predicate)
    })
  let relation = case row.membership_state {
    "member" -> relation(predicate_results)
    "not_member" -> "not_matched"
    _ -> "unresolved"
  }
  Ok(ScreenResult(row, relation, predicate_results))
}

fn dataset_contains(dataset: manifest.DatasetManifest, row: ScreenRow) -> Bool {
  dataset
  |> manifest.dataset_observations
  |> list.any(fn(value) {
    value.observation_id == row.observation_id
    && value.listing_id == row.listing_id
    && value.mic == row.mic
  })
}

fn validate_membership(row: ScreenRow) -> Result(Nil, Error) {
  case row.membership_state, row.membership_reason {
    "member", None | "not_member", None -> Ok(Nil)
    "unresolved", Some(_) -> Ok(Nil)
    _, _ ->
      Error(common.InvalidField(
        "rows[].membershipState",
        "member/not_member forbid a reason; unresolved requires one",
      ))
  }
}

fn validate_value_fact(value: ValueFact) -> Result(Nil, Error) {
  use _ <- result.try(common.non_empty("rows[].values[].field", value.field))
  use _ <- result.try(common.non_empty("rows[].values[].unit", value.unit))
  use _ <- result.try(
    list.try_each(value.receipts, fn(receipt) {
      common.receipt("rows[].values[].receipts[]", receipt)
    }),
  )
  case value.state, value.raw, value.reason, value.alternatives {
    "known", Some(raw), None, [] ->
      parse_decimal("rows[].values[].raw", raw) |> result.map(fn(_) { Nil })
    "unknown", None, Some(_), [] | "not_obtained", None, Some(_), [] -> Ok(Nil)
    "conflicting", None, Some(_), alternatives if alternatives != [] -> Ok(Nil)
    _, _, _, _ ->
      Error(common.InvalidField(
        "rows[].values[]",
        "fact fields do not match state",
      ))
  }
}

fn evaluate_predicate(
  row: ScreenRow,
  cutoff: Int,
  prepared: PreparedPredicate,
) -> PredicateResult {
  let predicate = prepared.predicate
  let matches =
    list.filter(row.values, fn(value) { value.field == predicate.field })
  case matches {
    [] -> PredicateResult(predicate, "unresolved", Some("field_missing"), None)
    [value] if value.known_at_unix_ms > cutoff ->
      PredicateResult(
        predicate,
        "unresolved",
        Some("known_after_cutoff"),
        value.raw,
      )
    [ValueFact(unit: unit, state: "known", raw: Some(raw), ..)]
      if unit == predicate.unit
    -> {
      let assert Ok(value) = decimal.parse(raw)
      let compared = decimal.compare(value, prepared.threshold)
      PredicateResult(
        predicate,
        bool_state(compare(compared, predicate.operator)),
        None,
        Some(raw),
      )
    }
    [ValueFact(unit: unit, ..)] if unit != predicate.unit ->
      PredicateResult(predicate, "unresolved", Some("unit_mismatch"), None)
    [value] -> PredicateResult(predicate, "unresolved", value.reason, value.raw)
    _ -> PredicateResult(predicate, "unresolved", Some("duplicate_field"), None)
  }
}

fn compare(value: Order, operator: String) -> Bool {
  case operator, value {
    "less_than", Lt
    | "less_or_equal", Lt
    | "less_or_equal", Eq
    | "equal", Eq
    | "not_equal", Lt
    | "not_equal", Gt
    | "greater_or_equal", Eq
    | "greater_or_equal", Gt
    | "greater_than", Gt
    -> True
    _, _ -> False
  }
}

fn relation(values: List(PredicateResult)) -> String {
  case
    list.any(values, fn(value) { value.state == "false" }),
    list.any(values, fn(value) { value.state == "unresolved" })
  {
    True, _ -> "not_matched"
    False, True -> "unresolved"
    False, False -> "matched"
  }
}

fn parse_decimal(field: String, value: String) -> Result(Decimal, Error) {
  decimal.parse(value)
  |> result.map_error(fn(_) {
    common.InvalidField(field, "expected exact decimal lexeme")
  })
}

fn count_direction(value: Counts, member: PreparedSnapshotMember) -> Counts {
  case member.direction {
    Advanced -> Counts(..value, advanced: value.advanced + 1)
    Declined -> Counts(..value, declined: value.declined + 1)
    Unchanged -> Counts(..value, unchanged: value.unchanged + 1)
    Unresolved(_) -> Counts(..value, unresolved: value.unresolved + 1)
  }
}

fn counts_json(value: Counts) -> json.Json {
  json.object([
    #("advanced", json.int(value.advanced)),
    #("declined", json.int(value.declined)),
    #("unchanged", json.int(value.unchanged)),
    #("unresolved", json.int(value.unresolved)),
  ])
}

fn coverage_json(value: SnapshotRequest) -> json.Json {
  json.object([
    #("state", json.string(value.coverage_state)),
    #("expectedMembers", json.nullable(value.expected_members, json.int)),
    #("reason", json.nullable(value.coverage_reason, json.string)),
  ])
}

fn duplicate_listing_ids(values: List(SnapshotMember)) -> List(String) {
  let ids = list.map(values, fn(value) { value.listing_id <> ":" <> value.mic })
  ids
  |> list.filter(fn(id) {
    ids |> list.filter(fn(other) { other == id }) |> list.length > 1
  })
  |> unique([])
}

fn group_ids(values: List(SnapshotMember)) -> List(String) {
  values |> list.map(fn(value) { value.group_id }) |> unique([])
}

fn unique(values: List(String), seen: List(String)) -> List(String) {
  case values {
    [] -> list.reverse(seen)
    [value, ..rest] ->
      case list.contains(seen, value) {
        True -> unique(rest, seen)
        False -> unique(rest, [value, ..seen])
      }
  }
}

fn group_json(
  group_id: String,
  values: List(PreparedSnapshotMember),
) -> json.Json {
  let members =
    list.filter(values, fn(value) { value.member.group_id == group_id })
  let counts = list.fold(members, Counts(0, 0, 0, 0), count_direction)
  json.object([
    #("groupId", json.string(group_id)),
    #("memberCount", json.int(list.length(members))),
    #("directionCounts", counts_json(counts)),
  ])
}

fn prepared_snapshot_json(value: PreparedSnapshotMember) -> json.Json {
  json.object([
    #("listingId", json.string(value.member.listing_id)),
    #("mic", json.string(value.member.mic)),
    #("board", json.string(value.member.board)),
    #("shareClass", json.string(value.member.share_class)),
    #("status", json.string(value.member.status)),
    #("groupId", json.string(value.member.group_id)),
    #("direction", direction_json(value.direction)),
    #(
      "turnoverRaw",
      json.nullable(value.turnover, fn(value) {
        json.string(decimal.to_string(value))
      }),
    ),
    #("sourceReceipt", json.string(value.member.source_receipt)),
  ])
}

fn direction_json(value: Direction) -> json.Json {
  case value {
    Advanced -> json.object([#("state", json.string("advanced"))])
    Declined -> json.object([#("state", json.string("declined"))])
    Unchanged -> json.object([#("state", json.string("unchanged"))])
    Unresolved(reason) ->
      json.object([
        #("state", json.string("unresolved")),
        #("reason", json.string(reason)),
      ])
  }
}

fn predicate_json(value: Predicate) -> json.Json {
  json.object([
    #("id", json.string(value.id)),
    #("field", json.string(value.field)),
    #("operator", json.string(value.operator)),
    #("threshold", json.string(value.threshold)),
    #("unit", json.string(value.unit)),
  ])
}

fn screen_result_json(value: ScreenResult) -> json.Json {
  json.object([
    #("listingId", json.string(value.row.listing_id)),
    #("mic", json.string(value.row.mic)),
    #("board", json.string(value.row.board)),
    #("shareClass", json.string(value.row.share_class)),
    #("status", json.string(value.row.status)),
    #("membershipState", json.string(value.row.membership_state)),
    #(
      "membershipReason",
      json.nullable(value.row.membership_reason, json.string),
    ),
    #("membershipReceipt", json.string(value.row.membership_receipt)),
    #("observationId", json.string(value.row.observation_id)),
    #("relation", json.string(value.relation)),
    #("predicates", json.array(value.predicates, predicate_result_json)),
  ])
}

fn predicate_result_json(value: PredicateResult) -> json.Json {
  json.object([
    #("predicateId", json.string(value.predicate.id)),
    #("state", json.string(value.state)),
    #("reason", json.nullable(value.reason, json.string)),
    #("raw", json.nullable(value.raw, json.string)),
  ])
}

fn bool_state(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}

fn option_to_result(value: Option(value)) -> Result(value, Nil) {
  case value {
    Some(value) -> Ok(value)
    None -> Error(Nil)
  }
}
