import finance_calendar/date as calendar_date
import finance_core/decimal.{type Decimal}
import finance_core/time
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/fact
import finance_replay/manifest
import finance_replay/wire
import finance_track
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_stock_screener/decode

const maximum_manifest_bytes = 10_000_000

const maximum_predicates = 20

const maximum_rows = 2000

const maximum_values_per_row = 100

const maximum_receipt_roots = 10_000

const maximum_page_size = 200

pub type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  ManifestDecodeFailure(kind: String, reason: String)
  ManifestNotCanonical(kind: String)
  ManifestHashMismatch(kind: String, expected: String, actual: String)
}

type Operator {
  GreaterThan
  GreaterThanOrEqual
  LessThan
  LessThanOrEqual
  Equal
  NotEqual
}

type Partition {
  MatchedPartition
  NotMatchedPartition
  UnresolvedPartition
  AllPartition
}

type Relation {
  Matched
  NotMatched
  Unresolved
}

type PreparedPredicate {
  PreparedPredicate(
    input: decode.PredicateInput,
    threshold: Decimal,
    op: Operator,
  )
}

type PreparedRow {
  PreparedRow(input: decode.RowInput, date: time.Date)
}

type Prepared {
  Prepared(
    input: decode.ScreenInput,
    track: finance_track.Track,
    start: time.Date,
    end: time.Date,
    cutoff: time.Instant,
    universe: manifest.UniverseManifest,
    dataset: manifest.DatasetManifest,
    universe_handle: Sha256,
    dataset_handle: Sha256,
    technical_roots: List(Sha256),
    predicates: List(PreparedPredicate),
    rows: List(PreparedRow),
    partition: Partition,
  )
}

type BindingFact {
  ExactBinding(reference: Sha256)
  UnavailableBinding(reason: String)
  ConflictingBinding(reason: String, alternatives: List(String))
}

type AlternativeComparison {
  AlternativeComparison(
    raw: String,
    normalized: Option(String),
    observed: Option(Bool),
  )
}

type PredicateState {
  ObservedTrue(raw: String, normalized: String, comparison: Order)
  ObservedFalse(raw: String, normalized: String, comparison: Order)
  PredicateUnavailable(reason: String)
  PredicateConflicting(
    reason: String,
    alternatives: List(AlternativeComparison),
  )
}

type PredicateFact {
  PredicateFact(predicate: PreparedPredicate, state: PredicateState)
}

type RowOutcome {
  RowOutcome(
    row: PreparedRow,
    universe_binding: BindingFact,
    dataset_binding: BindingFact,
    predicate_facts: List(PredicateFact),
    relation: Relation,
  )
}

type RelationCounts {
  RelationCounts(matched: Int, not_matched: Int, unresolved: Int)
}

type Page(value) {
  Page(
    values: List(value),
    total: Int,
    returned: Int,
    omitted: Int,
    next_offset: Option(Int),
  )
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid explicit stock-screen field " <> field <> ": " <> reason
    ManifestDecodeFailure(kind, reason) ->
      "The supplied "
      <> kind
      <> " manifest failed the finance_replay contract: "
      <> reason
    ManifestNotCanonical(kind) ->
      "The supplied "
      <> kind
      <> " manifestJson is not the exact canonical finance_replay envelope"
    ManifestHashMismatch(kind, expected, actual) ->
      "The supplied "
      <> kind
      <> " manifestHash "
      <> expected
      <> " does not match the canonical handle "
      <> actual
  }
}

pub fn run(value: decode.ScreenInput) -> Result(Response, DomainError) {
  use prepared <- result.try(prepare(value))
  let outcomes =
    list.map(prepared.rows, fn(row) { evaluate_row(prepared, row) })
  let request_json = canonical_request_json(prepared)
  let assert Ok(request_handle) = request_json |> json.to_string |> hash.text
  let result_projection =
    json.object([
      #("schema", json.string("pi-sparkles/stock-screen-semantic-result")),
      #("schemaVersion", json.int(1)),
      #("requestReceiptHandle", wire.sha_json(request_handle)),
      #("rows", json.array(outcomes, row_outcome_json)),
    ])
  let assert Ok(semantic_handle) =
    result_projection |> json.to_string |> hash.text
  let selected =
    list.filter(outcomes, fn(outcome) {
      partition_includes(prepared.partition, outcome.relation)
    })
  let decode.PageInput(_, offset, limit) = value.page
  use page <- result.try(paginate(selected, offset, limit))
  let counts = relation_counts(outcomes)
  let partition_name = partition_name(prepared.partition)
  Ok(Response(
    finance_track.name(prepared.track)
      <> " | exact stock screen | "
      <> int.to_string(list.length(outcomes))
      <> " rows | matched "
      <> int.to_string(counts.matched)
      <> ", not matched "
      <> int.to_string(counts.not_matched)
      <> ", unresolved "
      <> int.to_string(counts.unresolved)
      <> " | paged "
      <> partition_name
      <> " facts; interpretation belongs to the LLM",
    response_json(
      prepared,
      request_handle,
      semantic_handle,
      counts,
      partition_name,
      offset,
      limit,
      page,
    ),
  ))
}

fn prepare(value: decode.ScreenInput) -> Result(Prepared, DomainError) {
  let decode.ScreenInput(context, predicate_inputs, row_inputs, relation, page) =
    value
  use _ <- result.try(trimmed_text(
    "context.instructionRef",
    context.instruction_ref,
    64,
  ))
  use _ <- result.try(sha("context.instructionRef", context.instruction_ref))
  use track <- result.try(parse_track(context.track))
  use start <- result.try(date("context.dateStart", context.date_start))
  use end <- result.try(date("context.dateEnd", context.date_end))
  use _ <- result.try(case calendar_date.compare(start, end) {
    Gt -> Error(InvalidField("context.dateEnd", "must not precede dateStart"))
    _ -> Ok(Nil)
  })
  use cutoff <- result.try(instant(
    "context.sourceCutoffUnixMilliseconds",
    context.source_cutoff_unix_ms,
  ))
  use universe <- result.try(prepare_universe(context.universe))
  use dataset <- result.try(prepare_dataset(context.dataset))
  use _ <- result.try(exact_track(
    "context.universe",
    track,
    manifest.universe_track(universe.0),
  ))
  use _ <- result.try(exact_track(
    "context.dataset",
    track,
    manifest.dataset_track(dataset.0),
  ))
  use _ <- result.try(range_inside(
    "context.date range versus dataset coverage",
    start,
    end,
    manifest.dataset_coverage(dataset.0),
  ))
  use _ <- result.try(list_count(
    "context.technicalReceiptRoots",
    context.technical_receipt_roots,
    0,
    maximum_receipt_roots,
  ))
  use technical_roots <- result.try(
    list.try_map(context.technical_receipt_roots, fn(value) {
      sha("context.technicalReceiptRoots[]", value)
    }),
  )
  use _ <- result.try(
    unique_hashes("context.technicalReceiptRoots", technical_roots, []),
  )
  use _ <- result.try(list_count(
    "predicates",
    predicate_inputs,
    1,
    maximum_predicates,
  ))
  use predicates <- result.try(prepare_predicates(predicate_inputs, []))
  use _ <- result.try(list_count("rows", row_inputs, 1, maximum_rows))
  use rows <- result.try(prepare_rows(row_inputs, track, start, end, [], []))
  use _ <- result.try(exact_policy(
    "relation.matchPolicy",
    relation.match_policy,
    "all_predicates_observed_true_v1",
  ))
  use _ <- result.try(exact_policy(
    "relation.unresolvedPolicy",
    relation.unresolved_policy,
    "preserve_unresolved_separately_v1",
  ))
  use partition <- result.try(parse_partition(page.partition))
  use _ <- result.try(integer_range("page.offset", page.offset, 0, maximum_rows))
  use _ <- result.try(integer_range(
    "page.limit",
    page.limit,
    1,
    maximum_page_size,
  ))
  Ok(Prepared(
    value,
    track,
    start,
    end,
    cutoff,
    universe.0,
    dataset.0,
    universe.1,
    dataset.1,
    technical_roots,
    predicates,
    rows,
    partition,
  ))
}

fn prepare_universe(
  value: decode.ManifestInput,
) -> Result(#(manifest.UniverseManifest, Sha256), DomainError) {
  use expected <- result.try(prepare_manifest_bytes_and_hash(
    "universe",
    value.manifest_json,
    value.manifest_hash,
  ))
  use decoded <- result.try(
    manifest.decode_universe(value.manifest_json)
    |> result.map_error(fn(error) {
      ManifestDecodeFailure("universe", string.inspect(error))
    }),
  )
  use _ <- result.try(
    case manifest.encode_universe(decoded) == value.manifest_json {
      True -> Ok(Nil)
      False -> Error(ManifestNotCanonical("universe"))
    },
  )
  let actual = manifest.universe_digest(decoded)
  use _ <- result.try(match_manifest_hash("universe", expected, actual))
  Ok(#(decoded, actual))
}

fn prepare_dataset(
  value: decode.ManifestInput,
) -> Result(#(manifest.DatasetManifest, Sha256), DomainError) {
  use expected <- result.try(prepare_manifest_bytes_and_hash(
    "dataset",
    value.manifest_json,
    value.manifest_hash,
  ))
  use decoded <- result.try(
    manifest.decode_dataset(value.manifest_json)
    |> result.map_error(fn(error) {
      ManifestDecodeFailure("dataset", string.inspect(error))
    }),
  )
  use _ <- result.try(
    case manifest.encode_dataset(decoded) == value.manifest_json {
      True -> Ok(Nil)
      False -> Error(ManifestNotCanonical("dataset"))
    },
  )
  let actual = manifest.dataset_digest(decoded)
  use _ <- result.try(match_manifest_hash("dataset", expected, actual))
  Ok(#(decoded, actual))
}

fn prepare_manifest_bytes_and_hash(
  kind: String,
  manifest_json: String,
  manifest_hash: String,
) -> Result(Sha256, DomainError) {
  use _ <- result.try(integer_range(
    "context." <> kind <> ".manifestJson bytes",
    string.byte_size(manifest_json),
    1,
    maximum_manifest_bytes,
  ))
  sha("context." <> kind <> ".manifestHash", manifest_hash)
}

fn match_manifest_hash(
  kind: String,
  expected: Sha256,
  actual: Sha256,
) -> Result(Nil, DomainError) {
  case expected == actual {
    True -> Ok(Nil)
    False ->
      Error(ManifestHashMismatch(
        kind,
        identity.sha256_value(expected),
        identity.sha256_value(actual),
      ))
  }
}

fn prepare_predicates(
  values: List(decode.PredicateInput),
  seen: List(String),
) -> Result(List(PreparedPredicate), DomainError) {
  case values {
    [] -> Ok([])
    [value, ..rest] -> {
      use _ <- result.try(trimmed_text("predicates[].id", value.id, 200))
      use _ <- result.try(case list.contains(seen, value.id) {
        True -> Error(InvalidField("predicates[].id", "must be unique"))
        False -> Ok(Nil)
      })
      use _ <- result.try(trimmed_text("predicates[].field", value.field, 200))
      use _ <- result.try(trimmed_text("predicates[].unit", value.unit, 200))
      use op <- result.try(parse_operator(value.operator))
      use threshold <- result.try(
        decimal.parse(value.threshold_raw)
        |> result.map_error(fn(_) {
          InvalidField(
            "predicates[].rightOperand.raw",
            "expected an exact decimal lexeme",
          )
        }),
      )
      use tail <- result.try(prepare_predicates(rest, [value.id, ..seen]))
      Ok([PreparedPredicate(value, threshold, op), ..tail])
    }
  }
}

fn prepare_rows(
  values: List(decode.RowInput),
  track: finance_track.Track,
  start: time.Date,
  end: time.Date,
  seen: List(String),
  accumulated: List(PreparedRow),
) -> Result(List(PreparedRow), DomainError) {
  case values {
    [] -> Ok(list.reverse(accumulated))
    [value, ..rest] -> {
      use _ <- result.try(trimmed_text(
        "rows[].listingId",
        value.listing_id,
        2000,
      ))
      use _ <- result.try(trimmed_text("rows[].mic", value.mic, 50))
      use _ <- result.try(trimmed_text(
        "rows[].observationId",
        value.observation_id,
        2000,
      ))
      use row_date <- result.try(date(
        "rows[].observationDate",
        value.observation_date,
      ))
      use _ <- result.try(date_inside(
        "rows[].observationDate",
        row_date,
        start,
        end,
      ))
      let key =
        finance_track.name(track)
        <> "\n"
        <> value.listing_id
        <> "\n"
        <> value.mic
        <> "\n"
        <> value.observation_date
        <> "\n"
        <> value.observation_id
      use _ <- result.try(case list.contains(seen, key) {
        True -> Error(InvalidField("rows", "row keys must be unique"))
        False -> Ok(Nil)
      })
      use _ <- result.try(list_count(
        "rows[].values",
        value.values,
        0,
        maximum_values_per_row,
      ))
      use _ <- result.try(validate_values(value.values, []))
      prepare_rows(rest, track, start, end, [key, ..seen], [
        PreparedRow(value, row_date),
        ..accumulated
      ])
    }
  }
}

fn validate_values(
  values: List(decode.ValueInput),
  seen: List(String),
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(trimmed_text(
        "rows[].values[].field",
        value.field,
        200,
      ))
      use _ <- result.try(trimmed_text("rows[].values[].unit", value.unit, 200))
      use _ <- result.try(case list.contains(seen, value.field) {
        True ->
          Error(InvalidField(
            "rows[].values[].field",
            "must be unique within its row",
          ))
        False -> Ok(Nil)
      })
      use _ <- result.try(case value.source_kind {
        "dataset_observation" | "technical_receipt" -> Ok(Nil)
        _ ->
          Error(InvalidField(
            "rows[].values[].sourceKind",
            "expected dataset_observation or technical_receipt",
          ))
      })
      use _ <- result.try(instant(
        "rows[].values[].knownAtUnixMilliseconds",
        value.known_at_unix_ms,
      ))
      use _ <- result.try(list_count(
        "rows[].values[].evidenceRoots",
        value.evidence_roots,
        1,
        maximum_receipt_roots,
      ))
      use roots <- result.try(
        list.try_map(value.evidence_roots, fn(root) {
          sha("rows[].values[].evidenceRoots[]", root)
        }),
      )
      use _ <- result.try(
        unique_hashes("rows[].values[].evidenceRoots", roots, []),
      )
      use _ <- result.try(validate_fact(value.fact))
      validate_values(rest, [value.field, ..seen])
    }
  }
}

fn validate_fact(value: decode.FactInput) -> Result(Nil, DomainError) {
  case value.state, value.raw, value.reason, value.alternatives {
    "known", Some(raw), None, [] ->
      decimal.parse(raw)
      |> result.map(fn(_) { Nil })
      |> result.map_error(fn(_) {
        InvalidField(
          "rows[].values[].fact.raw",
          "known facts require an exact decimal lexeme",
        )
      })
    "unknown", None, Some(reason), []
    | "not_obtained", None, Some(reason), []
    | "not_applicable", None, Some(reason), []
    -> trimmed_text("rows[].values[].fact.reason", reason, 2000)
    "decode_failure", Some(raw), Some(reason), [] -> {
      use _ <- result.try(trimmed_text("rows[].values[].fact.raw", raw, 4000))
      trimmed_text("rows[].values[].fact.reason", reason, 2000)
    }
    "conflicting", None, Some(reason), alternatives if alternatives != [] -> {
      use _ <- result.try(trimmed_text(
        "rows[].values[].fact.reason",
        reason,
        2000,
      ))
      use _ <- result.try(list_count(
        "rows[].values[].fact.alternatives",
        alternatives,
        2,
        20,
      ))
      list.try_each(alternatives, fn(raw) {
        trimmed_text("rows[].values[].fact.alternatives[]", raw, 4000)
      })
    }
    _, _, _, _ ->
      Error(InvalidField(
        "rows[].values[].fact",
        "fields do not match the explicit fact state",
      ))
  }
}

fn evaluate_row(prepared: Prepared, row: PreparedRow) -> RowOutcome {
  let universe_binding =
    universe_binding(prepared.universe, row, prepared.cutoff)
  let dataset_binding = dataset_binding(prepared, row)
  let predicate_facts =
    list.map(prepared.predicates, fn(predicate) {
      PredicateFact(
        predicate,
        evaluate_predicate(prepared, row, dataset_binding, predicate),
      )
    })
  let relation = relation(universe_binding, dataset_binding, predicate_facts)
  RowOutcome(row, universe_binding, dataset_binding, predicate_facts, relation)
}

fn universe_binding(
  universe: manifest.UniverseManifest,
  row: PreparedRow,
  cutoff: time.Instant,
) -> BindingFact {
  let matches =
    universe
    |> manifest.universe_memberships
    |> list.filter(fn(value) {
      value.listing_id == row.input.listing_id && value.mic == row.input.mic
    })
  let bindings =
    list.map(matches, fn(value) { membership_binding(value, row.date, cutoff) })
  let active =
    list.filter_map(bindings, fn(value) {
      case value {
        ExactBinding(receipt) -> Ok(receipt)
        _ -> Error(Nil)
      }
    })
  let unresolved =
    list.filter(bindings, fn(value) {
      case value {
        ExactBinding(_) -> False
        UnavailableBinding(reason) -> !temporally_inactive(reason)
        ConflictingBinding(_, _) -> True
      }
    })
  case active, unresolved {
    [receipt], [] -> ExactBinding(receipt)
    [], [] -> UnavailableBinding("no_active_universe_membership_on_row_date")
    [], [UnavailableBinding(reason), ..] -> UnavailableBinding(reason)
    [], [ConflictingBinding(reason, alternatives), ..] ->
      ConflictingBinding(reason, alternatives)
    [receipt], _ ->
      ConflictingBinding(
        "active_universe_membership_overlaps_unresolved_membership_evidence",
        [identity.sha256_value(receipt)],
      )
    receipts, _ ->
      ConflictingBinding(
        "multiple_active_universe_memberships_for_exact_listing_and_mic",
        list.map(receipts, identity.sha256_value),
      )
  }
}

fn membership_binding(
  value: manifest.Membership,
  row_date: time.Date,
  cutoff: time.Instant,
) -> BindingFact {
  let manifest.OpenInterval(listing_start, listing_end) = value.listing_interval
  case date_in_open_interval(row_date, listing_start, listing_end) {
    False -> UnavailableBinding("listing_interval_excludes_row_date")
    True ->
      case calendar_date.compare(row_date, value.membership_effective) {
        Lt -> UnavailableBinding("membership_not_yet_effective_on_row_date")
        _ -> membership_knowledge_binding(value, row_date, cutoff)
      }
  }
}

fn membership_knowledge_binding(
  value: manifest.Membership,
  row_date: time.Date,
  cutoff: time.Instant,
) -> BindingFact {
  case value.knowledge_time {
    fact.Known(known_at) ->
      case time.unix_milliseconds(known_at) <= time.unix_milliseconds(cutoff) {
        True -> membership_state_binding(value, row_date)
        False -> UnavailableBinding("membership_known_after_source_cutoff")
      }
    fact.Unknown(reason) ->
      UnavailableBinding("membership_knowledge_time_unknown:" <> reason)
    fact.NotObtained(reason) ->
      UnavailableBinding("membership_knowledge_time_not_obtained:" <> reason)
    fact.NotApplicable(reason) ->
      UnavailableBinding("membership_knowledge_time_not_applicable:" <> reason)
    fact.DecodeFailure(_, reason) ->
      UnavailableBinding("membership_knowledge_time_decode_failure:" <> reason)
    fact.Conflicting(alternatives, reason) ->
      ConflictingBinding(
        "membership_knowledge_time_conflicting:" <> reason,
        list.map(alternatives, fn(value) {
          value |> time.unix_milliseconds |> int.to_string
        }),
      )
  }
}

fn temporally_inactive(reason: String) -> Bool {
  reason == "listing_interval_excludes_row_date"
  || reason == "membership_not_yet_effective_on_row_date"
  || reason == "membership_ended_before_row_date"
}

fn membership_state_binding(
  value: manifest.Membership,
  row_date: time.Date,
) -> BindingFact {
  case value.state {
    manifest.MembershipUnknown(reason) ->
      UnavailableBinding("membership_unknown:" <> reason)
    manifest.MembershipConflicting(alternatives, reason) ->
      ConflictingBinding("membership_conflicting:" <> reason, alternatives)
    manifest.MembershipKnown ->
      membership_end_binding(
        value.membership_end,
        row_date,
        value.source_receipt,
      )
  }
}

fn membership_end_binding(
  value: fact.Fact(time.Date),
  row_date: time.Date,
  source_receipt: Sha256,
) -> BindingFact {
  case value {
    fact.Known(end) ->
      case calendar_date.compare(row_date, end) {
        Gt -> UnavailableBinding("membership_ended_before_row_date")
        _ -> ExactBinding(source_receipt)
      }
    fact.NotApplicable(_) -> ExactBinding(source_receipt)
    fact.Unknown(reason) ->
      UnavailableBinding("membership_end_unknown:" <> reason)
    fact.NotObtained(reason) ->
      UnavailableBinding("membership_end_not_obtained:" <> reason)
    fact.DecodeFailure(_, reason) ->
      UnavailableBinding("membership_end_decode_failure:" <> reason)
    fact.Conflicting(alternatives, reason) ->
      ConflictingBinding(
        "membership_end_conflicting:" <> reason,
        list.map(alternatives, date_text),
      )
  }
}

fn dataset_binding(prepared: Prepared, row: PreparedRow) -> BindingFact {
  let matches =
    prepared.dataset
    |> manifest.dataset_observations
    |> list.filter(fn(value) {
      value.observation_id == row.input.observation_id
    })
  case matches {
    [] -> UnavailableBinding("exact_dataset_observation_id_not_found")
    [observation] ->
      case
        observation.listing_id == row.input.listing_id,
        observation.mic == row.input.mic,
        observation.track == prepared.track,
        observation.observation_date == row.date
      {
        True, True, True, True ->
          observation_cutoff_binding(
            observation.knowledge_time,
            prepared.cutoff,
            observation.content_hash,
          )
        _, _, _, _ ->
          UnavailableBinding("dataset_observation_identity_or_date_mismatch")
      }
    _ ->
      ConflictingBinding("duplicate_dataset_observation_id", [
        row.input.observation_id,
      ])
  }
}

fn observation_cutoff_binding(
  value: fact.Fact(time.Instant),
  cutoff: time.Instant,
  content_hash: Sha256,
) -> BindingFact {
  case value {
    fact.Known(known_at) ->
      case time.unix_milliseconds(known_at) <= time.unix_milliseconds(cutoff) {
        True -> ExactBinding(content_hash)
        False -> UnavailableBinding("dataset_observation_known_after_cutoff")
      }
    fact.Unknown(reason) ->
      UnavailableBinding("dataset_knowledge_time_unknown:" <> reason)
    fact.NotObtained(reason) ->
      UnavailableBinding("dataset_knowledge_time_not_obtained:" <> reason)
    fact.NotApplicable(reason) ->
      UnavailableBinding("dataset_knowledge_time_not_applicable:" <> reason)
    fact.DecodeFailure(_, reason) ->
      UnavailableBinding("dataset_knowledge_time_decode_failure:" <> reason)
    fact.Conflicting(alternatives, reason) ->
      ConflictingBinding(
        "dataset_knowledge_time_conflicting:" <> reason,
        list.map(alternatives, fn(value) {
          value |> time.unix_milliseconds |> int.to_string
        }),
      )
  }
}

fn evaluate_predicate(
  prepared: Prepared,
  row: PreparedRow,
  dataset_binding: BindingFact,
  predicate: PreparedPredicate,
) -> PredicateState {
  let matches =
    list.filter(row.input.values, fn(value) {
      value.field == predicate.input.field
    })
  case matches {
    [] -> PredicateUnavailable("named_field_not_supplied")
    [value] -> evaluate_value(prepared, dataset_binding, value, predicate)
    _ -> PredicateUnavailable("multiple_values_for_named_field")
  }
}

fn evaluate_value(
  prepared: Prepared,
  dataset_binding: BindingFact,
  value: decode.ValueInput,
  predicate: PreparedPredicate,
) -> PredicateState {
  case value.unit == predicate.input.unit {
    False -> PredicateUnavailable("operand_unit_mismatch")
    True ->
      case value.known_at_unix_ms <= time.unix_milliseconds(prepared.cutoff) {
        False -> PredicateUnavailable("value_known_after_source_cutoff")
        True ->
          case evidence_binding(prepared, dataset_binding, value) {
            Error(reason) -> PredicateUnavailable(reason)
            Ok(_) -> compare_fact(value.fact, predicate)
          }
      }
  }
}

fn evidence_binding(
  prepared: Prepared,
  dataset_binding: BindingFact,
  value: decode.ValueInput,
) -> Result(Nil, String) {
  let parsed_roots =
    list.filter_map(value.evidence_roots, fn(root) {
      case identity.sha256(root) {
        Ok(root) -> Ok(root)
        Error(_) -> Error(Nil)
      }
    })
  case value.source_kind, dataset_binding {
    "dataset_observation", ExactBinding(reference) ->
      case list.contains(parsed_roots, reference) {
        True -> Ok(Nil)
        False -> Error("dataset_fact_does_not_cite_selected_observation_hash")
      }
    "dataset_observation", _ ->
      Error("dataset_observation_binding_is_not_exact")
    "technical_receipt", _ ->
      case
        parsed_roots != []
        && list.all(parsed_roots, fn(root) {
          list.contains(prepared.technical_roots, root)
        })
      {
        True -> Ok(Nil)
        False -> Error("technical_fact_cites_undeclared_receipt")
      }
    _, _ -> Error("unsupported_value_source_kind")
  }
}

fn compare_fact(
  value: decode.FactInput,
  predicate: PreparedPredicate,
) -> PredicateState {
  case value.state, value.raw, value.reason, value.alternatives {
    "known", Some(raw), None, [] -> {
      let assert Ok(number) = decimal.parse(raw)
      comparison_state(raw, number, predicate)
    }
    "unknown", None, Some(reason), [] ->
      PredicateUnavailable("unknown:" <> reason)
    "not_obtained", None, Some(reason), [] ->
      PredicateUnavailable("not_obtained:" <> reason)
    "not_applicable", None, Some(reason), [] ->
      PredicateUnavailable("not_applicable:" <> reason)
    "decode_failure", Some(_), Some(reason), [] ->
      PredicateUnavailable("decode_failure:" <> reason)
    "conflicting", None, Some(reason), alternatives ->
      PredicateConflicting(
        reason,
        list.map(alternatives, fn(raw) {
          case decimal.parse(raw) {
            Error(_) -> AlternativeComparison(raw, None, None)
            Ok(number) ->
              AlternativeComparison(
                raw,
                Some(decimal.to_string(number)),
                Some(comparison_matches(
                  predicate.op,
                  decimal.compare(number, predicate.threshold),
                )),
              )
          }
        }),
      )
    _, _, _, _ -> PredicateUnavailable("invalid_fact_shape")
  }
}

fn comparison_state(
  raw: String,
  number: Decimal,
  predicate: PreparedPredicate,
) -> PredicateState {
  let comparison = decimal.compare(number, predicate.threshold)
  case comparison_matches(predicate.op, comparison) {
    True -> ObservedTrue(raw, decimal.to_string(number), comparison)
    False -> ObservedFalse(raw, decimal.to_string(number), comparison)
  }
}

fn comparison_matches(operator: Operator, comparison: Order) -> Bool {
  case operator, comparison {
    GreaterThan, Gt -> True
    GreaterThanOrEqual, Gt | GreaterThanOrEqual, Eq -> True
    LessThan, Lt -> True
    LessThanOrEqual, Lt | LessThanOrEqual, Eq -> True
    Equal, Eq -> True
    NotEqual, Lt | NotEqual, Gt -> True
    _, _ -> False
  }
}

fn relation(
  universe_binding: BindingFact,
  dataset_binding: BindingFact,
  predicates: List(PredicateFact),
) -> Relation {
  case binding_exact(universe_binding) && binding_exact(dataset_binding) {
    False -> Unresolved
    True ->
      case
        list.any(predicates, fn(value) {
          case value.state {
            ObservedFalse(_, _, _) -> True
            _ -> False
          }
        }),
        list.all(predicates, fn(value) {
          case value.state {
            ObservedTrue(_, _, _) -> True
            _ -> False
          }
        })
      {
        True, _ -> NotMatched
        False, True -> Matched
        False, False -> Unresolved
      }
  }
}

fn binding_exact(value: BindingFact) -> Bool {
  case value {
    ExactBinding(_) -> True
    _ -> False
  }
}

fn relation_counts(values: List(RowOutcome)) -> RelationCounts {
  list.fold(values, RelationCounts(0, 0, 0), fn(counts, value) {
    case value.relation {
      Matched ->
        RelationCounts(
          counts.matched + 1,
          counts.not_matched,
          counts.unresolved,
        )
      NotMatched ->
        RelationCounts(
          counts.matched,
          counts.not_matched + 1,
          counts.unresolved,
        )
      Unresolved ->
        RelationCounts(
          counts.matched,
          counts.not_matched,
          counts.unresolved + 1,
        )
    }
  })
}

fn partition_includes(partition: Partition, relation: Relation) -> Bool {
  case partition, relation {
    AllPartition, _ -> True
    MatchedPartition, Matched -> True
    NotMatchedPartition, NotMatched -> True
    UnresolvedPartition, Unresolved -> True
    _, _ -> False
  }
}

fn paginate(
  values: List(value),
  offset: Int,
  limit: Int,
) -> Result(Page(value), DomainError) {
  let total = list.length(values)
  use _ <- result.try(integer_range("page.offset", offset, 0, total))
  let page = values |> list.drop(offset) |> list.take(limit)
  let returned = list.length(page)
  let next_offset = case offset + returned < total {
    True -> Some(offset + returned)
    False -> None
  }
  Ok(Page(page, total, returned, total - returned, next_offset))
}

fn response_json(
  prepared: Prepared,
  request_handle: Sha256,
  semantic_handle: Sha256,
  counts: RelationCounts,
  partition: String,
  offset: Int,
  limit: Int,
  page: Page(RowOutcome),
) -> Json {
  let decode.ScreenInput(context, _, _, relation_policy, _) = prepared.input
  json.object([
    #("schema", json.string("pi-sparkles/stock-screen-result")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string("screen")),
    #("instructionRef", json.string(context.instruction_ref)),
    #("track", wire.track_json(prepared.track)),
    #(
      "dateRange",
      json.object([
        #("start", json.string(date_text(prepared.start))),
        #("end", json.string(date_text(prepared.end))),
        #("boundary", json.string("inclusive_gregorian_v1")),
      ]),
    ),
    #(
      "sourceCutoffUnixMilliseconds",
      prepared.cutoff |> time.unix_milliseconds |> json.int,
    ),
    #("universe", universe_summary_json(prepared)),
    #("dataset", dataset_summary_json(prepared)),
    #(
      "technicalReceiptRoots",
      json.array(prepared.technical_roots, wire.sha_json),
    ),
    #(
      "relationPolicy",
      json.object([
        #("matchPolicy", json.string(relation_policy.match_policy)),
        #("unresolvedPolicy", json.string(relation_policy.unresolved_policy)),
      ]),
    ),
    #("predicates", json.array(prepared.predicates, predicate_definition_json)),
    #("requestReceiptHandle", wire.sha_json(request_handle)),
    #("semanticReceiptHandle", wire.sha_json(semantic_handle)),
    #("relationCounts", relation_counts_json(counts)),
    #(
      "page",
      json.object([
        #("partition", json.string(partition)),
        #("offset", json.int(offset)),
        #("limit", json.int(limit)),
        #("matchedPartitionCount", json.int(page.total)),
        #("returnedCount", json.int(page.returned)),
        #("omittedCount", json.int(page.omitted)),
        #("nextOffset", json.nullable(page.next_offset, json.int)),
      ]),
    ),
    #("rows", json.array(page.values, row_outcome_json)),
    #(
      "availablePartitions",
      json.array(["matched", "not_matched", "unresolved", "all"], json.string),
    ),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], json.string)),
    #("limitations", json.array(limitations(), json.string)),
  ])
}

fn universe_summary_json(prepared: Prepared) -> Json {
  json.object([
    #("manifestHandle", wire.sha_json(prepared.universe_handle)),
    #("track", wire.track_json(manifest.universe_track(prepared.universe))),
    #(
      "membershipCount",
      prepared.universe
        |> manifest.universe_memberships
        |> list.length
        |> json.int,
    ),
  ])
}

fn dataset_summary_json(prepared: Prepared) -> Json {
  let manifest.Interval(start, end) =
    manifest.dataset_coverage(prepared.dataset)
  json.object([
    #("manifestId", json.string(manifest.dataset_manifest_id(prepared.dataset))),
    #("version", json.string(manifest.dataset_version(prepared.dataset))),
    #("provider", json.string(manifest.dataset_provider(prepared.dataset))),
    #("source", json.string(manifest.dataset_source(prepared.dataset))),
    #("manifestHandle", wire.sha_json(prepared.dataset_handle)),
    #(
      "coverage",
      json.object([
        #("start", json.string(date_text(start))),
        #("end", json.string(date_text(end))),
      ]),
    ),
    #(
      "observationCount",
      prepared.dataset
        |> manifest.dataset_observations
        |> list.length
        |> json.int,
    ),
    #(
      "limitations",
      prepared.dataset
        |> manifest.dataset_limitations
        |> json.array(json.string),
    ),
  ])
}

fn predicate_definition_json(value: PreparedPredicate) -> Json {
  json.object([
    #("id", json.string(value.input.id)),
    #(
      "leftOperand",
      json.object([
        #("kind", json.string("field")),
        #("field", json.string(value.input.field)),
        #("unit", json.string(value.input.unit)),
      ]),
    ),
    #("operator", json.string(operator_name(value.op))),
    #(
      "rightOperand",
      json.object([
        #("kind", json.string("constant")),
        #("raw", json.string(value.input.threshold_raw)),
        #("normalized", json.string(decimal.to_string(value.threshold))),
        #("unit", json.string(value.input.unit)),
      ]),
    ),
  ])
}

fn row_outcome_json(value: RowOutcome) -> Json {
  json.object([
    #("listingId", json.string(value.row.input.listing_id)),
    #("mic", json.string(value.row.input.mic)),
    #("observationDate", json.string(value.row.input.observation_date)),
    #("observationId", json.string(value.row.input.observation_id)),
    #("universeBinding", binding_json(value.universe_binding)),
    #("datasetBinding", binding_json(value.dataset_binding)),
    #("relation", json.string(relation_name(value.relation))),
    #("predicateFacts", json.array(value.predicate_facts, predicate_fact_json)),
  ])
}

fn binding_json(value: BindingFact) -> Json {
  case value {
    ExactBinding(reference) ->
      json.object([
        #("state", json.string("exact")),
        #("reference", wire.sha_json(reference)),
      ])
    UnavailableBinding(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("reason", json.string(reason)),
      ])
    ConflictingBinding(reason, alternatives) ->
      json.object([
        #("state", json.string("conflicting")),
        #("reason", json.string(reason)),
        #("alternatives", json.array(alternatives, json.string)),
      ])
  }
}

fn predicate_fact_json(value: PredicateFact) -> Json {
  json.object([
    #("predicateId", json.string(value.predicate.input.id)),
    #("field", json.string(value.predicate.input.field)),
    #("operator", json.string(operator_name(value.predicate.op))),
    #(
      "threshold",
      json.object([
        #("raw", json.string(value.predicate.input.threshold_raw)),
        #(
          "normalized",
          json.string(decimal.to_string(value.predicate.threshold)),
        ),
        #("unit", json.string(value.predicate.input.unit)),
      ]),
    ),
    #("fact", predicate_state_json(value.state)),
  ])
}

fn predicate_state_json(value: PredicateState) -> Json {
  case value {
    ObservedTrue(raw, normalized, comparison) ->
      observed_json("observed_true", raw, normalized, comparison)
    ObservedFalse(raw, normalized, comparison) ->
      observed_json("observed_false", raw, normalized, comparison)
    PredicateUnavailable(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("reason", json.string(reason)),
      ])
    PredicateConflicting(reason, alternatives) ->
      json.object([
        #("state", json.string("conflicting")),
        #("reason", json.string(reason)),
        #("alternatives", json.array(alternatives, alternative_comparison_json)),
      ])
  }
}

fn observed_json(
  state: String,
  raw: String,
  normalized: String,
  comparison: Order,
) -> Json {
  json.object([
    #("state", json.string(state)),
    #("raw", json.string(raw)),
    #("normalized", json.string(normalized)),
    #("comparison", json.string(order_name(comparison))),
  ])
}

fn alternative_comparison_json(value: AlternativeComparison) -> Json {
  json.object([
    #("raw", json.string(value.raw)),
    #("normalized", json.nullable(value.normalized, json.string)),
    #(
      "observed",
      json.nullable(value.observed, fn(value) {
        json.string(case value {
          True -> "observed_true"
          False -> "observed_false"
        })
      }),
    ),
  ])
}

fn canonical_request_json(prepared: Prepared) -> Json {
  let decode.ScreenInput(context, _, _, relation_policy, _) = prepared.input
  json.object([
    #("schema", json.string("pi-sparkles/stock-screen-request")),
    #("schemaVersion", json.int(1)),
    #("instructionRef", json.string(context.instruction_ref)),
    #("track", wire.track_json(prepared.track)),
    #("dateStart", json.string(date_text(prepared.start))),
    #("dateEnd", json.string(date_text(prepared.end))),
    #(
      "sourceCutoffUnixMilliseconds",
      prepared.cutoff |> time.unix_milliseconds |> json.int,
    ),
    #("universeManifestHandle", wire.sha_json(prepared.universe_handle)),
    #("datasetManifestHandle", wire.sha_json(prepared.dataset_handle)),
    #(
      "technicalReceiptRoots",
      json.array(prepared.technical_roots, wire.sha_json),
    ),
    #("predicates", json.array(prepared.predicates, predicate_definition_json)),
    #("rows", json.array(prepared.rows, canonical_row_json)),
    #(
      "relationPolicy",
      json.object([
        #("matchPolicy", json.string(relation_policy.match_policy)),
        #("unresolvedPolicy", json.string(relation_policy.unresolved_policy)),
      ]),
    ),
  ])
}

fn canonical_row_json(value: PreparedRow) -> Json {
  json.object([
    #("listingId", json.string(value.input.listing_id)),
    #("mic", json.string(value.input.mic)),
    #("observationDate", json.string(value.input.observation_date)),
    #("observationId", json.string(value.input.observation_id)),
    #("values", json.array(value.input.values, canonical_value_json)),
  ])
}

fn canonical_value_json(value: decode.ValueInput) -> Json {
  json.object([
    #("field", json.string(value.field)),
    #("unit", json.string(value.unit)),
    #("sourceKind", json.string(value.source_kind)),
    #("knownAtUnixMilliseconds", json.int(value.known_at_unix_ms)),
    #("evidenceRoots", json.array(value.evidence_roots, json.string)),
    #("fact", canonical_fact_json(value.fact)),
  ])
}

fn canonical_fact_json(value: decode.FactInput) -> Json {
  json.object([
    #("state", json.string(value.state)),
    #("raw", json.nullable(value.raw, json.string)),
    #("reason", json.nullable(value.reason, json.string)),
    #("alternatives", json.array(value.alternatives, json.string)),
  ])
}

fn relation_counts_json(value: RelationCounts) -> Json {
  json.object([
    #("matched", json.int(value.matched)),
    #("notMatched", json.int(value.not_matched)),
    #("unresolved", json.int(value.unresolved)),
    #("total", json.int(value.matched + value.not_matched + value.unresolved)),
  ])
}

fn parse_track(value: String) -> Result(finance_track.Track, DomainError) {
  finance_track.from_name(value)
  |> result.map_error(fn(_) {
    InvalidField("context.track", "expected cn, hk, or us")
  })
}

fn parse_operator(value: String) -> Result(Operator, DomainError) {
  case value {
    "greater_than" -> Ok(GreaterThan)
    "greater_than_or_equal" -> Ok(GreaterThanOrEqual)
    "less_than" -> Ok(LessThan)
    "less_than_or_equal" -> Ok(LessThanOrEqual)
    "equal" -> Ok(Equal)
    "not_equal" -> Ok(NotEqual)
    _ ->
      Error(InvalidField(
        "predicates[].operator",
        "expected a supported exact decimal comparison operator",
      ))
  }
}

fn operator_name(value: Operator) -> String {
  case value {
    GreaterThan -> "greater_than"
    GreaterThanOrEqual -> "greater_than_or_equal"
    LessThan -> "less_than"
    LessThanOrEqual -> "less_than_or_equal"
    Equal -> "equal"
    NotEqual -> "not_equal"
  }
}

fn parse_partition(value: String) -> Result(Partition, DomainError) {
  case value {
    "matched" -> Ok(MatchedPartition)
    "not_matched" -> Ok(NotMatchedPartition)
    "unresolved" -> Ok(UnresolvedPartition)
    "all" -> Ok(AllPartition)
    _ ->
      Error(InvalidField(
        "page.partition",
        "expected matched, not_matched, unresolved, or all",
      ))
  }
}

fn partition_name(value: Partition) -> String {
  case value {
    MatchedPartition -> "matched"
    NotMatchedPartition -> "not_matched"
    UnresolvedPartition -> "unresolved"
    AllPartition -> "all"
  }
}

fn relation_name(value: Relation) -> String {
  case value {
    Matched -> "matched"
    NotMatched -> "not_matched"
    Unresolved -> "unresolved"
  }
}

fn order_name(value: Order) -> String {
  case value {
    Lt -> "less_than_threshold"
    Eq -> "equal_to_threshold"
    Gt -> "greater_than_threshold"
  }
}

fn exact_track(
  field: String,
  expected: finance_track.Track,
  actual: finance_track.Track,
) -> Result(Nil, DomainError) {
  case expected == actual {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "manifest track "
          <> finance_track.name(actual)
          <> " does not equal request track "
          <> finance_track.name(expected),
      ))
  }
}

fn range_inside(
  field: String,
  start: time.Date,
  end: time.Date,
  coverage: manifest.Interval,
) -> Result(Nil, DomainError) {
  let manifest.Interval(coverage_start, coverage_end) = coverage
  case
    calendar_date.compare(start, coverage_start),
    calendar_date.compare(end, coverage_end)
  {
    Lt, _ | _, Gt ->
      Error(InvalidField(
        field,
        "requested range must be inside the exact manifest coverage",
      ))
    _, _ -> Ok(Nil)
  }
}

fn date_inside(
  field: String,
  value: time.Date,
  start: time.Date,
  end: time.Date,
) -> Result(Nil, DomainError) {
  case calendar_date.compare(value, start), calendar_date.compare(value, end) {
    Lt, _ | _, Gt ->
      Error(InvalidField(field, "must be inside the requested date range"))
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

fn exact_policy(
  field: String,
  actual: String,
  expected: String,
) -> Result(Nil, DomainError) {
  case actual == expected {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "first slice requires " <> expected))
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

fn unique_hashes(
  field: String,
  values: List(Sha256),
  seen: List(Sha256),
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case list.contains(seen, value) {
        True -> Error(InvalidField(field, "receipt hashes must be unique"))
        False -> unique_hashes(field, rest, [value, ..seen])
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
        "expected an integer from "
          <> int.to_string(minimum)
          <> " through "
          <> int.to_string(maximum),
      ))
  }
}

fn list_count(
  field: String,
  values: List(value),
  minimum: Int,
  maximum: Int,
) -> Result(Nil, DomainError) {
  integer_range(field <> " count", list.length(values), minimum, maximum)
}

fn trimmed_text(
  field: String,
  value: String,
  maximum: Int,
) -> Result(Nil, DomainError) {
  case
    value != ""
    && string.trim(value) == value
    && string.length(value) <= maximum
    && !string.contains(value, "\n")
    && !string.contains(value, "\r")
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "expected non-empty trimmed single-line text up to "
          <> int.to_string(maximum)
          <> " characters",
      ))
  }
}

fn limitations() -> List(String) {
  [
    "screen_uses_only_caller_supplied_canonical_manifests_rows_predicates_and_receipts",
    "manifest_and_result_hashes_prove_reproduction_not_source_correctness_or_origin_authentication",
    "matched_is_only_the_named_mechanical_relation_not_eligibility_suitability_or_recommendation",
    "unknown_not_obtained_not_applicable_decode_failure_and_conflicting_facts_are_preserved",
    "no_fetch_source_or_vintage_selection_imputation_cross_track_merge_rank_score_or_next_action",
    "first_slice_supports_only_exact_decimal_field_versus_constant_predicates",
  ]
}
