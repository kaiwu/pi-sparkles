import finance_calendar/date
import finance_core/time.{type Date, type Instant}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/fact.{type Fact}
import finance_replay/wire
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/order
import gleam/result

pub type Kind {
  Fixed
  Expanding
  Rolling
  WalkForward
  CallerSupplied
}

pub type Basis {
  Calendar
  Session
}

pub type Window {
  Window(
    label: String,
    role: String,
    start: Date,
    end: Date,
    observation_cutoff: Instant,
    warm_up_start: Option(Date),
    purge_gap: Fact(String),
    universe_manifest_ref: Sha256,
    dataset_manifest_ref: Sha256,
    parameter_refs: List(Sha256),
    definition_refs: List(Sha256),
    rebalance_schedule: Fact(String),
  )
}

pub type Relation {
  OrderedBefore(left: String, right: String)
  Adjacent(left: String, right: String)
  Gap(left: String, right: String, start: Date, end: Date, day_count: Int)
  Overlap(left: String, right: String, start: Date, end: Date, day_count: Int)
  Contains(outer: String, inner: String)
  SameRange(left: String, right: String)
}

pub opaque type Partition {
  Partition(
    id: String,
    version: String,
    kind: Kind,
    basis: Basis,
    windows: List(Window),
    digest: Sha256,
  )
}

pub type PartitionError {
  InvalidText(field: String)
  EmptyWindows
  TooManyWindows(received: Int, maximum: Int)
  DuplicateWindowLabel(String)
  InvalidWindowRange(String)
  HashMismatch
  InvalidJson
}

pub const maximum_windows = 1000

pub fn new(
  id: String,
  version: String,
  kind: Kind,
  basis: Basis,
  windows: List(Window),
) -> Result(Partition, PartitionError) {
  use _ <- result.try(validate_text(id, "partition_id"))
  use _ <- result.try(validate_text(version, "version"))
  case windows {
    [] -> Error(EmptyWindows)
    _ -> {
      let count = list.length(windows)
      case count > maximum_windows {
        True -> Error(TooManyWindows(count, maximum_windows))
        False -> {
          use _ <- result.try(validate_windows(windows, []))
          let payload = payload(id, version, kind, basis, windows)
          let assert Ok(digest) = payload |> json.to_string |> hash.text
          Ok(Partition(id, version, kind, basis, windows, digest))
        }
      }
    }
  }
}

pub fn relations(value: Partition) -> List(Relation) {
  pair_relations(value.windows)
}

fn pair_relations(values: List(Window)) -> List(Relation) {
  case values {
    [] -> []
    [first, ..rest] ->
      list.append(
        list.flat_map(rest, fn(second) { relation_for(first, second) }),
        pair_relations(rest),
      )
  }
}

fn relation_for(left: Window, right: Window) -> List(Relation) {
  let Window(left_label, _, left_start, left_end, ..) = left
  let Window(right_label, _, right_start, right_end, ..) = right
  let left_start_ordinal = date.ordinal(left_start)
  let left_end_ordinal = date.ordinal(left_end)
  let right_start_ordinal = date.ordinal(right_start)
  let right_end_ordinal = date.ordinal(right_end)
  case
    left_start_ordinal,
    left_end_ordinal,
    right_start_ordinal,
    right_end_ordinal
  {
    start, end, other_start, other_end
      if start == other_start && end == other_end
    -> [SameRange(left_label, right_label)]
    start, end, other_start, other_end
      if start <= other_start && end >= other_end
    -> [Contains(left_label, right_label), ..overlap(left, right)]
    start, end, other_start, other_end
      if other_start <= start && other_end >= end
    -> [Contains(right_label, left_label), ..overlap(left, right)]
    _, end, other_start, _ if end + 1 == other_start -> [
      Adjacent(left_label, right_label),
    ]
    start, _, _, other_end if other_end + 1 == start -> [
      Adjacent(right_label, left_label),
    ]
    _, end, other_start, _ if end < other_start -> {
      let assert Ok(gap_start) = date.add_days(left_end, 1)
      let assert Ok(gap_end) = date.add_days(right_start, -1)
      [
        OrderedBefore(left_label, right_label),
        Gap(
          left_label,
          right_label,
          gap_start,
          gap_end,
          date.days_between(gap_start, gap_end) + 1,
        ),
      ]
    }
    start, _, _, other_end if other_end < start -> {
      let assert Ok(gap_start) = date.add_days(right_end, 1)
      let assert Ok(gap_end) = date.add_days(left_start, -1)
      [
        OrderedBefore(right_label, left_label),
        Gap(
          right_label,
          left_label,
          gap_start,
          gap_end,
          date.days_between(gap_start, gap_end) + 1,
        ),
      ]
    }
    _, _, _, _ -> overlap(left, right)
  }
}

fn overlap(left: Window, right: Window) -> List(Relation) {
  let Window(left_label, _, left_start, left_end, ..) = left
  let Window(right_label, _, right_start, right_end, ..) = right
  let start = later(left_start, right_start)
  let end = earlier(left_end, right_end)
  [
    Overlap(
      left_label,
      right_label,
      start,
      end,
      date.days_between(start, end) + 1,
    ),
  ]
}

fn later(left: Date, right: Date) -> Date {
  case date.compare(left, right) == order.Gt {
    True -> left
    False -> right
  }
}

fn earlier(left: Date, right: Date) -> Date {
  case date.compare(left, right) == order.Lt {
    True -> left
    False -> right
  }
}

pub fn encode(value: Partition) -> String {
  json.object([
    #("payload", to_json(value)),
    #("canonical_content_hash", wire.sha_json(value.digest)),
  ])
  |> json.to_string
}

pub fn decode(input: String) -> Result(Partition, PartitionError) {
  case json.parse(input, envelope_decoder()) {
    Error(_) -> Error(InvalidJson)
    Ok(#(value, expected)) ->
      case value.digest == expected {
        True -> Ok(value)
        False -> Error(HashMismatch)
      }
  }
}

pub fn to_json(value: Partition) -> json.Json {
  json.object([
    #(
      "content",
      payload(value.id, value.version, value.kind, value.basis, value.windows),
    ),
    #("content_hash", wire.sha_json(value.digest)),
  ])
}

fn payload(
  id: String,
  version: String,
  kind: Kind,
  basis: Basis,
  windows: List(Window),
) -> json.Json {
  json.object([
    #("schema", json.string("finance_replay_partition")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("partition_id", json.string(id)),
    #("version", json.string(version)),
    #("kind", kind |> kind_name |> json.string),
    #("basis", basis |> basis_name |> json.string),
    #("windows", json.array(windows, window_json)),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

fn window_json(value: Window) -> json.Json {
  let Window(
    label,
    role,
    start,
    end,
    cutoff,
    warmup,
    purge,
    universe,
    dataset,
    parameters,
    definitions,
    rebalance,
  ) = value
  json.object([
    #("label", json.string(label)),
    #("role", json.string(role)),
    #("start", wire.date_json(start)),
    #("end", wire.date_json(end)),
    #("observation_cutoff_unix_ms", wire.instant_json(cutoff)),
    #("warm_up_start", json.nullable(warmup, wire.date_json)),
    #("purge_gap", fact.to_json(purge, json.string)),
    #("universe_manifest_ref", wire.sha_json(universe)),
    #("dataset_manifest_ref", wire.sha_json(dataset)),
    #("parameter_refs", json.array(parameters, wire.sha_json)),
    #("definition_refs", json.array(definitions, wire.sha_json)),
    #("rebalance_schedule", fact.to_json(rebalance, json.string)),
  ])
}

fn envelope_decoder() -> decode.Decoder(#(Partition, Sha256)) {
  use value <- decode.field("payload", wrapper_decoder())
  use expected <- decode.field("canonical_content_hash", wire.sha_decoder())
  decode.success(#(value, expected))
}

fn wrapper_decoder() -> decode.Decoder(Partition) {
  use content <- decode.field("content", payload_decoder())
  use supplied <- decode.field("content_hash", wire.sha_decoder())
  let #(id, version, kind, basis, windows) = content
  case new(id, version, kind, basis, windows) {
    Ok(value) if value.digest == supplied -> decode.success(value)
    _ -> decode.failure(placeholder(), "valid partition")
  }
}

fn payload_decoder() -> decode.Decoder(
  #(String, String, Kind, Basis, List(Window)),
) {
  use schema <- decode.field("schema", decode.string)
  use version_number <- decode.field("schema_version", decode.int)
  use decision_owner <- decode.field("decision_owner", decode.string)
  use id <- decode.field("partition_id", decode.string)
  use version <- decode.field("version", decode.string)
  use kind <- decode.field("kind", kind_decoder())
  use basis <- decode.field("basis", basis_decoder())
  use windows <- decode.field("windows", decode.list(of: window_decoder()))
  case schema, version_number, decision_owner {
    "finance_replay_partition", 1, "llm" ->
      decode.success(#(id, version, kind, basis, windows))
    _, _, _ -> decode.failure(placeholder_payload(), "partition v1")
  }
}

fn window_decoder() -> decode.Decoder(Window) {
  use label <- decode.field("label", decode.string)
  use role <- decode.field("role", decode.string)
  use start <- decode.field("start", wire.date_decoder())
  use end <- decode.field("end", wire.date_decoder())
  use cutoff <- decode.field(
    "observation_cutoff_unix_ms",
    wire.instant_decoder(),
  )
  use warmup <- decode.optional_field(
    "warm_up_start",
    None,
    decode.optional(wire.date_decoder()),
  )
  use purge <- decode.field("purge_gap", fact.decoder(decode.string))
  use universe <- decode.field("universe_manifest_ref", wire.sha_decoder())
  use dataset <- decode.field("dataset_manifest_ref", wire.sha_decoder())
  use parameters <- decode.field(
    "parameter_refs",
    decode.list(of: wire.sha_decoder()),
  )
  use definitions <- decode.field(
    "definition_refs",
    decode.list(of: wire.sha_decoder()),
  )
  use rebalance <- decode.field(
    "rebalance_schedule",
    fact.decoder(decode.string),
  )
  decode.success(Window(
    label,
    role,
    start,
    end,
    cutoff,
    warmup,
    purge,
    universe,
    dataset,
    parameters,
    definitions,
    rebalance,
  ))
}

fn kind_name(value: Kind) -> String {
  case value {
    Fixed -> "fixed"
    Expanding -> "expanding"
    Rolling -> "rolling"
    WalkForward -> "walk_forward"
    CallerSupplied -> "caller_supplied"
  }
}

fn kind_decoder() -> decode.Decoder(Kind) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "fixed" -> decode.success(Fixed)
      "expanding" -> decode.success(Expanding)
      "rolling" -> decode.success(Rolling)
      "walk_forward" -> decode.success(WalkForward)
      "caller_supplied" -> decode.success(CallerSupplied)
      _ -> decode.failure(CallerSupplied, "known partition kind")
    }
  })
}

fn basis_name(value: Basis) -> String {
  case value {
    Calendar -> "calendar"
    Session -> "session"
  }
}

fn basis_decoder() -> decode.Decoder(Basis) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "calendar" -> decode.success(Calendar)
      "session" -> decode.success(Session)
      _ -> decode.failure(Calendar, "calendar or session basis")
    }
  })
}

fn validate_windows(
  values: List(Window),
  seen: List(String),
) -> Result(Nil, PartitionError) {
  case values {
    [] -> Ok(Nil)
    [Window(label, role, start, end, ..), ..rest] -> {
      use _ <- result.try(validate_text(label, "window_label"))
      use _ <- result.try(validate_text(role, "window_role"))
      case list.contains(seen, label), date.compare(start, end) == order.Gt {
        True, _ -> Error(DuplicateWindowLabel(label))
        _, True -> Error(InvalidWindowRange(label))
        False, False -> validate_windows(rest, [label, ..seen])
      }
    }
  }
}

fn validate_text(value: String, field: String) -> Result(Nil, PartitionError) {
  case wire.valid_text(value, 200) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn placeholder_payload() {
  #("placeholder", "placeholder", CallerSupplied, Calendar, [
    placeholder_window(),
  ])
}

fn placeholder_window() -> Window {
  Window(
    "placeholder",
    "placeholder",
    wire.placeholder_date(),
    wire.placeholder_date(),
    wire.placeholder_instant(),
    None,
    fact.NotApplicable("placeholder"),
    wire.placeholder_sha(),
    wire.placeholder_sha(),
    [],
    [],
    fact.NotApplicable("placeholder"),
  )
}

fn placeholder() -> Partition {
  let assert Ok(value) =
    new("placeholder", "placeholder", CallerSupplied, Calendar, [
      placeholder_window(),
    ])
  value
}

pub fn digest(value: Partition) -> Sha256 {
  value.digest
}

pub fn windows(value: Partition) -> List(Window) {
  value.windows
}
