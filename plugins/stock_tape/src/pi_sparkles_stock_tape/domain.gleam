import finance_core/identifier
import finance_provenance/hash
import finance_provenance/identity
import finance_tape
import finance_track
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import pi_sparkles_stock_tape/decode

const maximum_page_size = 1000

pub opaque type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  TapeCoreError(error: finance_tape.TapeError)
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> Json {
  value.details
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid stock-tape field " <> field <> ": " <> reason
    TapeCoreError(error) -> finance_tape.error_message(error)
  }
}

pub fn run(input: decode.Input) -> Result(Response, DomainError) {
  use track <- result.try(
    finance_track.from_name(input.track)
    |> result.map_error(fn(_) {
      InvalidField("track", "expected exactly cn, hk, or us")
    }),
  )
  use mic <- result.try(
    identifier.mic(input.mic)
    |> result.map_error(fn(_) { InvalidField("mic", "must be a valid MIC") }),
  )
  use _ <- result.try(validate_track_mic(track, identifier.mic_value(mic)))
  use provider_receipt <- result.try(parse_hash(
    "providerReceiptHash",
    input.provider_receipt_hash,
  ))
  use coverage <- result.try(parse_coverage(input.coverage))
  use condition_coverage <- result.try(parse_condition_coverage(
    input.condition_coverage,
  ))
  use events <- result.try(parse_events(input.events, 0, []))
  use packet <- result.try(
    finance_tape.packet(
      track: track,
      listing_id: input.listing_id,
      mic: mic,
      session_id: input.session_id,
      provider: input.provider,
      feed: input.feed,
      entitlement: input.entitlement,
      licence: input.licence,
      coverage: coverage,
      condition_coverage: condition_coverage,
      maximum_events: input.maximum_events,
      events: events,
    )
    |> result.map_error(TapeCoreError),
  )
  use page <- result.try(parse_page(input.page, list.length(events)))
  let review = finance_tape.review(packet)
  let selected = events |> list.drop(page.0) |> list.take(page.1)
  let returned = list.length(selected)
  let next_offset = case page.0 + returned < list.length(events) {
    True -> Some(page.0 + returned)
    False -> None
  }
  let receipt_projection = packet_json(packet, events, provider_receipt)
  let assert Ok(tape_receipt) =
    receipt_projection |> json.to_string |> hash.text
  let details =
    json.object([
      #("schemaVersion", json.int(1)),
      #("operation", json.string("stock_tape")),
      #("track", json.string(finance_track.name(track))),
      #("listingId", json.string(finance_tape.packet_listing_id(packet))),
      #(
        "mic",
        json.string(identifier.mic_value(finance_tape.packet_mic(packet))),
      ),
      #("sessionId", json.string(finance_tape.packet_session_id(packet))),
      #(
        "providerCapability",
        json.object([
          #("provider", json.string(finance_tape.packet_provider(packet))),
          #("feed", json.string(finance_tape.packet_feed(packet))),
          #("dependencyMode", json.string("explicit_external_capability")),
          #("networkPerformed", json.bool(False)),
          #("credentialAccepted", json.bool(False)),
          #("providerAuthenticatedByPlugin", json.bool(False)),
          #("openDRequiredByPackage", json.bool(False)),
          #("adapterBundled", json.bool(False)),
          #(
            "providerReceiptHash",
            json.string(identity.sha256_value(provider_receipt)),
          ),
        ]),
      ),
      #("entitlement", json.string(finance_tape.packet_entitlement(packet))),
      #("licence", json.string(finance_tape.packet_licence(packet))),
      #("coverage", coverage_json(finance_tape.packet_coverage(packet))),
      #("review", review_json(review)),
      #(
        "page",
        json.object([
          #("offset", json.int(page.0)),
          #("limit", json.int(page.1)),
          #("returned", json.int(returned)),
          #("total", json.int(list.length(events))),
          #("nextOffset", json.nullable(next_offset, json.int)),
          #("order", json.string("provider_packet_order")),
        ]),
      ),
      #("events", json.array(selected, event_json)),
      #("tapeReceiptHash", json.string(identity.sha256_value(tape_receipt))),
      #("receiptProjection", json.string("validated_exact_bounded_packet_v1")),
      #(
        "assessmentStatus",
        json.string("mechanical_tape_review_only_no_trading_judgment"),
      ),
      #("executable", json.bool(False)),
      #(
        "limitations",
        json.array(
          [
            "external provider capability must be selected and supplied explicitly",
            "a matching content receipt is byte-integrity evidence, not provider authentication",
            "provider-declared completeness is not exchange attestation",
            "sequence gaps and resets are reported but never repaired",
            "unknown or conflicting correction lineage remains unresolved",
            "clock deltas are observations unless synchronization is independently established",
            "no quote, order book, signal, recommendation, or broker mutation is performed",
          ],
          json.string,
        ),
      ),
    ])
  Ok(Response(
    finance_track.name(track)
      <> " transaction tape | "
      <> input.listing_id
      <> " @ "
      <> identifier.mic_value(mic)
      <> " | "
      <> int.to_string(list.length(events))
      <> " events / "
      <> int.to_string(list.length(finance_tape.review_sequence_issues(review)))
      <> " sequence issues / "
      <> int.to_string(list.length(finance_tape.review_lineage_issues(review)))
      <> " lineage issues",
    details,
  ))
}

fn parse_page(
  page: decode.PageInput,
  total: Int,
) -> Result(#(Int, Int), DomainError) {
  case page.offset >= 0 && page.offset <= total {
    False -> Error(InvalidField("page.offset", "must be within the packet"))
    True ->
      case page.limit >= 1 && page.limit <= maximum_page_size {
        True -> Ok(#(page.offset, page.limit))
        False -> Error(InvalidField("page.limit", "must be between 1 and 1000"))
      }
  }
}

fn validate_track_mic(
  track: finance_track.Track,
  mic: String,
) -> Result(Nil, DomainError) {
  let allowed = case track {
    finance_track.Cn -> ["XSHG", "XSHE", "XBSE"]
    finance_track.Hk -> ["XHKG"]
    finance_track.Us -> ["XNYS", "XNAS"]
  }
  case list.contains(allowed, mic) {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "mic",
        "is outside the exact " <> finance_track.name(track) <> " tape scope",
      ))
  }
}

fn parse_coverage(
  value: decode.CoverageInput,
) -> Result(finance_tape.Coverage, DomainError) {
  case value.state, value.reference_hash, value.reason {
    "provider_declared_complete", Some(reference), None -> {
      use receipt <- result.try(parse_hash("coverage.referenceHash", reference))
      Ok(finance_tape.ProviderDeclaredComplete(receipt))
    }
    "bounded_partial", None, Some(reason) ->
      Ok(finance_tape.BoundedPartial(reason))
    "unknown", None, Some(reason) -> Ok(finance_tape.UnknownCoverage(reason))
    _, _, _ ->
      Error(InvalidField(
        "coverage",
        "requires exactly the fields for provider_declared_complete, bounded_partial, or unknown",
      ))
  }
}

fn parse_condition_coverage(
  value: decode.ConditionCoverageInput,
) -> Result(finance_tape.ConditionCoverage, DomainError) {
  case value.state, value.reference_hash, value.reason {
    "documented", Some(reference), None -> {
      use receipt <- result.try(parse_hash(
        "conditionCoverage.referenceHash",
        reference,
      ))
      Ok(finance_tape.DocumentedConditions(value.codes, receipt))
    }
    "partially_documented", Some(reference), Some(reason) -> {
      use receipt <- result.try(parse_hash(
        "conditionCoverage.referenceHash",
        reference,
      ))
      Ok(finance_tape.PartiallyDocumentedConditions(
        value.codes,
        receipt,
        reason,
      ))
    }
    "undocumented", None, Some(reason) ->
      case value.codes {
        [] -> Ok(finance_tape.UndocumentedConditions(reason))
        _ ->
          Error(InvalidField(
            "conditionCoverage.codes",
            "must be empty when condition coverage is undocumented",
          ))
      }
    _, _, _ ->
      Error(InvalidField(
        "conditionCoverage",
        "requires exactly the fields for documented, partially_documented, or undocumented",
      ))
  }
}

fn parse_events(
  remaining: List(decode.EventInput),
  index: Int,
  reversed: List(finance_tape.Event),
) -> Result(List(finance_tape.Event), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use event <- result.try(parse_event(value, index))
      parse_events(rest, index + 1, [event, ..reversed])
    }
  }
}

fn parse_event(
  value: decode.EventInput,
  index: Int,
) -> Result(finance_tape.Event, DomainError) {
  let field = "events[" <> int.to_string(index) <> "]"
  use kind <- result.try(parse_kind(value.kind, field <> ".kind"))
  use price <- result.try(parse_lexeme(value.price, field <> ".price"))
  use size <- result.try(parse_lexeme(value.size, field <> ".size"))
  let decode.ClocksInput(exchange, provider, retrieved) = value.clocks
  use clocks <- result.try(
    finance_tape.clocks(exchange, provider, retrieved)
    |> result.map_error(TapeCoreError),
  )
  use sequence <- result.try(parse_sequence(
    value.sequence,
    field <> ".sequence",
  ))
  use receipt <- result.try(parse_hash(
    field <> ".rawReceiptHash",
    value.raw_receipt_hash,
  ))
  finance_tape.event(
    event_id: value.event_id,
    trade_id: value.trade_id,
    kind: kind,
    price: price,
    size: size,
    condition_codes: value.condition_codes,
    venue_lexeme: value.venue_lexeme,
    clocks: clocks,
    sequence: sequence,
    raw_receipt_hash: receipt,
  )
  |> result.map_error(TapeCoreError)
}

fn parse_kind(
  value: decode.EventKindInput,
  field: String,
) -> Result(finance_tape.EventKind, DomainError) {
  case value.state, value.reference_event_id, value.reference_trade_id {
    "original", None, None -> Ok(finance_tape.OriginalTrade)
    "correction", Some(reference), trade ->
      Ok(finance_tape.Correction(reference, trade))
    "cancel", Some(reference), trade ->
      Ok(finance_tape.Cancel(reference, trade))
    _, _, _ ->
      Error(InvalidField(field, "has an invalid state/reference shape"))
  }
}

fn parse_lexeme(
  value: decode.LexemeInput,
  field: String,
) -> Result(finance_tape.Lexeme, DomainError) {
  case value.state, value.value, value.values, value.reason {
    "known", Some(lexeme), [], None -> Ok(finance_tape.KnownLexeme(lexeme))
    "unavailable", None, [], Some(reason) ->
      Ok(finance_tape.UnavailableLexeme(reason))
    "conflicting", None, values, Some(_) ->
      Ok(finance_tape.ConflictingLexemes(values))
    _, _, _, _ ->
      Error(InvalidField(
        field,
        "has an invalid known/unavailable/conflicting shape",
      ))
  }
}

fn parse_sequence(
  value: decode.SequenceInput,
  field: String,
) -> Result(finance_tape.SequenceMarker, DomainError) {
  case
    value.state,
    value.scope,
    value.value,
    value.values,
    value.declared_previous,
    value.reason
  {
    "sequenced", Some(scope), Some(sequence), [], None, None ->
      Ok(finance_tape.Sequenced(scope, sequence))
    "reset", Some(scope), Some(sequence), [], previous, None ->
      Ok(finance_tape.SequenceReset(scope, sequence, previous))
    "unavailable", None, None, [], None, Some(reason) ->
      Ok(finance_tape.SequenceUnavailable(reason))
    "conflicting", Some(scope), None, values, None, Some(_) ->
      Ok(finance_tape.SequenceConflicting(scope, values))
    _, _, _, _, _, _ ->
      Error(InvalidField(
        field,
        "has an invalid sequenced/reset/unavailable/conflicting shape",
      ))
  }
}

fn parse_hash(
  field: String,
  value: String,
) -> Result(identity.Sha256, DomainError) {
  identity.sha256(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "must be a SHA-256 hex value")
  })
}

fn packet_json(
  packet: finance_tape.Packet,
  events: List(finance_tape.Event),
  provider_receipt: identity.Sha256,
) -> Json {
  json.object([
    #(
      "track",
      json.string(finance_track.name(finance_tape.packet_track(packet))),
    ),
    #("listingId", json.string(finance_tape.packet_listing_id(packet))),
    #("mic", json.string(identifier.mic_value(finance_tape.packet_mic(packet)))),
    #("sessionId", json.string(finance_tape.packet_session_id(packet))),
    #("provider", json.string(finance_tape.packet_provider(packet))),
    #("feed", json.string(finance_tape.packet_feed(packet))),
    #("entitlement", json.string(finance_tape.packet_entitlement(packet))),
    #("licence", json.string(finance_tape.packet_licence(packet))),
    #(
      "providerReceiptHash",
      json.string(identity.sha256_value(provider_receipt)),
    ),
    #("coverage", coverage_json(finance_tape.packet_coverage(packet))),
    #("events", json.array(events, event_json)),
  ])
}

fn coverage_json(value: finance_tape.Coverage) -> Json {
  case value {
    finance_tape.ProviderDeclaredComplete(reference) ->
      json.object([
        #("state", json.string("provider_declared_complete")),
        #("referenceHash", json.string(identity.sha256_value(reference))),
        #("authenticated", json.bool(False)),
      ])
    finance_tape.BoundedPartial(reason) ->
      json.object([
        #("state", json.string("bounded_partial")),
        #("reason", json.string(reason)),
        #("authenticated", json.bool(False)),
      ])
    finance_tape.UnknownCoverage(reason) ->
      json.object([
        #("state", json.string("unknown")),
        #("reason", json.string(reason)),
        #("authenticated", json.bool(False)),
      ])
  }
}

fn event_json(value: finance_tape.Event) -> Json {
  let clocks = finance_tape.event_clocks(value)
  json.object([
    #("eventId", json.string(finance_tape.event_id(value))),
    #("tradeId", json.string(finance_tape.trade_id(value))),
    #("kind", kind_json(finance_tape.event_kind(value))),
    #("price", lexeme_json(finance_tape.event_price(value))),
    #("size", lexeme_json(finance_tape.event_size(value))),
    #(
      "conditionCodes",
      json.array(finance_tape.event_condition_codes(value), json.string),
    ),
    #("venueLexeme", json.string(finance_tape.event_venue_lexeme(value))),
    #(
      "clocks",
      json.object([
        #(
          "exchangeUnixMilliseconds",
          json.nullable(
            finance_tape.exchange_unix_milliseconds(clocks),
            json.int,
          ),
        ),
        #(
          "providerUnixMilliseconds",
          json.nullable(
            finance_tape.provider_unix_milliseconds(clocks),
            json.int,
          ),
        ),
        #(
          "retrievedUnixMilliseconds",
          json.int(finance_tape.retrieved_unix_milliseconds(clocks)),
        ),
      ]),
    ),
    #("sequence", sequence_json(finance_tape.event_sequence(value))),
    #(
      "rawReceiptHash",
      json.string(
        identity.sha256_value(finance_tape.event_raw_receipt_hash(value)),
      ),
    ),
  ])
}

fn kind_json(value: finance_tape.EventKind) -> Json {
  case value {
    finance_tape.OriginalTrade ->
      json.object([#("state", json.string("original"))])
    finance_tape.Correction(reference, trade) ->
      json.object([
        #("state", json.string("correction")),
        #("referenceEventId", json.string(reference)),
        #("referenceTradeId", json.nullable(trade, json.string)),
      ])
    finance_tape.Cancel(reference, trade) ->
      json.object([
        #("state", json.string("cancel")),
        #("referenceEventId", json.string(reference)),
        #("referenceTradeId", json.nullable(trade, json.string)),
      ])
  }
}

fn lexeme_json(value: finance_tape.Lexeme) -> Json {
  case value {
    finance_tape.KnownLexeme(value) ->
      json.object([
        #("state", json.string("known")),
        #("value", json.string(value)),
      ])
    finance_tape.UnavailableLexeme(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("reason", json.string(reason)),
      ])
    finance_tape.ConflictingLexemes(values) ->
      json.object([
        #("state", json.string("conflicting")),
        #("values", json.array(values, json.string)),
      ])
  }
}

fn sequence_json(value: finance_tape.SequenceMarker) -> Json {
  case value {
    finance_tape.Sequenced(scope, sequence) ->
      json.object([
        #("state", json.string("sequenced")),
        #("scope", json.string(scope)),
        #("value", json.string(sequence)),
      ])
    finance_tape.SequenceReset(scope, sequence, previous) ->
      json.object([
        #("state", json.string("reset")),
        #("scope", json.string(scope)),
        #("value", json.string(sequence)),
        #("declaredPrevious", json.nullable(previous, json.string)),
      ])
    finance_tape.SequenceUnavailable(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("reason", json.string(reason)),
      ])
    finance_tape.SequenceConflicting(scope, values) ->
      json.object([
        #("state", json.string("conflicting")),
        #("scope", json.string(scope)),
        #("values", json.array(values, json.string)),
      ])
  }
}

fn review_json(value: finance_tape.Review) -> Json {
  json.object([
    #(
      "eventTimeOrder",
      event_time_order_json(finance_tape.event_time_order(value)),
    ),
    #(
      "duplicateExactEventCount",
      json.int(finance_tape.duplicate_exact_event_count(value)),
    ),
    #(
      "duplicateEventIds",
      json.array(finance_tape.duplicate_event_id_values(value), json.string),
    ),
    #(
      "conflictingEventIds",
      json.array(finance_tape.conflicting_event_id_values(value), json.string),
    ),
    #(
      "duplicateOriginalTradeIds",
      json.array(
        finance_tape.duplicate_original_trade_id_values(value),
        json.string,
      ),
    ),
    #(
      "sequenceIssues",
      json.array(
        finance_tape.review_sequence_issues(value),
        sequence_issue_json,
      ),
    ),
    #(
      "lineageIssues",
      json.array(finance_tape.review_lineage_issues(value), lineage_issue_json),
    ),
    #(
      "clockDeltas",
      json.array(finance_tape.review_clock_deltas(value), clock_delta_json),
    ),
    #(
      "conditionCounts",
      json.array(
        finance_tape.review_condition_counts(value),
        condition_count_json,
      ),
    ),
    #(
      "undocumentedConditionCodes",
      json.array(
        finance_tape.review_undocumented_condition_codes(value),
        json.string,
      ),
    ),
    #(
      "conditionDocumentationComplete",
      json.bool(finance_tape.review_condition_documentation_complete(value)),
    ),
    #(
      "providerDeclaredComplete",
      json.bool(finance_tape.review_provider_declared_complete(value)),
    ),
  ])
}

fn event_time_order_json(value: finance_tape.EventTimeOrder) -> Json {
  case value {
    finance_tape.Nondecreasing(basis) ->
      json.object([
        #("state", json.string("nondecreasing")),
        #("basis", json.string(ordering_basis(basis))),
      ])
    finance_tape.Nonmonotonic(basis, event_ids) ->
      json.object([
        #("state", json.string("nonmonotonic")),
        #("basis", json.string(ordering_basis(basis))),
        #("eventIds", json.array(event_ids, json.string)),
      ])
  }
}

fn ordering_basis(value: finance_tape.OrderingBasis) -> String {
  case value {
    finance_tape.ExchangeClock -> "exchange_clock"
    finance_tape.ProviderClock -> "provider_clock"
    finance_tape.RetrievalClock -> "retrieval_clock"
  }
}

fn sequence_issue_json(value: finance_tape.SequenceIssue) -> Json {
  case value {
    finance_tape.SequenceGap(scope, previous, expected, received, event_id) ->
      issue_json("gap", event_id, [
        #("scope", json.string(scope)),
        #("previous", json.string(previous)),
        #("expected", json.string(expected)),
        #("received", json.string(received)),
      ])
    finance_tape.DuplicateSequence(scope, sequence, event_id) ->
      issue_json("duplicate", event_id, [
        #("scope", json.string(scope)),
        #("value", json.string(sequence)),
      ])
    finance_tape.OutOfOrderSequence(scope, previous, received, event_id) ->
      issue_json("out_of_order", event_id, [
        #("scope", json.string(scope)),
        #("previous", json.string(previous)),
        #("received", json.string(received)),
      ])
    finance_tape.SequenceScopeChanged(previous, received, event_id) ->
      issue_json("scope_changed", event_id, [
        #("previousScope", json.string(previous)),
        #("receivedScope", json.string(received)),
      ])
    finance_tape.ResetBoundary(scope, sequence, previous, event_id) ->
      issue_json("reset_boundary", event_id, [
        #("scope", json.string(scope)),
        #("value", json.string(sequence)),
        #("declaredPrevious", json.nullable(previous, json.string)),
      ])
    finance_tape.ResetPreviousMismatch(scope, observed, declared, event_id) ->
      issue_json("reset_previous_mismatch", event_id, [
        #("scope", json.string(scope)),
        #("observedPrevious", json.string(observed)),
        #("declaredPrevious", json.string(declared)),
      ])
    finance_tape.UnavailableSequence(reason, event_id) ->
      issue_json("unavailable", event_id, [#("reason", json.string(reason))])
    finance_tape.ConflictingSequence(scope, values, event_id) ->
      issue_json("conflicting", event_id, [
        #("scope", json.string(scope)),
        #("values", json.array(values, json.string)),
      ])
  }
}

fn lineage_issue_json(value: finance_tape.LineageIssue) -> Json {
  case value {
    finance_tape.MissingReference(event_id, reference) ->
      issue_json("missing_reference", event_id, [
        #("referenceEventId", json.string(reference)),
      ])
    finance_tape.AmbiguousReference(event_id, reference) ->
      issue_json("ambiguous_reference", event_id, [
        #("referenceEventId", json.string(reference)),
      ])
    finance_tape.SelfReference(event_id) ->
      issue_json("self_reference", event_id, [])
    finance_tape.TradeReferenceMismatch(event_id, expected, received) ->
      issue_json("trade_reference_mismatch", event_id, [
        #("expectedTradeId", json.string(expected)),
        #("receivedTradeId", json.string(received)),
      ])
    finance_tape.CancelReference(event_id, reference) ->
      issue_json("cancel_reference", event_id, [
        #("referenceEventId", json.string(reference)),
      ])
    finance_tape.ReferenceOccursLater(event_id, reference) ->
      issue_json("reference_occurs_later", event_id, [
        #("referenceEventId", json.string(reference)),
      ])
  }
}

fn issue_json(
  kind: String,
  event_id: String,
  rest: List(#(String, Json)),
) -> Json {
  json.object([
    #("kind", json.string(kind)),
    #("eventId", json.string(event_id)),
    ..rest
  ])
}

fn clock_delta_json(value: finance_tape.ClockDelta) -> Json {
  let finance_tape.ClockDelta(
    event_id,
    exchange_provider,
    provider_retrieval,
    exchange_retrieval,
  ) = value
  json.object([
    #("eventId", json.string(event_id)),
    #(
      "exchangeToProviderMilliseconds",
      json.nullable(exchange_provider, json.int),
    ),
    #(
      "providerToRetrievalMilliseconds",
      json.nullable(provider_retrieval, json.int),
    ),
    #(
      "exchangeToRetrievalMilliseconds",
      json.nullable(exchange_retrieval, json.int),
    ),
    #("latencyClaimed", json.bool(False)),
  ])
}

fn condition_count_json(value: finance_tape.ConditionCount) -> Json {
  let finance_tape.ConditionCount(code, occurrences) = value
  json.object([
    #("code", json.string(code)),
    #("occurrences", json.int(occurrences)),
  ])
}
