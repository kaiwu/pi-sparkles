import finance_provenance/hash
import finance_provenance/identity
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string

pub const maximum_payload_bytes = 10_000_000

pub const maximum_events = 100_000

pub const maximum_depth_levels_per_side = 10

pub const maximum_output_rows = 1000

pub const maximum_condition_codes = 100

pub const maximum_source_lexeme_bytes = 4096

pub type Entitlement {
  RealTime
  Delayed(minutes: Int)
}

pub type Licence {
  Licence(
    label: String,
    receipt: String,
    venue_coverage: List(String),
    redistribution_permitted: Bool,
    retention_limit: Option(String),
    display_use: Option(String),
    non_display_use: Option(String),
    derived_data_permitted: Option(Bool),
    caching_permitted: Option(Bool),
    logging_permitted: Option(Bool),
    fixture_use_permitted: Option(Bool),
  )
}

pub type PhaseInterval {
  PhaseInterval(
    phase: String,
    start_unix_ms: Int,
    end_unix_ms: Int,
    rule_receipt: String,
  )
}

pub type Common {
  Common(
    event_id: String,
    listing_id: String,
    mic: String,
    track: String,
    feed: String,
    currency: String,
    size_unit: String,
    exchange_time_unix_ms: Option(Int),
    provider_time_unix_ms: Int,
    receipt_time_unix_ms: Int,
    sequence: Option(Int),
    entitlement: Entitlement,
    licence_receipt: String,
    acquisition_receipt: String,
    conditions: List(String),
    odd_lot: Bool,
    off_exchange: Bool,
    source_lexemes: Dict(String, String),
  )
}

pub type DepthSide {
  Bid
  Ask
}

pub type DepthLevel {
  DepthLevel(
    side: DepthSide,
    price: String,
    visible_size: String,
    order_count: Option(Int),
  )
}

pub type DepthAction {
  Add
  Modify
  Delete
}

pub type DepthChange {
  DepthChange(
    side: DepthSide,
    price: String,
    size_delta: String,
    action: DepthAction,
  )
}

pub type Body {
  Quote(
    bid_price: String,
    bid_size: String,
    ask_price: String,
    ask_size: String,
  )
  Trade(price: String, size: String, correction_lineage: Option(String))
  DepthSnapshot(levels: List(DepthLevel))
  DepthDelta(base_sequence: Int, changes: List(DepthChange))
  IndicativeAuction(
    auction_phase: String,
    indicative_price: String,
    indicative_volume: String,
    imbalance: String,
  )
  OfficialAuctionResult(
    auction_phase: String,
    match_price: String,
    match_volume: String,
  )
  Halt(halt_reason: String, resumption_time_unix_ms: Option(Int))
  StatusChange(status: String)
  Correction(original_event_id: String, corrected_fields: List(String))
  CancelBust(original_event_id: String, reason: String)
  Heartbeat
}

pub type Event {
  Event(common: Common, body: Body)
}

pub type Packet {
  Packet(
    packet_id: String,
    packet_hash: String,
    track: String,
    listing_id: String,
    mic: String,
    session_date: String,
    timezone: String,
    provider: String,
    feed: String,
    currency: String,
    size_unit: String,
    entitlement: Entitlement,
    licence: Licence,
    acquisition_receipt: String,
    sequence_scope: String,
    expected_heartbeat_interval_ms: Option(Int),
    phases: List(PhaseInterval),
    declared_complete: Bool,
    input_event_count: Int,
    events: List(Event),
    exact_duplicate_count: Int,
    conflicting_event_ids: List(String),
  )
}

pub type SequenceIssue {
  MissingSequence(event_id: String)
  SequenceGap(
    prior_event_id: String,
    event_id: String,
    from: Int,
    to: Int,
    at_unix_ms: Int,
  )
  SequenceOutOfOrder(
    prior_event_id: String,
    event_id: String,
    prior: Int,
    received: Int,
    at_unix_ms: Int,
  )
  SequenceReset(event_id: String, prior: Int, at_unix_ms: Int)
  DuplicateSequence(event_id: String, sequence: Int)
  IdentityMismatch(event_id: String)
  EntitlementMismatch(event_id: String)
  ReceiptMismatch(event_id: String)
  EventIdConflict(event_id: String)
  UnboundDepthDelta(event_id: String, base_sequence: Int)
  UnknownOriginalReference(event_id: String, original_event_id: String)
  HeartbeatMissed(last_heartbeat_at: Int, expected_at: Int)
}

pub type PhaseState {
  PhaseKnown(phase: String, rule_receipt: String)
  PhaseUnavailable
  PhaseConflict(phases: List(String))
}

pub type Inspection {
  Inspection(
    packet: Packet,
    issues: List(SequenceIssue),
    phase_state: PhaseState,
    stale_event_count: Int,
  )
}

type RawPacket {
  RawPacket(
    schema_version: String,
    packet_id: String,
    track: String,
    listing_id: String,
    mic: String,
    session_date: String,
    timezone: String,
    provider: String,
    feed: String,
    currency: String,
    size_unit: String,
    entitlement: Entitlement,
    licence: Licence,
    acquisition_receipt: String,
    sequence_scope: String,
    expected_heartbeat_interval_ms: Option(Int),
    phases: List(PhaseInterval),
    declared_complete: Bool,
    events: List(Event),
  )
}

pub fn parse(
  payload: String,
  supplied_hash: String,
  event_budget: Int,
) -> Result(Packet, String) {
  use _ <- result.try(case string.byte_size(payload) <= maximum_payload_bytes {
    True -> Ok(Nil)
    False -> Error("packet payload exceeds the 10000000-byte hard limit")
  })
  use _ <- result.try(case event_budget >= 1 && event_budget <= maximum_events {
    True -> Ok(Nil)
    False -> Error("maximumEvents must be between 1 and 100000")
  })
  use expected_hash <- result.try(
    identity.sha256(supplied_hash)
    |> result.map_error(fn(_) { "packetHash must be a SHA-256 hex value" }),
  )
  use actual_hash <- result.try(
    hash.text(payload)
    |> result.map_error(fn(_) { "packet payload could not be hashed" }),
  )
  use _ <- result.try(case expected_hash == actual_hash {
    True -> Ok(Nil)
    False -> Error("packetHash does not match packetPayload")
  })
  use raw <- result.try(
    json_parse(payload)
    |> result.map_error(fn(_) { "packetPayload is not canonical packet JSON" }),
  )
  validate_raw(raw, identity.sha256_value(actual_hash), event_budget)
}

pub fn inspect(
  packet: Packet,
  as_of_unix_ms: Int,
  freshness_cutoff_unix_ms: Int,
) -> Inspection {
  let packet_issues = issues(packet)
  let Packet(events: events, phases: phases, ..) = packet
  let stale =
    events
    |> list.filter(fn(event) {
      common(event).receipt_time_unix_ms < freshness_cutoff_unix_ms
    })
    |> list.length
  Inspection(packet, packet_issues, current_phase(phases, as_of_unix_ms), stale)
}

pub fn issues(packet: Packet) -> List(SequenceIssue) {
  let Packet(
    events: events,
    conflicting_event_ids: conflicts,
    expected_heartbeat_interval_ms: heartbeat_interval,
    ..,
  ) = packet
  let base =
    event_issues(packet, events)
    |> list.append(sequence_issues(events))
    |> list.append(reference_issues(events))
    |> list.append(depth_issues(events))
    |> list.append(
      conflicts
      |> list.unique
      |> list.map(EventIdConflict),
    )
  case heartbeat_interval, last_heartbeat(events), last_receipt_time(events) {
    Some(interval), Some(last_heartbeat_at), Some(last_receipt)
      if interval > 0 && last_receipt > last_heartbeat_at + interval
    ->
      list.append(base, [
        HeartbeatMissed(last_heartbeat_at, last_heartbeat_at + interval),
      ])
    _, _, _ -> base
  }
}

pub fn integrity_current(packet: Packet) -> Bool {
  issues(packet) == [] && packet.declared_complete
}

pub fn calculation_events(packet: Packet) -> List(Event) {
  packet.events
  |> list.filter(fn(event) {
    event_matches_packet(packet, event)
    && !list.contains(packet.conflicting_event_ids, event_id(event))
  })
}

pub fn event_in_window(event: Event, start: Int, end: Int) -> Bool {
  let time = common(event).provider_time_unix_ms
  time >= start && time <= end
}

pub fn common(event: Event) -> Common {
  let Event(common, _) = event
  common
}

pub fn body(event: Event) -> Body {
  let Event(_, body) = event
  body
}

pub fn event_id(event: Event) -> String {
  common(event).event_id
}

pub fn event_type(event: Event) -> String {
  case body(event) {
    Quote(..) -> "quote"
    Trade(..) -> "trade"
    DepthSnapshot(..) -> "depth_snapshot"
    DepthDelta(..) -> "depth_delta"
    IndicativeAuction(..) -> "indicative_auction"
    OfficialAuctionResult(..) -> "official_auction_result"
    Halt(..) -> "halt"
    StatusChange(..) -> "status_change"
    Correction(..) -> "correction"
    CancelBust(..) -> "cancel_bust"
    Heartbeat -> "heartbeat"
  }
}

pub fn inspection_json(
  inspection: Inspection,
  include_events: Bool,
  include_source_lexemes: Bool,
  offset: Int,
  limit: Int,
) -> Json {
  let Inspection(packet, issue_values, phase_state, stale_count) = inspection
  let Packet(
    packet_id: packet_id,
    packet_hash: packet_hash,
    track: track,
    listing_id: listing_id,
    mic: mic,
    session_date: session_date,
    timezone: timezone,
    provider: provider,
    feed: feed,
    currency: currency,
    size_unit: size_unit,
    entitlement: entitlement,
    licence: licence,
    acquisition_receipt: acquisition_receipt,
    sequence_scope: sequence_scope,
    declared_complete: declared_complete,
    input_event_count: input_count,
    events: events,
    exact_duplicate_count: duplicates,
    conflicting_event_ids: conflicts,
    ..,
  ) = packet
  let Licence(
    label: licence_label,
    receipt: licence_receipt,
    venue_coverage: venue_coverage,
    redistribution_permitted: redistribution,
    ..,
  ) = licence
  let page = case include_events {
    True ->
      events
      |> list.drop(offset)
      |> list.take(limit)
      |> list.map(fn(event) { event_json(event, include_source_lexemes) })
    False -> []
  }
  json.object([
    #("schemaVersion", json.string("pi_day_inspection_v1")),
    #("packetId", json.string(packet_id)),
    #("packetHash", json.string(packet_hash)),
    #("track", json.string(track)),
    #("listingId", json.string(listing_id)),
    #("mic", json.string(mic)),
    #("sessionDate", json.string(session_date)),
    #("timezone", json.string(timezone)),
    #("currency", json.string(currency)),
    #("sizeUnit", json.string(size_unit)),
    #("provider", json.string(provider)),
    #("feed", json.string(feed)),
    #("entitlement", entitlement_json(entitlement)),
    #("claimVerification", json.string("caller_attested_not_verified")),
    #(
      "licence",
      json.object([
        #("label", json.string(licence_label)),
        #("receipt", json.string(licence_receipt)),
        #("venueCoverage", json.array(venue_coverage, json.string)),
        #("redistributionPermitted", json.bool(redistribution)),
      ]),
    ),
    #("acquisitionReceipt", json.string(acquisition_receipt)),
    #("sequenceScope", json.string(sequence_scope)),
    #("declaredComplete", json.bool(declared_complete)),
    #("phase", phase_json(phase_state)),
    #(
      "counts",
      json.object([
        #("inputEvents", json.int(input_count)),
        #("retainedEvents", json.int(list.length(events))),
        #("exactDuplicatesCollapsed", json.int(duplicates)),
        #("conflictingEventIds", json.int(list.length(list.unique(conflicts)))),
        #("integrityIssues", json.int(list.length(issue_values))),
        #("staleEventsAgainstCallerCutoff", json.int(stale_count)),
      ]),
    ),
    #(
      "integrity",
      json.object([
        #("current", json.bool(issue_values == [] && declared_complete)),
        #("issues", json.array(issue_values, issue_json)),
        #(
          "meaning",
          json.string(
            "mechanical packet integrity only; not feed authenticity, sufficiency, readiness, or a trade decision",
          ),
        ),
      ]),
    ),
    #("evidenceMatrix", evidence_matrix_json(events, issue_values)),
    #(
      "page",
      json.object([
        #("included", json.bool(include_events)),
        #("offset", json.int(offset)),
        #("limit", json.int(limit)),
        #("returned", json.int(list.length(page))),
        #(
          "hasMore",
          json.bool(
            include_events && offset + list.length(page) < list.length(events),
          ),
        ),
        #(
          "nextOffset",
          case
            include_events && offset + list.length(page) < list.length(events)
          {
            True -> json.int(offset + list.length(page))
            False -> json.null()
          },
        ),
        #("events", json.array(page, fn(value) { value })),
      ]),
    ),
    #(
      "availableOperations",
      json.array(
        [
          "day_inspect",
          "day_calculate",
          "day_transition",
        ],
        json.string,
      ),
    ),
    #("decisionOwner", json.string("llm_or_user")),
    #(
      "forbiddenClaims",
      json.array(
        [
          "provider_or_exchange_authentication",
          "professional_sufficiency",
          "ready_to_trade",
          "candidate_qualification_or_rank",
          "likely_or_actual_fill_from_simulation",
          "recommendation_authorization_or_next_action",
        ],
        json.string,
      ),
    ),
  ])
}

pub fn event_json(event: Event, include_source_lexemes: Bool) -> Json {
  let Event(common_value, body_value) = event
  let Common(
    event_id: id,
    listing_id: listing,
    mic: mic,
    track: track,
    feed: feed,
    currency: currency,
    size_unit: size_unit,
    exchange_time_unix_ms: exchange_time,
    provider_time_unix_ms: provider_time,
    receipt_time_unix_ms: receipt_time,
    sequence: sequence,
    entitlement: entitlement,
    licence_receipt: licence,
    acquisition_receipt: acquisition,
    conditions: conditions,
    odd_lot: odd_lot,
    off_exchange: off_exchange,
    source_lexemes: lexemes,
  ) = common_value
  let fields = [
    #("eventId", json.string(id)),
    #("type", json.string(event_type(event))),
    #("listingId", json.string(listing)),
    #("mic", json.string(mic)),
    #("track", json.string(track)),
    #("feed", json.string(feed)),
    #("currency", json.string(currency)),
    #("sizeUnit", json.string(size_unit)),
    #("exchangeTimeUnixMilliseconds", optional_int_json(exchange_time)),
    #("providerTimeUnixMilliseconds", json.int(provider_time)),
    #("receiptTimeUnixMilliseconds", json.int(receipt_time)),
    #("sequence", optional_int_json(sequence)),
    #("entitlement", entitlement_json(entitlement)),
    #("licenceReceipt", json.string(licence)),
    #("acquisitionReceipt", json.string(acquisition)),
    #("conditions", json.array(conditions, json.string)),
    #("oddLot", json.bool(odd_lot)),
    #("offExchange", json.bool(off_exchange)),
    #("details", body_json(body_value)),
  ]
  let with_lexemes = case include_source_lexemes {
    True ->
      list.append(fields, [
        #(
          "sourceLexemes",
          lexemes
            |> dict.to_list
            |> list.map(fn(pair) {
              let #(key, value) = pair
              #(key, json.string(value))
            })
            |> json.object,
        ),
      ])
    False -> fields
  }
  json.object(with_lexemes)
}

fn validate_raw(
  raw: RawPacket,
  packet_hash: String,
  event_budget: Int,
) -> Result(Packet, String) {
  let RawPacket(
    schema_version,
    packet_id,
    track,
    listing_id,
    mic,
    session_date,
    timezone,
    provider,
    feed,
    currency,
    size_unit,
    entitlement,
    licence,
    acquisition_receipt,
    sequence_scope,
    expected_heartbeat,
    phases,
    declared_complete,
    raw_events,
  ) = raw
  use _ <- result.try(case schema_version == "pi_day_intraday_packet_v1" {
    True -> Ok(Nil)
    False -> Error("unsupported packet schemaVersion")
  })
  use _ <- result.try(validate_identity(track, mic))
  use _ <- result.try(
    validate_texts([
      #("packetId", packet_id),
      #("listingId", listing_id),
      #("sessionDate", session_date),
      #("timezone", timezone),
      #("provider", provider),
      #("feed", feed),
      #("currency", currency),
      #("sizeUnit", size_unit),
    ]),
  )
  use _ <- result.try(
    case sequence_scope == "per_feed" || sequence_scope == "per_listing" {
      True -> Ok(Nil)
      False -> Error("sequenceScope must be per_feed or per_listing")
    },
  )
  use _ <- result.try(validate_licence(licence, mic))
  use _ <- result.try(validate_hash("acquisitionReceipt", acquisition_receipt))
  use _ <- result.try(case list.length(raw_events) <= event_budget {
    True -> Ok(Nil)
    False -> Error("packet event count exceeds caller maximumEvents")
  })
  use _ <- result.try(case list.length(phases) <= 32 {
    True -> Ok(Nil)
    False -> Error("packet has more than 32 phase intervals")
  })
  use _ <- result.try(phases |> list.try_each(validate_phase))
  use _ <- result.try(raw_events |> list.try_each(validate_event))
  let #(events, duplicate_count, conflicts) = collapse_events(raw_events)
  Ok(Packet(
    packet_id,
    packet_hash,
    track,
    listing_id,
    mic,
    session_date,
    timezone,
    provider,
    feed,
    currency,
    size_unit,
    entitlement,
    licence,
    acquisition_receipt,
    sequence_scope,
    expected_heartbeat,
    phases,
    declared_complete,
    list.length(raw_events),
    events,
    duplicate_count,
    conflicts,
  ))
}

fn validate_identity(track: String, mic: String) -> Result(Nil, String) {
  case track, mic {
    "cn", "XSHG" | "cn", "XSHE" | "hk", "XHKG" | "us", "XNYS" | "us", "XNAS" ->
      Ok(Nil)
    "cn", _ | "hk", _ | "us", _ ->
      Error("MIC is outside Session 22's first-slice track scope")
    _, _ -> Error("track must be cn, hk, or us")
  }
}

fn validate_licence(licence: Licence, mic: String) -> Result(Nil, String) {
  let Licence(label, receipt, venues, _, _, _, _, _, _, _, _) = licence
  use _ <- result.try(validate_texts([#("licence.label", label)]))
  use _ <- result.try(validate_hash("licence.receipt", receipt))
  case list.contains(venues, mic) {
    True -> Ok(Nil)
    False -> Error("licence venueCoverage does not include packet MIC")
  }
}

fn validate_phase(phase: PhaseInterval) -> Result(Nil, String) {
  let PhaseInterval(name, start, finish, receipt) = phase
  use _ <- result.try(case valid_phase_name(name) {
    True -> Ok(Nil)
    False -> Error("phase has an unsupported name")
  })
  use _ <- result.try(case start < finish {
    True -> Ok(Nil)
    False -> Error("phase interval start must be before end")
  })
  validate_hash("phase.ruleReceipt", receipt)
}

fn validate_event(event: Event) -> Result(Nil, String) {
  let Event(common_value, body_value) = event
  let Common(
    event_id,
    listing_id,
    mic,
    track,
    feed,
    currency,
    size_unit,
    _,
    provider_time,
    receipt_time,
    sequence,
    entitlement,
    licence,
    acquisition,
    conditions,
    _,
    _,
    lexemes,
  ) = common_value
  use _ <- result.try(
    validate_texts([
      #("event.eventId", event_id),
      #("event.listingId", listing_id),
      #("event.mic", mic),
      #("event.track", track),
      #("event.feed", feed),
      #("event.currency", currency),
      #("event.sizeUnit", size_unit),
    ]),
  )
  use _ <- result.try(case provider_time >= 0 && receipt_time >= 0 {
    True -> Ok(Nil)
    False -> Error("event timestamps must be non-negative")
  })
  use _ <- result.try(case sequence {
    Some(value) if value < 0 -> Error("event sequence must be non-negative")
    _ -> Ok(Nil)
  })
  use _ <- result.try(case entitlement {
    Delayed(minutes) if minutes <= 0 ->
      Error("delayed entitlement minutes must be positive")
    _ -> Ok(Nil)
  })
  use _ <- result.try(validate_hash("event.licenceReceipt", licence))
  use _ <- result.try(validate_hash("event.acquisitionReceipt", acquisition))
  use _ <- result.try(case list.length(conditions) <= maximum_condition_codes {
    True -> Ok(Nil)
    False -> Error("event condition count exceeds 100")
  })
  use _ <- result.try(
    lexemes
    |> dict.to_list
    |> list.try_each(fn(pair) {
      let #(key, value) = pair
      case
        string.byte_size(key) <= 200,
        string.byte_size(value) <= maximum_source_lexeme_bytes
      {
        True, True -> Ok(Nil)
        False, _ -> Error("source lexeme key exceeds 200 bytes")
        _, False -> Error("source lexeme value exceeds 4096 bytes")
      }
    }),
  )
  validate_body(body_value)
}

fn validate_body(body: Body) -> Result(Nil, String) {
  case body {
    DepthSnapshot(levels) -> {
      let bids =
        levels |> list.filter(fn(level) { level.side == Bid }) |> list.length
      let asks =
        levels |> list.filter(fn(level) { level.side == Ask }) |> list.length
      case
        bids <= maximum_depth_levels_per_side,
        asks <= maximum_depth_levels_per_side
      {
        True, True -> Ok(Nil)
        _, _ -> Error("depth snapshot exceeds 10 levels per side")
      }
    }
    DepthDelta(base, changes) ->
      case
        base >= 0,
        list.length(changes) <= maximum_depth_levels_per_side * 2
      {
        True, True -> Ok(Nil)
        False, _ -> Error("depth delta baseSequence must be non-negative")
        _, False -> Error("depth delta exceeds 20 changes")
      }
    Correction(original, fields) ->
      case original != "", list.length(fields) <= 100 {
        True, True -> Ok(Nil)
        False, _ -> Error("correction originalEventId is required")
        _, False -> Error("correction field count exceeds 100")
      }
    CancelBust(original, reason) ->
      case original != "" && reason != "" {
        True -> Ok(Nil)
        False -> Error("cancel/bust originalEventId and reason are required")
      }
    _ -> Ok(Nil)
  }
}

fn validate_texts(values: List(#(String, String))) -> Result(Nil, String) {
  values
  |> list.try_each(fn(pair) {
    let #(name, value) = pair
    case value == "", string.byte_size(value) > 500 {
      True, _ -> Error(name <> " must not be blank")
      _, True -> Error(name <> " exceeds 500 bytes")
      False, False -> Ok(Nil)
    }
  })
}

fn validate_hash(name: String, value: String) -> Result(Nil, String) {
  identity.sha256(value)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(_) { name <> " must be a SHA-256 hex value" })
}

fn collapse_events(events: List(Event)) -> #(List(Event), Int, List(String)) {
  events
  |> list.fold(#([], 0, []), fn(acc, event) {
    let #(retained, duplicates, conflicts) = acc
    case find_event(retained, event_id(event)) {
      None -> #(list.append(retained, [event]), duplicates, conflicts)
      Some(existing) if existing == event -> #(
        retained,
        duplicates + 1,
        conflicts,
      )
      Some(_) -> #(
        list.append(retained, [event]),
        duplicates,
        list.append(conflicts, [event_id(event)]),
      )
    }
  })
}

fn find_event(events: List(Event), id: String) -> Option(Event) {
  case events |> list.find(fn(event) { event_id(event) == id }) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn event_issues(packet: Packet, events: List(Event)) -> List(SequenceIssue) {
  events
  |> list.flat_map(fn(event) {
    let common_value = common(event)
    let identity_issues = case event_matches_packet(packet, event) {
      True -> []
      False -> [IdentityMismatch(common_value.event_id)]
    }
    let entitlement_issues = case
      common_value.entitlement == packet.entitlement
    {
      True -> []
      False -> [EntitlementMismatch(common_value.event_id)]
    }
    let receipt_issues = case
      common_value.licence_receipt == packet.licence.receipt,
      common_value.acquisition_receipt == packet.acquisition_receipt
    {
      True, True -> []
      _, _ -> [ReceiptMismatch(common_value.event_id)]
    }
    identity_issues
    |> list.append(entitlement_issues)
    |> list.append(receipt_issues)
  })
}

fn event_matches_packet(packet: Packet, event: Event) -> Bool {
  let value = common(event)
  value.listing_id == packet.listing_id
  && value.mic == packet.mic
  && value.track == packet.track
  && value.feed == packet.feed
  && value.currency == packet.currency
  && value.size_unit == packet.size_unit
}

fn sequence_issues(events: List(Event)) -> List(SequenceIssue) {
  let #(_, values) =
    events
    |> list.fold(#(None, []), fn(acc, event) {
      let #(prior, issues) = acc
      let value = common(event)
      case value.sequence, prior {
        None, _ -> #(
          prior,
          list.append(issues, [MissingSequence(value.event_id)]),
        )
        Some(sequence), None -> #(Some(#(value.event_id, sequence)), issues)
        Some(sequence), Some(#(prior_id, prior_sequence)) -> {
          let next_issues = case int.compare(sequence, prior_sequence) {
            Eq -> [DuplicateSequence(value.event_id, sequence)]
            Lt if sequence == 1 -> [
              SequenceReset(
                value.event_id,
                prior_sequence,
                value.provider_time_unix_ms,
              ),
            ]
            Lt -> [
              SequenceOutOfOrder(
                prior_id,
                value.event_id,
                prior_sequence,
                sequence,
                value.provider_time_unix_ms,
              ),
            ]
            Gt if sequence > prior_sequence + 1 -> [
              SequenceGap(
                prior_id,
                value.event_id,
                prior_sequence + 1,
                sequence - 1,
                value.provider_time_unix_ms,
              ),
            ]
            Gt -> []
          }
          #(Some(#(value.event_id, sequence)), list.append(issues, next_issues))
        }
      }
    })
  values
}

fn depth_issues(events: List(Event)) -> List(SequenceIssue) {
  let snapshot_sequences =
    events
    |> list.filter_map(fn(event) {
      case body(event), common(event).sequence {
        DepthSnapshot(_), Some(sequence) -> Ok(sequence)
        _, _ -> Error(Nil)
      }
    })
  events
  |> list.filter_map(fn(event) {
    case body(event) {
      DepthDelta(base, _) ->
        case list.contains(snapshot_sequences, base) {
          True -> Error(Nil)
          False -> Ok(UnboundDepthDelta(event_id(event), base))
        }
      _ -> Error(Nil)
    }
  })
}

fn reference_issues(events: List(Event)) -> List(SequenceIssue) {
  let ids = list.map(events, event_id)
  events
  |> list.filter_map(fn(event) {
    case body(event) {
      Correction(original, _) ->
        case list.contains(ids, original) {
          True -> Error(Nil)
          False -> Ok(UnknownOriginalReference(event_id(event), original))
        }
      CancelBust(original, _) ->
        case list.contains(ids, original) {
          True -> Error(Nil)
          False -> Ok(UnknownOriginalReference(event_id(event), original))
        }
      _ -> Error(Nil)
    }
  })
}

fn last_heartbeat(events: List(Event)) -> Option(Int) {
  events
  |> list.filter_map(fn(event) {
    case body(event) {
      Heartbeat -> Ok(common(event).provider_time_unix_ms)
      _ -> Error(Nil)
    }
  })
  |> list.last
  |> result.map(Some)
  |> result.unwrap(None)
}

fn last_receipt_time(events: List(Event)) -> Option(Int) {
  events
  |> list.last
  |> result.map(fn(event) { Some(common(event).receipt_time_unix_ms) })
  |> result.unwrap(None)
}

fn current_phase(phases: List(PhaseInterval), as_of: Int) -> PhaseState {
  let matches =
    phases
    |> list.filter(fn(phase) {
      as_of >= phase.start_unix_ms && as_of < phase.end_unix_ms
    })
  case matches {
    [] -> PhaseUnavailable
    [phase] -> PhaseKnown(phase.phase, phase.rule_receipt)
    values -> PhaseConflict(list.map(values, fn(value) { value.phase }))
  }
}

fn evidence_matrix_json(
  events: List(Event),
  issues: List(SequenceIssue),
) -> Json {
  let has_quote = list.any(events, fn(event) { event_type(event) == "quote" })
  let has_trade = list.any(events, fn(event) { event_type(event) == "trade" })
  let has_depth =
    list.any(events, fn(event) { event_type(event) == "depth_snapshot" })
  let has_status =
    list.any(events, fn(event) {
      event_type(event) == "status_change" || event_type(event) == "halt"
    })
  json.object([
    #("identity", json.string("known_from_packet_declaration")),
    #("sessionPhase", json.string("supplied_track_owned_phase_facts")),
    #("quote", availability_json(has_quote, "QuoteUnavailable")),
    #("trade", availability_json(has_trade, "TradeUnavailable")),
    #("depth", availability_json(has_depth, "DepthUnavailable")),
    #("haltOrStatus", availability_json(has_status, "StatusUnavailable")),
    #("sequenceIntegrity", case issues {
      [] -> json.string("mechanically_current")
      _ -> json.string("issues_present")
    }),
    #("verdict", json.string("none_llm_or_user_decides")),
  ])
}

fn availability_json(available: Bool, unavailable: String) -> Json {
  case available {
    True -> json.string("available")
    False -> json.string(unavailable)
  }
}

fn phase_json(state: PhaseState) -> Json {
  case state {
    PhaseKnown(phase, receipt) ->
      json.object([
        #("state", json.string("known")),
        #("phase", json.string(phase)),
        #("ruleReceipt", json.string(receipt)),
      ])
    PhaseUnavailable -> json.object([#("state", json.string("unavailable"))])
    PhaseConflict(phases) ->
      json.object([
        #("state", json.string("conflicting")),
        #("phases", json.array(phases, json.string)),
      ])
  }
}

fn issue_json(issue: SequenceIssue) -> Json {
  case issue {
    MissingSequence(id) -> issue_object("missing_sequence", id, [])
    SequenceGap(prior, id, from, to, at) ->
      issue_object("sequence_gap", id, [
        #("priorEventId", json.string(prior)),
        #("from", json.int(from)),
        #("to", json.int(to)),
        #("atUnixMilliseconds", json.int(at)),
      ])
    SequenceOutOfOrder(prior, id, prior_sequence, received, at) ->
      issue_object("sequence_out_of_order", id, [
        #("priorEventId", json.string(prior)),
        #("priorSequence", json.int(prior_sequence)),
        #("receivedSequence", json.int(received)),
        #("atUnixMilliseconds", json.int(at)),
      ])
    SequenceReset(id, prior, at) ->
      issue_object("sequence_reset", id, [
        #("priorSequence", json.int(prior)),
        #("atUnixMilliseconds", json.int(at)),
      ])
    DuplicateSequence(id, sequence) ->
      issue_object("duplicate_sequence", id, [
        #("sequence", json.int(sequence)),
      ])
    IdentityMismatch(id) -> issue_object("identity_mismatch", id, [])
    EntitlementMismatch(id) -> issue_object("entitlement_mismatch", id, [])
    ReceiptMismatch(id) -> issue_object("receipt_mismatch", id, [])
    EventIdConflict(id) -> issue_object("event_id_conflict", id, [])
    UnboundDepthDelta(id, base) ->
      issue_object("unbound_depth_delta", id, [
        #("baseSequence", json.int(base)),
      ])
    UnknownOriginalReference(id, original) ->
      issue_object("unknown_original_reference", id, [
        #("originalEventId", json.string(original)),
      ])
    HeartbeatMissed(last, expected) ->
      json.object([
        #("kind", json.string("heartbeat_missed")),
        #("lastHeartbeatAtUnixMilliseconds", json.int(last)),
        #("expectedAtUnixMilliseconds", json.int(expected)),
      ])
  }
}

fn issue_object(
  kind: String,
  id: String,
  details: List(#(String, Json)),
) -> Json {
  json.object(list.append(
    [
      #("kind", json.string(kind)),
      #("eventId", json.string(id)),
    ],
    details,
  ))
}

fn body_json(body: Body) -> Json {
  case body {
    Quote(bid_price, bid_size, ask_price, ask_size) ->
      json.object([
        #("bidPrice", json.string(bid_price)),
        #("bidSize", json.string(bid_size)),
        #("askPrice", json.string(ask_price)),
        #("askSize", json.string(ask_size)),
      ])
    Trade(price, size, lineage) ->
      json.object([
        #("price", json.string(price)),
        #("size", json.string(size)),
        #("correctionLineage", optional_string_json(lineage)),
      ])
    DepthSnapshot(levels) ->
      json.object([#("levels", json.array(levels, depth_level_json))])
    DepthDelta(base, changes) ->
      json.object([
        #("baseSequence", json.int(base)),
        #("changes", json.array(changes, depth_change_json)),
      ])
    IndicativeAuction(phase, price, volume, imbalance) ->
      json.object([
        #("auctionPhase", json.string(phase)),
        #("indicativePrice", json.string(price)),
        #("indicativeVolume", json.string(volume)),
        #("imbalance", json.string(imbalance)),
        #("meaning", json.string("indicative_not_official_match_or_fill")),
      ])
    OfficialAuctionResult(phase, price, volume) ->
      json.object([
        #("auctionPhase", json.string(phase)),
        #("matchPrice", json.string(price)),
        #("matchVolume", json.string(volume)),
        #("meaning", json.string("official_result_not_broker_fill")),
      ])
    Halt(reason, resumption) ->
      json.object([
        #("haltReason", json.string(reason)),
        #("resumptionTimeUnixMilliseconds", optional_int_json(resumption)),
      ])
    StatusChange(status) -> json.object([#("status", json.string(status))])
    Correction(original, fields) ->
      json.object([
        #("originalEventId", json.string(original)),
        #("correctedFields", json.array(fields, json.string)),
      ])
    CancelBust(original, reason) ->
      json.object([
        #("originalEventId", json.string(original)),
        #("reason", json.string(reason)),
      ])
    Heartbeat -> json.object([])
  }
}

fn depth_level_json(level: DepthLevel) -> Json {
  json.object([
    #("side", json.string(side_name(level.side))),
    #("price", json.string(level.price)),
    #("visibleSize", json.string(level.visible_size)),
    #("orderCount", optional_int_json(level.order_count)),
  ])
}

fn depth_change_json(change: DepthChange) -> Json {
  json.object([
    #("side", json.string(side_name(change.side))),
    #("price", json.string(change.price)),
    #("sizeDelta", json.string(change.size_delta)),
    #("action", json.string(action_name(change.action))),
  ])
}

fn entitlement_json(value: Entitlement) -> Json {
  case value {
    RealTime -> json.object([#("kind", json.string("real_time"))])
    Delayed(minutes) ->
      json.object([
        #("kind", json.string("delayed")),
        #("minutes", json.int(minutes)),
      ])
  }
}

fn optional_int_json(value: Option(Int)) -> Json {
  case value {
    Some(value) -> json.int(value)
    None -> json.null()
  }
}

fn optional_string_json(value: Option(String)) -> Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn side_name(side: DepthSide) -> String {
  case side {
    Bid -> "bid"
    Ask -> "ask"
  }
}

fn action_name(action: DepthAction) -> String {
  case action {
    Add -> "add"
    Modify -> "modify"
    Delete -> "delete"
  }
}

fn valid_phase_name(value: String) -> Bool {
  list.contains(
    [
      "pre_session",
      "pre_open_auction",
      "opening_auction",
      "continuous",
      "interruption",
      "closing_auction",
      "post_session",
      "closed",
    ],
    value,
  )
}

fn json_parse(payload: String) -> Result(RawPacket, json.DecodeError) {
  json.parse(payload, raw_packet_decoder())
}

fn raw_packet_decoder() -> decode.Decoder(RawPacket) {
  use schema_version <- decode.field("schemaVersion", decode.string)
  use packet_id <- decode.field("packetId", decode.string)
  use track <- decode.field("track", decode.string)
  use listing_id <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use session_date <- decode.field("sessionDate", decode.string)
  use timezone <- decode.field("timezone", decode.string)
  use provider <- decode.field("provider", decode.string)
  use feed <- decode.field("feed", decode.string)
  use currency <- decode.field("currency", decode.string)
  use size_unit <- decode.field("sizeUnit", decode.string)
  use entitlement <- decode.field("entitlement", entitlement_decoder())
  use licence <- decode.field("licence", licence_decoder())
  use acquisition <- decode.field("acquisitionReceipt", decode.string)
  use sequence_scope <- decode.field("sequenceScope", decode.string)
  use heartbeat <- optional_int("expectedHeartbeatIntervalMilliseconds")
  use phases <- decode.field("phases", decode.list(of: phase_decoder()))
  use complete <- decode.field("declaredComplete", decode.bool)
  use events <- decode.field("events", decode.list(of: event_decoder()))
  decode.success(RawPacket(
    schema_version,
    packet_id,
    track,
    listing_id,
    mic,
    session_date,
    timezone,
    provider,
    feed,
    currency,
    size_unit,
    entitlement,
    licence,
    acquisition,
    sequence_scope,
    heartbeat,
    phases,
    complete,
    events,
  ))
}

fn entitlement_decoder() -> decode.Decoder(Entitlement) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "real_time" -> decode.success(RealTime)
    "delayed" -> {
      use minutes <- decode.field("minutes", decode.int)
      decode.success(Delayed(minutes))
    }
    _ -> decode.failure(RealTime, "unsupported entitlement kind")
  }
}

fn licence_decoder() -> decode.Decoder(Licence) {
  use label <- decode.field("label", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  use venues <- decode.field("venueCoverage", decode.list(of: decode.string))
  use redistribution <- decode.field("redistributionPermitted", decode.bool)
  use retention <- optional_string("retentionLimit")
  use display <- optional_string("displayUse")
  use non_display <- optional_string("nonDisplayUse")
  use derived <- optional_bool("derivedDataPermitted")
  use caching <- optional_bool("cachingPermitted")
  use logging <- optional_bool("loggingPermitted")
  use fixture <- optional_bool("fixtureUsePermitted")
  decode.success(Licence(
    label,
    receipt,
    venues,
    redistribution,
    retention,
    display,
    non_display,
    derived,
    caching,
    logging,
    fixture,
  ))
}

fn phase_decoder() -> decode.Decoder(PhaseInterval) {
  use phase <- decode.field("phase", decode.string)
  use start <- decode.field("startUnixMilliseconds", decode.int)
  use finish <- decode.field("endUnixMilliseconds", decode.int)
  use receipt <- decode.field("ruleReceipt", decode.string)
  decode.success(PhaseInterval(phase, start, finish, receipt))
}

fn event_decoder() -> decode.Decoder(Event) {
  use kind <- decode.field("type", decode.string)
  use event_id <- decode.field("eventId", decode.string)
  use listing_id <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use track <- decode.field("track", decode.string)
  use feed <- decode.field("feed", decode.string)
  use currency <- decode.field("currency", decode.string)
  use size_unit <- decode.field("sizeUnit", decode.string)
  use exchange_time <- optional_int("exchangeTimeUnixMilliseconds")
  use provider_time <- decode.field("providerTimeUnixMilliseconds", decode.int)
  use receipt_time <- decode.field("receiptTimeUnixMilliseconds", decode.int)
  use sequence <- optional_int("sequence")
  use entitlement <- decode.field("entitlement", entitlement_decoder())
  use licence <- decode.field("licenceReceipt", decode.string)
  use acquisition <- decode.field("acquisitionReceipt", decode.string)
  use conditions <- decode.field("conditions", decode.list(of: decode.string))
  use odd_lot <- decode.field("oddLot", decode.bool)
  use off_exchange <- decode.field("offExchange", decode.bool)
  use lexemes <- decode.field(
    "sourceLexemes",
    decode.dict(decode.string, decode.string),
  )
  event_body_decoder(kind)
  |> decode.then(fn(body) {
    decode.success(Event(
      Common(
        event_id,
        listing_id,
        mic,
        track,
        feed,
        currency,
        size_unit,
        exchange_time,
        provider_time,
        receipt_time,
        sequence,
        entitlement,
        licence,
        acquisition,
        conditions,
        odd_lot,
        off_exchange,
        lexemes,
      ),
      body,
    ))
  })
}

fn event_body_decoder(kind: String) -> decode.Decoder(Body) {
  case kind {
    "quote" -> {
      use bid_price <- decode.field("bidPrice", decode.string)
      use bid_size <- decode.field("bidSize", decode.string)
      use ask_price <- decode.field("askPrice", decode.string)
      use ask_size <- decode.field("askSize", decode.string)
      decode.success(Quote(bid_price, bid_size, ask_price, ask_size))
    }
    "trade" -> {
      use price <- decode.field("price", decode.string)
      use size <- decode.field("size", decode.string)
      use lineage <- optional_string("correctionLineage")
      decode.success(Trade(price, size, lineage))
    }
    "depth_snapshot" -> {
      use levels <- decode.field(
        "levels",
        decode.list(of: depth_level_decoder()),
      )
      decode.success(DepthSnapshot(levels))
    }
    "depth_delta" -> {
      use base <- decode.field("baseSequence", decode.int)
      use changes <- decode.field(
        "changes",
        decode.list(of: depth_change_decoder()),
      )
      decode.success(DepthDelta(base, changes))
    }
    "indicative_auction" -> {
      use phase <- decode.field("auctionPhase", decode.string)
      use price <- decode.field("indicativePrice", decode.string)
      use volume <- decode.field("indicativeVolume", decode.string)
      use imbalance <- decode.field("imbalance", decode.string)
      decode.success(IndicativeAuction(phase, price, volume, imbalance))
    }
    "official_auction_result" -> {
      use phase <- decode.field("auctionPhase", decode.string)
      use price <- decode.field("matchPrice", decode.string)
      use volume <- decode.field("matchVolume", decode.string)
      decode.success(OfficialAuctionResult(phase, price, volume))
    }
    "halt" -> {
      use reason <- decode.field("haltReason", decode.string)
      use resumption <- optional_int("resumptionTimeUnixMilliseconds")
      decode.success(Halt(reason, resumption))
    }
    "status_change" -> {
      use status <- decode.field("status", decode.string)
      decode.success(StatusChange(status))
    }
    "correction" -> {
      use original <- decode.field("originalEventId", decode.string)
      use fields <- decode.field(
        "correctedFields",
        decode.list(of: decode.string),
      )
      decode.success(Correction(original, fields))
    }
    "cancel_bust" -> {
      use original <- decode.field("originalEventId", decode.string)
      use reason <- decode.field("reason", decode.string)
      decode.success(CancelBust(original, reason))
    }
    "heartbeat" -> decode.success(Heartbeat)
    _ -> decode.failure(Heartbeat, "unsupported event type")
  }
}

fn depth_level_decoder() -> decode.Decoder(DepthLevel) {
  use side <- decode.field("side", side_decoder())
  use price <- decode.field("price", decode.string)
  use visible_size <- decode.field("visibleSize", decode.string)
  use order_count <- optional_int("orderCount")
  decode.success(DepthLevel(side, price, visible_size, order_count))
}

fn depth_change_decoder() -> decode.Decoder(DepthChange) {
  use side <- decode.field("side", side_decoder())
  use price <- decode.field("price", decode.string)
  use size_delta <- decode.field("sizeDelta", decode.string)
  use action <- decode.field("action", action_decoder())
  decode.success(DepthChange(side, price, size_delta, action))
}

fn side_decoder() -> decode.Decoder(DepthSide) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "bid" -> decode.success(Bid)
      "ask" -> decode.success(Ask)
      _ -> decode.failure(Bid, "unsupported depth side")
    }
  })
}

fn action_decoder() -> decode.Decoder(DepthAction) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "add" -> decode.success(Add)
      "modify" -> decode.success(Modify)
      "delete" -> decode.success(Delete)
      _ -> decode.failure(Add, "unsupported depth action")
    }
  })
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn optional_int(
  name: String,
  next: fn(Option(Int)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.int), next)
}

fn optional_bool(
  name: String,
  next: fn(Option(Bool)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.bool), next)
}
