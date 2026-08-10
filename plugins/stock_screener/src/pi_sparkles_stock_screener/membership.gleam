import finance_calendar/date as calendar_date
import finance_core/time
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/fact
import finance_replay/manifest
import finance_replay/wire
import finance_track
import gleam/dict
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_stock_screener/membership_decode as decode

const maximum_manifest_bytes = 10_000_000

const maximum_membership_events_per_listing = 200

pub type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  ManifestDecodeFailure(reason: String)
  ManifestNotCanonical
  ManifestHashMismatch(expected: String, actual: String)
  TooManyMembershipEvents(listing_id: String, mic: String, count: Int)
}

type Partition {
  MemberPartition
  NotMemberPartition
  UnresolvedPartition
  AllPartition
}

type EventRelation {
  Active
  Inactive(reason: String)
  EventUnresolved(reason: String, alternatives: List(String))
}

type ListingRelation {
  Member
  NotMember
  ListingUnresolved(reason: String)
}

type EventOutcome {
  EventOutcome(value: manifest.Membership, relation: EventRelation)
}

type ListingOutcome {
  ListingOutcome(
    listing_id: String,
    mic: String,
    events: List(EventOutcome),
    relation: ListingRelation,
  )
}

type Prepared {
  Prepared(
    input: decode.Input,
    track: finance_track.Track,
    effective_date: time.Date,
    cutoff: time.Instant,
    universe: manifest.UniverseManifest,
    universe_handle: Sha256,
    partition: Partition,
    listings: List(ListingOutcome),
  )
}

pub fn run(input: decode.Input) -> Result(Response, DomainError) {
  use prepared <- result.try(prepare(input))
  let filtered = filter_partition(prepared.listings, prepared.partition)
  let decode.PageInput(_, offset, limit) = input.page
  use _ <- result.try(integer_range(
    "page.offset",
    offset,
    0,
    list.length(filtered),
  ))
  let page = filtered |> list.drop(offset) |> list.take(limit)
  let next_offset = case offset + list.length(page) < list.length(filtered) {
    True -> Some(offset + list.length(page))
    False -> None
  }
  let counts = relation_counts(prepared.listings)
  let query_json = canonical_query_json(prepared)
  let assert Ok(query_handle) = query_json |> json.to_string |> hash.text
  let summary =
    finance_track.name(prepared.track)
    <> " point-in-time universe | "
    <> date_text(prepared.effective_date)
    <> " | "
    <> int.to_string(counts.member)
    <> " member, "
    <> int.to_string(counts.not_member)
    <> " not-member, "
    <> int.to_string(counts.unresolved)
    <> " unresolved | caller-selected knowledge cutoff"
  Ok(Response(
    summary,
    json.object([
      #("schema", json.string("pi-sparkles/stock-universe-projection")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("project_universe")),
      #("manifest", manifest_summary_json(prepared.universe)),
      #("universeManifestHandle", wire.sha_json(prepared.universe_handle)),
      #("projectionHandle", wire.sha_json(query_handle)),
      #("query", query_json),
      #("relationCounts", relation_counts_json(counts)),
      #(
        "page",
        json.object([
          #("partition", json.string(partition_name(prepared.partition))),
          #("offset", json.int(offset)),
          #("limit", json.int(limit)),
          #("matchingCount", json.int(list.length(filtered))),
          #("returnedCount", json.int(list.length(page))),
          #("nextOffset", json.nullable(next_offset, json.int)),
        ]),
      ),
      #("rows", json.array(page, listing_json)),
      #(
        "availableOperations",
        json.array(["project_universe", "screen"], json.string),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
      #("limitations", json.array(limitations(), json.string)),
    ]),
  ))
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) -> field <> " " <> reason
    ManifestDecodeFailure(reason) ->
      "universe.manifestJson failed the canonical finance_replay contract: "
      <> reason
    ManifestNotCanonical ->
      "universe.manifestJson must be the exact canonical finance_replay envelope"
    ManifestHashMismatch(expected, actual) ->
      "universe.manifestHash "
      <> expected
      <> " does not equal the canonical manifest handle "
      <> actual
    TooManyMembershipEvents(listing_id, mic, count) ->
      "exact listing "
      <> listing_id
      <> " / "
      <> mic
      <> " has "
      <> int.to_string(count)
      <> " membership events; the first projection slice permits at most "
      <> int.to_string(maximum_membership_events_per_listing)
      <> " per exact listing"
  }
}

fn prepare(input: decode.Input) -> Result(Prepared, DomainError) {
  let decode.Input(
    track_name,
    effective_date_text,
    cutoff_unix_ms,
    universe_input,
    page,
  ) = input
  use track <- result.try(parse_track(track_name))
  use effective_date <- result.try(date("effectiveDate", effective_date_text))
  use cutoff <- result.try(instant(
    "knowledgeCutoffUnixMilliseconds",
    cutoff_unix_ms,
  ))
  use partition <- result.try(parse_partition(page.partition))
  use _ <- result.try(integer_range("page.offset", page.offset, 0, 10_000))
  use _ <- result.try(integer_range("page.limit", page.limit, 1, 200))
  use universe <- result.try(prepare_manifest(universe_input))
  use _ <- result.try(exact_track(track, manifest.universe_track(universe.0)))
  use _ <- result.try(date_inside_coverage(
    effective_date,
    manifest.universe_coverage(universe.0),
  ))
  let event_outcomes =
    universe.0
    |> manifest.universe_memberships
    |> list.map(fn(value) { evaluate_event(value, effective_date, cutoff) })
  use listings <- result.try(group_listings(event_outcomes))
  Ok(Prepared(
    input,
    track,
    effective_date,
    cutoff,
    universe.0,
    universe.1,
    partition,
    listings,
  ))
}

fn prepare_manifest(
  value: decode.ManifestInput,
) -> Result(#(manifest.UniverseManifest, Sha256), DomainError) {
  use _ <- result.try(integer_range(
    "universe.manifestJson bytes",
    string.byte_size(value.manifest_json),
    1,
    maximum_manifest_bytes,
  ))
  use expected <- result.try(sha("universe.manifestHash", value.manifest_hash))
  use decoded <- result.try(
    manifest.decode_universe(value.manifest_json)
    |> result.map_error(fn(error) {
      ManifestDecodeFailure(string.inspect(error))
    }),
  )
  use _ <- result.try(
    case manifest.encode_universe(decoded) == value.manifest_json {
      True -> Ok(Nil)
      False -> Error(ManifestNotCanonical)
    },
  )
  let actual = manifest.universe_digest(decoded)
  use _ <- result.try(case expected == actual {
    True -> Ok(Nil)
    False ->
      Error(ManifestHashMismatch(
        identity.sha256_value(expected),
        identity.sha256_value(actual),
      ))
  })
  Ok(#(decoded, actual))
}

fn evaluate_event(
  value: manifest.Membership,
  effective_date: time.Date,
  cutoff: time.Instant,
) -> EventOutcome {
  let relation = case
    calendar_date.compare(value.membership_effective, effective_date)
  {
    Gt -> Inactive("membership_not_yet_effective")
    Lt | Eq ->
      case knowledge_relation(value.knowledge_time, cutoff) {
        Ok(Nil) -> effective_relation(value, effective_date)
        Error(relation) -> relation
      }
  }
  EventOutcome(value, relation)
}

fn knowledge_relation(
  value: fact.Fact(time.Instant),
  cutoff: time.Instant,
) -> Result(Nil, EventRelation) {
  case value {
    fact.Known(known_at) ->
      case time.unix_milliseconds(known_at) <= time.unix_milliseconds(cutoff) {
        True -> Ok(Nil)
        False -> Error(EventUnresolved("membership_known_after_cutoff", []))
      }
    fact.Unknown(reason) ->
      Error(EventUnresolved("membership_knowledge_time_unknown:" <> reason, []))
    fact.NotObtained(reason) ->
      Error(
        EventUnresolved("membership_knowledge_time_not_obtained:" <> reason, []),
      )
    fact.NotApplicable(reason) ->
      Error(
        EventUnresolved(
          "membership_knowledge_time_not_applicable:" <> reason,
          [],
        ),
      )
    fact.DecodeFailure(raw, reason) ->
      Error(
        EventUnresolved("membership_knowledge_time_decode_failure:" <> reason, [
          raw,
        ]),
      )
    fact.Conflicting(alternatives, reason) ->
      Error(EventUnresolved(
        "membership_knowledge_time_conflicting:" <> reason,
        list.map(alternatives, fn(value) {
          value |> time.unix_milliseconds |> int.to_string
        }),
      ))
  }
}

fn effective_relation(
  value: manifest.Membership,
  effective_date: time.Date,
) -> EventRelation {
  let manifest.OpenInterval(listing_start, listing_end) = value.listing_interval
  case date_in_open_interval(effective_date, listing_start, listing_end) {
    False -> Inactive("listing_interval_excludes_effective_date")
    True ->
      case value.state {
        manifest.MembershipUnknown(reason) ->
          EventUnresolved("membership_unknown:" <> reason, [])
        manifest.MembershipConflicting(alternatives, reason) ->
          EventUnresolved("membership_conflicting:" <> reason, alternatives)
        manifest.MembershipKnown ->
          membership_end_relation(value.membership_end, effective_date)
      }
  }
}

fn membership_end_relation(
  value: fact.Fact(time.Date),
  effective_date: time.Date,
) -> EventRelation {
  case value {
    fact.Known(end) ->
      case calendar_date.compare(effective_date, end) {
        Gt -> Inactive("membership_ended_before_effective_date")
        Lt | Eq -> Active
      }
    fact.NotApplicable(_) -> Active
    fact.Unknown(reason) ->
      EventUnresolved("membership_end_unknown:" <> reason, [])
    fact.NotObtained(reason) ->
      EventUnresolved("membership_end_not_obtained:" <> reason, [])
    fact.DecodeFailure(raw, reason) ->
      EventUnresolved("membership_end_decode_failure:" <> reason, [raw])
    fact.Conflicting(alternatives, reason) ->
      EventUnresolved(
        "membership_end_conflicting:" <> reason,
        list.map(alternatives, date_text),
      )
  }
}

fn group_listings(
  events: List(EventOutcome),
) -> Result(List(ListingOutcome), DomainError) {
  let #(keys, groups) =
    list.fold(events, #([], dict.new()), fn(acc, outcome) {
      let #(keys, groups) = acc
      let key = event_key(outcome)
      case dict.get(groups, key) {
        Ok(existing) -> #(keys, dict.insert(groups, key, [outcome, ..existing]))
        Error(_) -> #([key, ..keys], dict.insert(groups, key, [outcome]))
      }
    })
  keys
  |> list.reverse
  |> list.try_map(fn(key) {
    let assert Ok(reversed_events) = dict.get(groups, key)
    let grouped_events = list.reverse(reversed_events)
    let assert [EventOutcome(first, _), ..] = grouped_events
    let count = list.length(grouped_events)
    use _ <- result.try(case count <= maximum_membership_events_per_listing {
      True -> Ok(Nil)
      False ->
        Error(TooManyMembershipEvents(first.listing_id, first.mic, count))
    })
    Ok(ListingOutcome(
      first.listing_id,
      first.mic,
      grouped_events,
      listing_relation(grouped_events),
    ))
  })
}

fn event_key(value: EventOutcome) -> String {
  let EventOutcome(membership, _) = value
  membership.listing_id <> "\n" <> membership.mic
}

fn listing_relation(events: List(EventOutcome)) -> ListingRelation {
  let active =
    list.filter(events, fn(value) {
      let EventOutcome(_, relation) = value
      relation == Active
    })
  let unresolved =
    list.filter(events, fn(value) {
      let EventOutcome(_, relation) = value
      case relation {
        EventUnresolved(..) -> True
        _ -> False
      }
    })
  case list.length(active), list.length(unresolved) {
    1, 0 -> Member
    0, 0 -> NotMember
    active_count, _ if active_count > 1 ->
      ListingUnresolved("multiple_active_membership_events_for_exact_listing")
    _, _ -> ListingUnresolved("membership_event_facts_are_unresolved")
  }
}

fn filter_partition(
  values: List(ListingOutcome),
  partition: Partition,
) -> List(ListingOutcome) {
  list.filter(values, fn(value) {
    let ListingOutcome(_, _, _, relation) = value
    case partition, relation {
      AllPartition, _ -> True
      MemberPartition, Member -> True
      NotMemberPartition, NotMember -> True
      UnresolvedPartition, ListingUnresolved(_) -> True
      _, _ -> False
    }
  })
}

type RelationCounts {
  RelationCounts(member: Int, not_member: Int, unresolved: Int)
}

fn relation_counts(values: List(ListingOutcome)) -> RelationCounts {
  list.fold(values, RelationCounts(0, 0, 0), fn(counts, value) {
    let ListingOutcome(_, _, _, relation) = value
    case relation {
      Member -> RelationCounts(..counts, member: counts.member + 1)
      NotMember -> RelationCounts(..counts, not_member: counts.not_member + 1)
      ListingUnresolved(_) ->
        RelationCounts(..counts, unresolved: counts.unresolved + 1)
    }
  })
}

fn listing_json(value: ListingOutcome) -> Json {
  let ListingOutcome(listing_id, mic, events, relation) = value
  json.object([
    #("listingId", json.string(listing_id)),
    #("mic", json.string(mic)),
    #("relation", json.string(listing_relation_name(relation))),
    #(
      "relationReason",
      json.nullable(listing_relation_reason(relation), json.string),
    ),
    #("membershipEventCount", json.int(list.length(events))),
    #(
      "eventRelationCounts",
      event_relation_counts_json(event_relation_counts(events)),
    ),
    #("events", json.array(events, event_json)),
  ])
}

type EventRelationCounts {
  EventRelationCounts(active: Int, inactive: Int, unresolved: Int)
}

fn event_relation_counts(values: List(EventOutcome)) -> EventRelationCounts {
  list.fold(values, EventRelationCounts(0, 0, 0), fn(counts, value) {
    let EventOutcome(_, relation) = value
    case relation {
      Active -> EventRelationCounts(..counts, active: counts.active + 1)
      Inactive(_) ->
        EventRelationCounts(..counts, inactive: counts.inactive + 1)
      EventUnresolved(_, _) ->
        EventRelationCounts(..counts, unresolved: counts.unresolved + 1)
    }
  })
}

fn event_json(value: EventOutcome) -> Json {
  let EventOutcome(membership, relation) = value
  json.object([
    #("relation", json.string(event_relation_name(relation))),
    #("reason", json.nullable(event_relation_reason(relation), json.string)),
    #(
      "alternatives",
      json.array(event_relation_alternatives(relation), json.string),
    ),
    #("listingId", json.string(membership.listing_id)),
    #("mic", json.string(membership.mic)),
    #("track", wire.track_json(membership.track)),
    #("symbol", fact.to_json(membership.symbol, json.string)),
    #(
      "symbolInterval",
      fact.to_json(membership.symbol_interval, open_interval_json),
    ),
    #("listingInterval", open_interval_json(membership.listing_interval)),
    #("securityClass", fact.to_json(membership.security_class, json.string)),
    #(
      "statusInterval",
      fact.to_json(membership.status_interval, open_interval_json),
    ),
    #(
      "membershipEffective",
      json.string(date_text(membership.membership_effective)),
    ),
    #(
      "membershipEnd",
      fact.to_json(membership.membership_end, fn(value) {
        json.string(date_text(value))
      }),
    ),
    #(
      "publicationTime",
      fact.to_json(membership.publication_time, fn(value) {
        value |> time.unix_milliseconds |> json.int
      }),
    ),
    #(
      "knowledgeTime",
      fact.to_json(membership.knowledge_time, fn(value) {
        value |> time.unix_milliseconds |> json.int
      }),
    ),
    #(
      "retrievalTimeUnixMilliseconds",
      membership.retrieval_time |> time.unix_milliseconds |> json.int,
    ),
    #("sourceReceipt", wire.sha_json(membership.source_receipt)),
    #(
      "correctionLineage",
      json.array(membership.correction_lineage, wire.sha_json),
    ),
    #("sourceState", membership_state_json(membership.state)),
  ])
}

fn manifest_summary_json(value: manifest.UniverseManifest) -> Json {
  let manifest.Interval(start, end) = manifest.universe_coverage(value)
  json.object([
    #("manifestId", json.string(manifest.universe_manifest_id(value))),
    #("version", json.string(manifest.universe_version(value))),
    #("track", wire.track_json(manifest.universe_track(value))),
    #(
      "definitionKind",
      definition_kind_json(manifest.universe_definition_kind(value)),
    ),
    #(
      "asOfTimeUnixMilliseconds",
      value
        |> manifest.universe_as_of_time
        |> time.unix_milliseconds
        |> json.int,
    ),
    #(
      "coverage",
      json.object([
        #("start", json.string(date_text(start))),
        #("end", json.string(date_text(end))),
      ]),
    ),
    #("sourceReceipt", wire.sha_json(manifest.universe_source_receipt(value))),
    #("provenance", provenance_json(manifest.universe_provenance(value))),
    #(
      "limitations",
      json.array(manifest.universe_limitations(value), json.string),
    ),
    #(
      "membershipEventCount",
      value |> manifest.universe_memberships |> list.length |> json.int,
    ),
  ])
}

fn canonical_query_json(value: Prepared) -> Json {
  json.object([
    #("schema", json.string("pi-sparkles/stock-universe-query")),
    #("schemaVersion", json.int(1)),
    #("track", wire.track_json(value.track)),
    #("effectiveDate", json.string(date_text(value.effective_date))),
    #(
      "knowledgeCutoffUnixMilliseconds",
      value.cutoff |> time.unix_milliseconds |> json.int,
    ),
    #("membershipEndPolicy", json.string("inclusive_end_v1")),
    #("universeManifestHandle", wire.sha_json(value.universe_handle)),
  ])
}

fn relation_counts_json(value: RelationCounts) -> Json {
  json.object([
    #("member", json.int(value.member)),
    #("notMember", json.int(value.not_member)),
    #("unresolved", json.int(value.unresolved)),
    #("total", json.int(value.member + value.not_member + value.unresolved)),
  ])
}

fn event_relation_counts_json(value: EventRelationCounts) -> Json {
  json.object([
    #("active", json.int(value.active)),
    #("inactive", json.int(value.inactive)),
    #("unresolved", json.int(value.unresolved)),
  ])
}

fn open_interval_json(value: manifest.OpenInterval) -> Json {
  let manifest.OpenInterval(start, end) = value
  json.object([
    #("start", json.string(date_text(start))),
    #("end", json.nullable(end, fn(value) { json.string(date_text(value)) })),
  ])
}

fn membership_state_json(value: manifest.MembershipState) -> Json {
  case value {
    manifest.MembershipKnown -> json.object([#("state", json.string("known"))])
    manifest.MembershipUnknown(reason) ->
      json.object([
        #("state", json.string("unknown")),
        #("reason", json.string(reason)),
      ])
    manifest.MembershipConflicting(alternatives, reason) ->
      json.object([
        #("state", json.string("conflicting")),
        #("alternatives", json.array(alternatives, json.string)),
        #("reason", json.string(reason)),
      ])
  }
}

fn definition_kind_json(value: manifest.UniverseDefinitionKind) -> Json {
  case value {
    manifest.ExactEnumerated ->
      json.object([#("kind", json.string("exact_enumerated"))])
    manifest.RuleProjection(receipt) ->
      json.object([
        #("kind", json.string("rule_projection")),
        #("receipt", wire.sha_json(receipt)),
      ])
    manifest.ImportedDeclaration(source) ->
      json.object([
        #("kind", json.string("imported_declaration")),
        #("source", json.string(source)),
      ])
  }
}

fn provenance_json(value: manifest.Provenance) -> Json {
  json.string(case value {
    manifest.ProviderObserved -> "provider_observed"
    manifest.AuthorityObserved -> "authority_observed"
    manifest.CallerDeclared -> "caller_declared"
    manifest.Imported -> "imported"
  })
}

fn parse_track(value: String) -> Result(finance_track.Track, DomainError) {
  finance_track.from_name(value)
  |> result.map_error(fn(_) { InvalidField("track", "expected cn, hk, or us") })
}

fn parse_partition(value: String) -> Result(Partition, DomainError) {
  case value {
    "member" -> Ok(MemberPartition)
    "not_member" -> Ok(NotMemberPartition)
    "unresolved" -> Ok(UnresolvedPartition)
    "all" -> Ok(AllPartition)
    _ ->
      Error(InvalidField(
        "page.partition",
        "expected member, not_member, unresolved, or all",
      ))
  }
}

fn partition_name(value: Partition) -> String {
  case value {
    MemberPartition -> "member"
    NotMemberPartition -> "not_member"
    UnresolvedPartition -> "unresolved"
    AllPartition -> "all"
  }
}

fn listing_relation_name(value: ListingRelation) -> String {
  case value {
    Member -> "member"
    NotMember -> "not_member"
    ListingUnresolved(_) -> "unresolved"
  }
}

fn listing_relation_reason(value: ListingRelation) -> Option(String) {
  case value {
    ListingUnresolved(reason) -> Some(reason)
    _ -> None
  }
}

fn event_relation_name(value: EventRelation) -> String {
  case value {
    Active -> "active"
    Inactive(_) -> "inactive"
    EventUnresolved(_, _) -> "unresolved"
  }
}

fn event_relation_reason(value: EventRelation) -> Option(String) {
  case value {
    Inactive(reason) | EventUnresolved(reason, _) -> Some(reason)
    Active -> None
  }
}

fn event_relation_alternatives(value: EventRelation) -> List(String) {
  case value {
    EventUnresolved(_, alternatives) -> alternatives
    _ -> []
  }
}

fn exact_track(
  expected: finance_track.Track,
  actual: finance_track.Track,
) -> Result(Nil, DomainError) {
  case expected == actual {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "universe",
        "manifest track "
          <> finance_track.name(actual)
          <> " does not equal request track "
          <> finance_track.name(expected),
      ))
  }
}

fn date_inside_coverage(
  value: time.Date,
  coverage: manifest.Interval,
) -> Result(Nil, DomainError) {
  let manifest.Interval(start, end) = coverage
  case calendar_date.compare(value, start), calendar_date.compare(value, end) {
    Lt, _ | _, Gt ->
      Error(InvalidField(
        "effectiveDate",
        "must be inside the exact universe manifest coverage",
      ))
    _, _ -> Ok(Nil)
  }
}

fn date_in_open_interval(
  value: time.Date,
  start: time.Date,
  end: Option(time.Date),
) -> Bool {
  case calendar_date.compare(value, start), end {
    Lt, _ -> False
    _, Some(end) -> calendar_date.compare(value, end) != Gt
    _, None -> True
  }
}

fn date(field: String, value: String) -> Result(time.Date, DomainError) {
  case string.split(value, "-") {
    [year, month, day] -> {
      use year <- result.try(parsed_int(field, year))
      use month <- result.try(parsed_int(field, month))
      use day <- result.try(parsed_int(field, day))
      use parsed <- result.try(
        time.date(year, month, day)
        |> result.map_error(fn(_) {
          InvalidField(field, "expected a canonical YYYY-MM-DD date")
        }),
      )
      case date_text(parsed) == value {
        True -> Ok(parsed)
        False ->
          Error(InvalidField(field, "expected a canonical YYYY-MM-DD date"))
      }
    }
    _ -> Error(InvalidField(field, "expected a canonical YYYY-MM-DD date"))
  }
}

fn parsed_int(field: String, value: String) -> Result(Int, DomainError) {
  int.parse(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "expected a canonical YYYY-MM-DD date")
  })
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

fn instant(field: String, value: Int) -> Result(time.Instant, DomainError) {
  time.instant(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "instant is outside the supported range")
  })
}

fn sha(field: String, value: String) -> Result(Sha256, DomainError) {
  identity.sha256(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "expected exactly 64 hexadecimal SHA-256 characters")
  })
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
        "expected an integer from "
          <> int.to_string(minimum)
          <> " through "
          <> int.to_string(maximum),
      ))
  }
}

fn limitations() -> List(String) {
  [
    "projection_uses_only_the_caller_supplied_canonical_universe_manifest_and_cutoff",
    "member_is_an_exact_interval_and_known_at_cutoff_relation_not_eligibility_suitability_or_recommendation",
    "membership_end_is_inclusive_under_the_explicit_first_slice_policy",
    "unknown_conflicting_late_or_overlapping_membership_evidence_remains_unresolved",
    "matching_hashes_prove_content_coherence_not_provider_origin_authority_correctness_completeness_or_licence_permission",
    "no_provider_fetch_current_constituent_substitution_cross_track_merge_rank_score_or_next_action",
  ]
}
