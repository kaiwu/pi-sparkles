import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode as dynamic_decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_day_workbench/calculation
import pi_sparkles_day_workbench/decode
import pi_sparkles_day_workbench/packet
import pi_sparkles_day_workbench/workflow

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn coherent_packet_inspection_preserves_attested_claims_test() {
  let #(payload, digest) = coherent_packet()
  let assert Ok(value) = packet.parse(payload, digest, 100)
  let text =
    packet.inspect(value, 1500, 900)
    |> packet.inspection_json(True, True, 0, 20)
    |> json.to_string
  text |> string.contains("\"track\":\"us\"") |> should.be_true
  text |> string.contains("\"mic\":\"XNAS\"") |> should.be_true
  text
  |> string.contains("\"claimVerification\":\"caller_attested_not_verified\"")
  |> should.be_true
  text |> string.contains("\"phase\":\"continuous\"") |> should.be_true
  text |> string.contains("\"integrityIssues\":0") |> should.be_true
  text |> string.contains("\"current\":true") |> should.be_true
  text |> string.contains("\"sourceLexemes\"") |> should.be_true
  text |> string.contains("ready_to_trade") |> should.be_true
}

pub fn every_session_22_event_variant_decodes_without_reordering_test() {
  let events = [
    quote("q1", 1, "10.00", "100", "10.10", "90"),
    trade("t1", 2, "10.05", "20", False, False, []),
    depth_snapshot("d1", 3),
    depth_delta("d2", 4, 3),
    event("ia1", 5, "indicative_auction", [
      #("auctionPhase", json.string("opening_auction")),
      #("indicativePrice", json.string("10.02")),
      #("indicativeVolume", json.string("500")),
      #("imbalance", json.string("50")),
    ]),
    event("oa1", 6, "official_auction_result", [
      #("auctionPhase", json.string("opening_auction")),
      #("matchPrice", json.string("10.03")),
      #("matchVolume", json.string("450")),
    ]),
    event("h1", 7, "halt", [
      #("haltReason", json.string("volatility")),
      #("resumptionTimeUnixMilliseconds", json.int(2000)),
    ]),
    event("s1", 8, "status_change", [
      #("status", json.string("resumed")),
    ]),
    event("c1", 9, "correction", [
      #("originalEventId", json.string("t1")),
      #("correctedFields", json.array(["price"], json.string)),
    ]),
    event("b1", 10, "cancel_bust", [
      #("originalEventId", json.string("t1")),
      #("reason", json.string("venue_bust")),
    ]),
    event("hb1", 11, "heartbeat", []),
  ]
  let #(payload, digest) = packet_with(events, True)
  let assert Ok(value) = packet.parse(payload, digest, 100)
  let text =
    packet.inspect(value, 1500, 0)
    |> packet.inspection_json(True, False, 0, 20)
    |> json.to_string
  [
    "quote",
    "trade",
    "depth_snapshot",
    "depth_delta",
    "indicative_auction",
    "official_auction_result",
    "halt",
    "status_change",
    "correction",
    "cancel_bust",
    "heartbeat",
  ]
  |> list.each(fn(kind) {
    text |> string.contains("\"type\":\"" <> kind <> "\"") |> should.be_true
  })
  text |> string.contains("\"integrityIssues\":0") |> should.be_true
}

pub fn duplicates_conflicts_and_sequence_gaps_remain_explicit_test() {
  let first = quote("q1", 1, "10", "2", "11", "3")
  let conflicting = quote("q1", 3, "10", "2", "12", "3")
  let #(payload, digest) = packet_with([first, first, conflicting], True)
  let assert Ok(value) = packet.parse(payload, digest, 100)
  let text =
    packet.inspect(value, 2000, 0)
    |> packet.inspection_json(False, False, 0, 10)
    |> json.to_string
  text |> string.contains("\"exactDuplicatesCollapsed\":1") |> should.be_true
  text |> string.contains("\"conflictingEventIds\":1") |> should.be_true
  text |> string.contains("\"kind\":\"event_id_conflict\"") |> should.be_true
  text |> string.contains("\"kind\":\"sequence_gap\"") |> should.be_true
  text |> string.contains("\"current\":false") |> should.be_true
}

pub fn conflicting_event_variants_have_a_hard_per_id_budget_test() {
  let events = conflicting_trades(33, [])
  let #(payload, digest) = packet_with(events, True)
  case packet.parse(payload, digest, 100) {
    Error(message) ->
      message
      |> string.contains("32 distinct conflicting-variant limit")
      |> should.be_true
    Ok(_) -> should.fail()
  }
}

pub fn unsafe_embedded_packet_integers_fail_closed_test() {
  let #(payload, _) =
    packet_with([trade("t1", 1, "10", "1", False, False, [])], True)
  let unsafe =
    string.replace(
      payload,
      "\"providerTimeUnixMilliseconds\":1001",
      "\"providerTimeUnixMilliseconds\":9007199254740992",
    )
  packet.parse(unsafe, content_hash(unsafe), 10) |> should.be_error
}

pub fn future_snapshot_and_original_references_do_not_satisfy_causality_test() {
  let events = [
    depth_delta("delta-before-snapshot", 1, 2),
    depth_snapshot("snapshot-later", 2),
    event("correction-before-original", 3, "correction", [
      #("originalEventId", json.string("trade-later")),
      #("correctedFields", json.array(["price"], json.string)),
    ]),
    trade("trade-later", 4, "10", "1", False, False, []),
  ]
  let #(payload, digest) = packet_with(events, True)
  let assert Ok(value) = packet.parse(payload, digest, 100)
  let text =
    packet.inspect(value, 5000, 0)
    |> packet.inspection_json(False, False, 0, 20)
    |> json.to_string
  text |> string.contains("\"kind\":\"unbound_depth_delta\"") |> should.be_true
  text
  |> string.contains("\"kind\":\"unknown_original_reference\"")
  |> should.be_true
}

pub fn integrity_issue_output_is_paged_even_for_large_packets_test() {
  let events = gapped_trades(1002, [])
  let #(payload, digest) = packet_with(events, True)
  let assert Ok(value) = packet.parse(payload, digest, 2000)
  let text =
    packet.inspect(value, 10_000, 0)
    |> packet.inspection_json(False, False, 0, 10)
    |> json.to_string
  text |> string.contains("\"returnedIssueCount\":1000") |> should.be_true
  text |> string.contains("\"omittedIssueCount\":1") |> should.be_true
}

pub fn quote_and_trade_calculations_retain_formula_operands_test() {
  let events = [
    quote("q1", 1, "10.00", "100", "10.10", "90"),
    trade("t1", 2, "10", "2", False, False, []),
    trade("t2", 3, "12", "1", False, False, []),
  ]
  let #(payload, digest) = packet_with(events, True)
  let assert Ok(value) = packet.parse(payload, digest, 100)
  let assert Ok(spread) =
    calculation.run(value, "quoted_spread", 0, 10_000, 4, "half_even", filter())
  let spread = json.to_string(spread)
  spread |> string.contains("\"exactValue\":\"0.1\"") |> should.be_true
  spread |> string.contains("\"formula\":\"ask - bid\"") |> should.be_true
  spread |> string.contains("\"eventId\":\"q1\"") |> should.be_true

  let assert Ok(vwap) =
    calculation.run(value, "vwap", 0, 10_000, 4, "half_even", filter())
  let vwap = json.to_string(vwap)
  vwap |> string.contains("\"exactValue\":\"10.6667\"") |> should.be_true
  vwap
  |> string.contains("sum(trade_price * trade_size) / sum(trade_size)")
  |> should.be_true
  vwap
  |> string.contains("\"sourceEventIds\":[\"t1\",\"t2\"]")
  |> should.be_true
}

pub fn depth_calculations_are_exact_and_source_bound_test() {
  let #(payload, digest) = packet_with([depth_snapshot("d1", 1)], True)
  let assert Ok(value) = packet.parse(payload, digest, 100)
  let assert Ok(result) =
    calculation.run(
      value,
      "depth_imbalance",
      0,
      10_000,
      4,
      "half_even",
      filter(),
    )
  let text = json.to_string(result)
  text |> string.contains("\"state\":\"calculated\"") |> should.be_true
  text |> string.contains("\"exactValue\":\"0.6\"") |> should.be_true
  text |> string.contains("\"sourceEventIds\":[\"d1\"]") |> should.be_true
  text |> string.contains("not a signal") |> should.be_true
}

pub fn gaps_incomplete_packets_and_unreplaced_corrections_are_unperformed_test() {
  let #(gap_payload, gap_digest) =
    packet_with(
      [
        trade("t1", 1, "10", "2", False, False, []),
        trade("t2", 3, "11", "2", False, False, []),
      ],
      True,
    )
  let assert Ok(gap_packet) = packet.parse(gap_payload, gap_digest, 100)
  let assert Ok(gap) =
    calculation.run(
      gap_packet,
      "cumulative_volume",
      0,
      10_000,
      2,
      "half_even",
      filter(),
    )
  json.to_string(gap)
  |> string.contains("packet_integrity_issues_present")
  |> should.be_true

  let #(partial_payload, partial_digest) =
    packet_with(
      [
        trade("t1", 1, "10", "2", False, False, []),
      ],
      False,
    )
  let assert Ok(partial_packet) =
    packet.parse(partial_payload, partial_digest, 100)
  let assert Ok(partial) =
    calculation.run(
      partial_packet,
      "cumulative_volume",
      0,
      10_000,
      2,
      "half_even",
      filter(),
    )
  json.to_string(partial)
  |> string.contains("packet_declared_incomplete")
  |> should.be_true

  let #(correction_payload, correction_digest) =
    packet_with(
      [
        trade("t1", 1, "10", "2", False, False, []),
        event("c1", 2, "correction", [
          #("originalEventId", json.string("t1")),
          #("correctedFields", json.array(["price"], json.string)),
        ]),
      ],
      True,
    )
  let assert Ok(correction_packet) =
    packet.parse(correction_payload, correction_digest, 100)
  let assert Ok(corrected) =
    calculation.run(
      correction_packet,
      "cumulative_turnover",
      0,
      10_000,
      2,
      "half_even",
      filter(),
    )
  json.to_string(corrected)
  |> string.contains("correction_values_require_explicit_replacement_events")
  |> should.be_true
}

pub fn cancel_bust_and_explicit_event_filters_control_only_operands_test() {
  let #(payload, digest) =
    packet_with(
      [
        trade("t1", 1, "10", "2", False, False, []),
        trade("t2", 2, "11", "3", True, False, ["ODD"]),
        trade("t3", 3, "12", "4", False, False, []),
        event("b1", 4, "cancel_bust", [
          #("originalEventId", json.string("t1")),
          #("reason", json.string("venue_bust")),
        ]),
      ],
      True,
    )
  let assert Ok(value) = packet.parse(payload, digest, 100)
  let assert Ok(default_result) =
    calculation.run(
      value,
      "cumulative_volume",
      0,
      10_000,
      2,
      "half_even",
      filter(),
    )
  json.to_string(default_result)
  |> string.contains("\"exactValue\":\"4\"")
  |> should.be_true
  let assert Ok(including_odd_lot) =
    calculation.run(
      value,
      "cumulative_volume",
      0,
      10_000,
      2,
      "half_even",
      decode.EventFilter(True, False, ["ODD"]),
    )
  json.to_string(including_odd_lot)
  |> string.contains("\"exactValue\":\"7\"")
  |> should.be_true
}

pub fn workflow_is_branch_bound_idempotent_and_replay_validated_test() {
  let initial =
    transition(
      None,
      None,
      "t1",
      "k1",
      "initialize_preparation",
      "user_authored",
      1,
      [],
      [],
    )
  let assert Ok(initial_result) = workflow.transition(initial)
  let #(payload1, hash1) = next_state(initial_result)
  let acquiring =
    transition(
      Some(payload1),
      Some(hash1),
      "t2",
      "k2",
      "begin_acquisition",
      "llm_authored",
      2,
      [],
      [],
    )
  let assert Ok(acquiring_result) = workflow.transition(acquiring)
  let acquiring_text = json.to_string(acquiring_result)
  acquiring_text |> string.contains("\"name\":\"acquiring\"") |> should.be_true
  let #(payload2, hash2) = next_state(acquiring_result)
  let available =
    transition(
      Some(payload2),
      Some(hash2),
      "t3",
      "k3",
      "evidence_available",
      "mechanical_fact",
      3,
      [hex("e")],
      [],
    )
  let assert Ok(ready_result) = workflow.transition(available)
  let ready_text = json.to_string(ready_result)
  ready_text
  |> string.contains("evidence_available mechanical state")
  |> should.be_true
  ready_text |> string.contains("never ready_to_trade") |> should.be_true

  let #(ready_payload, ready_hash) = next_state(ready_result)
  let retry =
    decode.TransitionInput(
      ..available,
      current_state_payload: Some(ready_payload),
      current_state_hash: Some(ready_hash),
    )
  let assert Ok(idempotent) = workflow.transition(retry)
  json.to_string(idempotent)
  |> string.contains("\"idempotent\":true")
  |> should.be_true

  let wrong_branch = decode.TransitionInput(..available, branch_id: "branch-b")
  case workflow.transition(wrong_branch) {
    Error(message) ->
      message |> string.contains("branchId does not match") |> should.be_true
    Ok(_) -> should.fail()
  }

  let forged_payload =
    string.replace(payload2, "\"revision\":2", "\"revision\":9")
  let forged =
    decode.TransitionInput(
      ..available,
      current_state_payload: Some(forged_payload),
      current_state_hash: Some(content_hash(forged_payload)),
    )
  case workflow.transition(forged) {
    Error(message) ->
      message |> string.contains("revision does not match") |> should.be_true
    Ok(_) -> should.fail()
  }
}

pub fn mechanical_transition_and_live_mutation_laws_fail_closed_test() {
  let initial =
    transition(
      None,
      None,
      "t1",
      "k1",
      "initialize_preparation",
      "user_authored",
      1,
      [],
      [],
    )
  let assert Ok(initial_result) = workflow.transition(initial)
  let #(payload, digest) = next_state(initial_result)
  let acquiring =
    transition(
      Some(payload),
      Some(digest),
      "t2",
      "k2",
      "begin_acquisition",
      "user_authored",
      2,
      [],
      [],
    )
  let assert Ok(acquiring_result) = workflow.transition(acquiring)
  let #(payload, digest) = next_state(acquiring_result)
  let without_evidence =
    transition(
      Some(payload),
      Some(digest),
      "t3",
      "k3",
      "evidence_available",
      "mechanical_fact",
      3,
      [],
      [],
    )
  case workflow.transition(without_evidence) {
    Error(message) ->
      message
      |> string.contains("requires evidenceReferences")
      |> should.be_true
    Ok(_) -> should.fail()
  }
  let mutation =
    decode.TransitionInput(
      ..without_evidence,
      event_kind: "submit_order",
      origin: "user_authored",
      evidence_references: [hex("e")],
    )
  case workflow.transition(mutation) {
    Error(message) ->
      message |> string.contains("behind CG-LIVE") |> should.be_true
    Ok(_) -> should.fail()
  }
}

pub fn invalid_track_licence_scope_and_event_budget_reject_test() {
  let #(payload, digest) = coherent_packet()
  case packet.parse(payload, digest, 1) {
    Error(message) ->
      message |> string.contains("caller maximumEvents") |> should.be_true
    Ok(_) -> should.fail()
  }
  let bad_track =
    string.replace(payload, "\"track\":\"us\"", "\"track\":\"global\"")
  case packet.parse(bad_track, content_hash(bad_track), 100) {
    Error(message) ->
      message
      |> string.contains("track must be cn, hk, or us")
      |> should.be_true
    Ok(_) -> should.fail()
  }
  let bad_licence =
    string.replace(
      payload,
      "\"venueCoverage\":[\"XNAS\"]",
      "\"venueCoverage\":[\"XNYS\"]",
    )
  case packet.parse(bad_licence, content_hash(bad_licence), 100) {
    Error(message) ->
      message
      |> string.contains("does not include packet MIC")
      |> should.be_true
    Ok(_) -> should.fail()
  }
}

fn coherent_packet() -> #(String, String) {
  packet_with(
    [
      quote("q1", 1, "10.00", "100", "10.10", "90"),
      trade("t1", 2, "10.05", "20", False, False, []),
      depth_snapshot("d1", 3),
    ],
    True,
  )
}

fn conflicting_trades(remaining: Int, reversed: List(Json)) -> List(Json) {
  case remaining {
    0 -> list.reverse(reversed)
    value ->
      conflicting_trades(value - 1, [
        trade("same-id", value, int.to_string(value), "1", False, False, []),
        ..reversed
      ])
  }
}

fn gapped_trades(remaining: Int, reversed: List(Json)) -> List(Json) {
  case remaining {
    0 -> list.reverse(reversed)
    value ->
      gapped_trades(value - 1, [
        trade(
          "gap-" <> int.to_string(value),
          value * 2,
          "10",
          "1",
          False,
          False,
          [],
        ),
        ..reversed
      ])
  }
}

fn packet_with(events: List(Json), complete: Bool) -> #(String, String) {
  let payload =
    json.object([
      #("schemaVersion", json.string("pi_day_intraday_packet_v1")),
      #("packetId", json.string("packet-1")),
      #("track", json.string("us")),
      #("listingId", json.string("listing-aapl-xnas")),
      #("mic", json.string("XNAS")),
      #("sessionDate", json.string("2026-08-07")),
      #("timezone", json.string("America/New_York")),
      #("provider", json.string("caller-provider")),
      #("feed", json.string("caller-feed")),
      #("currency", json.string("USD")),
      #("sizeUnit", json.string("shares")),
      #("entitlement", json.object([#("kind", json.string("real_time"))])),
      #(
        "licence",
        json.object([
          #("label", json.string("caller-private-display")),
          #("receipt", json.string(hex("a"))),
          #("venueCoverage", json.array(["XNAS"], json.string)),
          #("redistributionPermitted", json.bool(False)),
          #("retentionLimit", json.string("session_only")),
          #("displayUse", json.string("private")),
          #("nonDisplayUse", json.null()),
          #("derivedDataPermitted", json.bool(True)),
          #("cachingPermitted", json.bool(False)),
          #("loggingPermitted", json.bool(False)),
          #("fixtureUsePermitted", json.bool(True)),
        ]),
      ),
      #("acquisitionReceipt", json.string(hex("b"))),
      #("sequenceScope", json.string("per_listing")),
      #("expectedHeartbeatIntervalMilliseconds", json.null()),
      #(
        "phases",
        json.array(
          [
            json.object([
              #("phase", json.string("continuous")),
              #("startUnixMilliseconds", json.int(1000)),
              #("endUnixMilliseconds", json.int(2000)),
              #("ruleReceipt", json.string(hex("c"))),
            ]),
          ],
          fn(value) { value },
        ),
      ),
      #("declaredComplete", json.bool(complete)),
      #("events", json.array(events, fn(value) { value })),
    ])
    |> json.to_string
  #(payload, content_hash(payload))
}

fn event(
  id: String,
  sequence: Int,
  kind: String,
  details: List(#(String, Json)),
) -> Json {
  json.object(list.append(
    common_fields(id, sequence, kind, False, False, []),
    details,
  ))
}

fn quote(
  id: String,
  sequence: Int,
  bid: String,
  bid_size: String,
  ask: String,
  ask_size: String,
) -> Json {
  event(id, sequence, "quote", [
    #("bidPrice", json.string(bid)),
    #("bidSize", json.string(bid_size)),
    #("askPrice", json.string(ask)),
    #("askSize", json.string(ask_size)),
  ])
}

fn trade(
  id: String,
  sequence: Int,
  price: String,
  size: String,
  odd_lot: Bool,
  off_exchange: Bool,
  conditions: List(String),
) -> Json {
  json.object(
    list.append(
      common_fields(id, sequence, "trade", odd_lot, off_exchange, conditions),
      [
        #("price", json.string(price)),
        #("size", json.string(size)),
        #("correctionLineage", json.null()),
      ],
    ),
  )
}

fn depth_snapshot(id: String, sequence: Int) -> Json {
  event(id, sequence, "depth_snapshot", [
    #(
      "levels",
      json.array(
        [
          json.object([
            #("side", json.string("bid")),
            #("price", json.string("10")),
            #("visibleSize", json.string("60")),
            #("orderCount", json.int(3)),
          ]),
          json.object([
            #("side", json.string("ask")),
            #("price", json.string("10.1")),
            #("visibleSize", json.string("40")),
            #("orderCount", json.int(2)),
          ]),
        ],
        fn(value) { value },
      ),
    ),
  ])
}

fn depth_delta(id: String, sequence: Int, base: Int) -> Json {
  event(id, sequence, "depth_delta", [
    #("baseSequence", json.int(base)),
    #(
      "changes",
      json.array(
        [
          json.object([
            #("side", json.string("bid")),
            #("price", json.string("10")),
            #("sizeDelta", json.string("5")),
            #("action", json.string("modify")),
          ]),
        ],
        fn(value) { value },
      ),
    ),
  ])
}

fn common_fields(
  id: String,
  sequence: Int,
  kind: String,
  odd_lot: Bool,
  off_exchange: Bool,
  conditions: List(String),
) -> List(#(String, Json)) {
  [
    #("type", json.string(kind)),
    #("eventId", json.string(id)),
    #("listingId", json.string("listing-aapl-xnas")),
    #("mic", json.string("XNAS")),
    #("track", json.string("us")),
    #("feed", json.string("caller-feed")),
    #("currency", json.string("USD")),
    #("sizeUnit", json.string("shares")),
    #("exchangeTimeUnixMilliseconds", json.int(1000 + sequence)),
    #("providerTimeUnixMilliseconds", json.int(1000 + sequence)),
    #("receiptTimeUnixMilliseconds", json.int(1010 + sequence)),
    #("sequence", json.int(sequence)),
    #("entitlement", json.object([#("kind", json.string("real_time"))])),
    #("licenceReceipt", json.string(hex("a"))),
    #("acquisitionReceipt", json.string(hex("b"))),
    #("conditions", json.array(conditions, json.string)),
    #("oddLot", json.bool(odd_lot)),
    #("offExchange", json.bool(off_exchange)),
    #(
      "sourceLexemes",
      json.object([
        #("raw", json.string("caller supplied event " <> id)),
      ]),
    ),
  ]
}

fn filter() -> decode.EventFilter {
  decode.EventFilter(False, False, [])
}

fn transition(
  state_payload: Option(String),
  state_hash: Option(String),
  transition_id: String,
  key: String,
  event_kind: String,
  origin: String,
  occurred_at: Int,
  evidence: List(String),
  execution: List(String),
) -> decode.TransitionInput {
  let payload = "{\"declaration\":\"" <> event_kind <> "\"}"
  decode.TransitionInput(
    state_payload,
    state_hash,
    "workflow-1",
    "branch-a",
    transition_id,
    key,
    event_kind,
    origin,
    occurred_at,
    payload,
    content_hash(payload),
    evidence,
    execution,
  )
}

fn next_state(value: Json) -> #(String, String) {
  let decoder = {
    use payload <- dynamic_decode.field(
      "nextStatePayload",
      dynamic_decode.string,
    )
    use digest <- dynamic_decode.field("nextStateHash", dynamic_decode.string)
    dynamic_decode.success(#(payload, digest))
  }
  let assert Ok(value) = json.parse(json.to_string(value), decoder)
  value
}

fn content_hash(value: String) -> String {
  let assert Ok(value) = hash.text(value)
  identity.sha256_value(value)
}

fn hex(character: String) -> String {
  string.repeat(character, times: 64)
}
