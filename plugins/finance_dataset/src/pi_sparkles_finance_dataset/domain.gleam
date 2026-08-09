import finance_calendar/date as calendar_date
import finance_core/time
import finance_ohlcv
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_provenance/redact
import finance_replay/fact
import finance_replay/manifest
import finance_replay/wire
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_finance_dataset/decode

const maximum_manifest_bytes = 10_000_000

const maximum_supplement_entries = 10_000

const maximum_page_size = 200

pub opaque type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  ManifestDecodeFailure(reason: String)
  ManifestNotCanonical
  ManifestHashMismatch(expected: String, actual: String)
  SelectorNotFound(listing_id: String, observation_date: String)
}

type PreparedOmission {
  PreparedOmission(listing_id: String, gap: finance_ohlcv.Gap)
}

type Prepared {
  Prepared(
    dataset: manifest.DatasetManifest,
    manifest_handle: String,
    manifest_bytes: Int,
    omissions: List(PreparedOmission),
    receipt_roots: List(Sha256),
    inspection_projection_handle: String,
  )
}

type DrillEntry {
  ObservationEntry(manifest.ObservationHandle)
  OmissionEntry(PreparedOmission)
}

type FactCounts {
  FactCounts(
    known: Int,
    unknown: Int,
    not_obtained: Int,
    not_applicable: Int,
    conflicting: Int,
    decode_failure: Int,
  )
}

type GapCounts {
  GapCounts(
    market_closure: Int,
    suspension: Int,
    provider_omission: Int,
    unavailable_history: Int,
  )
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
      "Invalid explicit finance-dataset field " <> field <> ": " <> reason
    ManifestDecodeFailure(reason) ->
      "The supplied dataset manifest failed the finance_replay contract: "
      <> reason
    ManifestNotCanonical ->
      "The supplied manifestJson is not the exact canonical finance_replay dataset envelope"
    ManifestHashMismatch(expected, actual) ->
      "The supplied manifestHash "
      <> expected
      <> " does not match the canonical dataset handle "
      <> actual
    SelectorNotFound(listing_id, observation_date) ->
      "No exact observation or supplied omission names listing "
      <> listing_id
      <> " on "
      <> observation_date
      <> "; no fallback was used"
  }
}

pub fn run_inspect(
  value: decode.InspectInput,
) -> Result(Response, DomainError) {
  use prepared <- result.try(prepare(value.dataset))
  let observations = manifest.dataset_observations(prepared.dataset)
  Ok(Response(
    "Inspected exact dataset manifest " <> prepared.manifest_handle,
    common(prepared, "inspect_dataset", [
      #("counts", dataset_counts_json(prepared, observations)),
      #("omissionSummary", omission_counts_json(prepared.omissions)),
      #("receiptRoots", json.array(prepared.receipt_roots, wire.sha_json)),
    ]),
  ))
}

pub fn run_drill(value: decode.DrillInput) -> Result(Response, DomainError) {
  use _ <- result.try(trimmed_text("listingId", value.listing_id, 2000))
  use requested_date <- result.try(date(
    "observationDate",
    value.observation_date,
  ))
  use _ <- result.try(page_limit(value.offset, value.limit))
  use prepared <- result.try(prepare(value.dataset))
  let observation_entries =
    prepared.dataset
    |> manifest.dataset_observations
    |> list.filter(fn(item) {
      item.listing_id == value.listing_id
      && item.observation_date == requested_date
    })
    |> list.map(ObservationEntry)
  let omission_entries =
    prepared.omissions
    |> list.filter(fn(item) {
      item.listing_id == value.listing_id
      && omission_date(item) == requested_date
    })
    |> list.map(OmissionEntry)
  let entries = list.append(observation_entries, omission_entries)
  case entries {
    [] -> Error(SelectorNotFound(value.listing_id, value.observation_date))
    _ -> {
      use page <- result.try(paginate(entries, value.offset, value.limit))
      Ok(Response(
        "Returned "
          <> int.to_string(page.returned)
          <> " of "
          <> int.to_string(page.total)
          <> " exact dataset entries for "
          <> value.listing_id
          <> " on "
          <> value.observation_date,
        common(prepared, "drill_observation", [
          #(
            "query",
            json.object([
              #("listingId", json.string(value.listing_id)),
              #("observationDate", json.string(value.observation_date)),
            ]),
          ),
          #("offset", json.int(value.offset)),
          #("limit", json.int(value.limit)),
          #("matchedCount", json.int(page.total)),
          #("returnedCount", json.int(page.returned)),
          #("omittedCount", json.int(page.omitted)),
          #("nextOffset", json.nullable(page.next_offset, json.int)),
          #("entries", json.array(page.values, drill_entry_json)),
        ]),
      ))
    }
  }
}

pub fn run_vintages(
  value: decode.VintagesInput,
) -> Result(Response, DomainError) {
  use _ <- result.try(validate_optional_listing(value.listing_id))
  use requested_date <- result.try(optional_date(
    "observationDate",
    value.observation_date,
  ))
  use _ <- result.try(page_limit(value.offset, value.limit))
  use prepared <- result.try(prepare(value.dataset))
  let matching =
    prepared.dataset
    |> manifest.dataset_observations
    |> list.filter(fn(item) {
      optional_text_matches(value.listing_id, item.listing_id)
      && optional_date_matches(requested_date, item.observation_date)
    })
  use page <- result.try(paginate(matching, value.offset, value.limit))
  Ok(Response(
    "Listed "
      <> int.to_string(page.returned)
      <> " of "
      <> int.to_string(page.total)
      <> " exact supplied observation vintages",
    common(prepared, "list_vintages", [
      #(
        "query",
        json.object([
          #("listingId", json.nullable(value.listing_id, json.string)),
          #(
            "observationDate",
            json.nullable(value.observation_date, json.string),
          ),
        ]),
      ),
      #("offset", json.int(value.offset)),
      #("limit", json.int(value.limit)),
      #("matchedCount", json.int(page.total)),
      #("returnedCount", json.int(page.returned)),
      #("omittedCount", json.int(page.omitted)),
      #("nextOffset", json.nullable(page.next_offset, json.int)),
      #("vintages", json.array(page.values, vintage_json)),
    ]),
  ))
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

fn paginate(
  values: List(value),
  offset: Int,
  limit: Int,
) -> Result(Page(value), DomainError) {
  let total = list.length(values)
  use _ <- result.try(integer_range("offset", offset, 0, total))
  let page = values |> list.drop(offset) |> list.take(limit)
  let returned = list.length(page)
  let next_offset = case offset + returned < total {
    True -> Some(offset + returned)
    False -> None
  }
  Ok(Page(page, total, returned, total - returned, next_offset))
}

fn prepare(value: decode.DatasetInput) -> Result(Prepared, DomainError) {
  let manifest_bytes = string.byte_size(value.manifest_json)
  use _ <- result.try(integer_range(
    "dataset.manifestJson bytes",
    manifest_bytes,
    1,
    maximum_manifest_bytes,
  ))
  use expected <- result.try(sha("dataset.manifestHash", value.manifest_hash))
  use _ <- result.try(count_bound(
    "dataset.omissions",
    value.omissions,
    maximum_supplement_entries,
  ))
  use _ <- result.try(count_bound(
    "dataset.receiptRoots",
    value.receipt_roots,
    maximum_supplement_entries,
  ))
  use dataset <- result.try(
    manifest.decode_dataset(value.manifest_json)
    |> result.map_error(fn(error) {
      ManifestDecodeFailure(string.inspect(error))
    }),
  )
  use _ <- result.try(
    case manifest.encode_dataset(dataset) == value.manifest_json {
      True -> Ok(Nil)
      False -> Error(ManifestNotCanonical)
    },
  )
  let actual = manifest.dataset_digest(dataset)
  let expected_text = identity.sha256_value(expected)
  let actual_text = identity.sha256_value(actual)
  use _ <- result.try(case expected == actual {
    True -> Ok(Nil)
    False -> Error(ManifestHashMismatch(expected_text, actual_text))
  })
  use omissions <- result.try(
    list.try_map(value.omissions, fn(input) { prepare_omission(input, dataset) }),
  )
  use receipt_roots <- result.try(
    list.try_map(value.receipt_roots, fn(value) {
      sha("dataset.receiptRoots[]", value)
    }),
  )
  let projection_handle =
    inspection_projection_json(actual, omissions, receipt_roots)
    |> json.to_string
    |> hash.text
  let assert Ok(projection_handle) = projection_handle
  Ok(Prepared(
    dataset,
    actual_text,
    manifest_bytes,
    omissions,
    receipt_roots,
    identity.sha256_value(projection_handle),
  ))
}

fn prepare_omission(
  value: decode.OmissionInput,
  dataset: manifest.DatasetManifest,
) -> Result(PreparedOmission, DomainError) {
  use _ <- result.try(trimmed_text(
    "dataset.omissions[].listingId",
    value.listing_id,
    2000,
  ))
  use observation_date <- result.try(date(
    "dataset.omissions[].observationDate",
    value.observation_date,
  ))
  let manifest.Interval(start, end) = manifest.dataset_coverage(dataset)
  use _ <- result.try(
    case
      calendar_date.compare(observation_date, start),
      calendar_date.compare(observation_date, end)
    {
      Lt, _ | _, Gt ->
        Error(InvalidField(
          "dataset.omissions[].observationDate",
          "must be inside the exact manifest coverage interval",
        ))
      _, _ -> Ok(Nil)
    },
  )
  use state <- result.try(gap_state(value.state))
  use _ <- result.try(validate_optional_text(
    "dataset.omissions[].evidenceReference",
    value.evidence_reference,
    4000,
  ))
  Ok(PreparedOmission(
    value.listing_id,
    finance_ohlcv.Gap(observation_date, state, value.evidence_reference),
  ))
}

fn common(
  prepared: Prepared,
  operation: String,
  fields: List(#(String, Json)),
) -> Json {
  json.object(list.append(
    [
      #("schemaVersion", json.int(1)),
      #("operation", json.string(operation)),
      #("manifest", manifest_summary_json(prepared.dataset)),
      #("manifestHandle", json.string(prepared.manifest_handle)),
      #("canonicalManifestBytes", json.int(prepared.manifest_bytes)),
      #(
        "inspectionProjectionHandle",
        json.string(prepared.inspection_projection_handle),
      ),
      #(
        "availableOperations",
        json.array(
          ["inspect_dataset", "drill_observation", "list_vintages"],
          json.string,
        ),
      ),
      #("decisionOwner", json.string("llm")),
      #(
        "pluginDecisionFields",
        json.array([], fn(value: String) { json.string(value) }),
      ),
      #(
        "limitations",
        json.array(
          [
            "Matching manifest and projection hashes prove content coherence only, not provider origin, source truth, authentication, licence permission, correctness, quality, sufficiency, or point-in-time safety.",
            "Observation handles retain metadata and content hashes; they do not contain the raw OHLCV row bytes.",
            "Supplied omissions and receipt roots are caller-provided projections; this shell does not infer gaps, choose vintages, fetch, repair, transform, persist, rank, recommend, or select a next operation.",
          ],
          json.string,
        ),
      ),
    ],
    fields,
  ))
}

fn manifest_summary_json(value: manifest.DatasetManifest) -> Json {
  let manifest.Interval(start, end) = manifest.dataset_coverage(value)
  let source = manifest.dataset_source(value)
  let safe_source = redact.url(source, [])
  json.object([
    #("manifestId", value |> manifest.dataset_manifest_id |> json.string),
    #("version", value |> manifest.dataset_version |> json.string),
    #("provider", value |> manifest.dataset_provider |> json.string),
    #("sourceOrImportProvenance", json.string(safe_source)),
    #("sourceReferenceRedacted", json.bool(source != safe_source)),
    #("track", value |> manifest.dataset_track |> wire.track_json),
    #(
      "coverage",
      json.object([
        #("start", json.string(date_text(start))),
        #("end", json.string(date_text(end))),
      ]),
    ),
    #(
      "declaredLimitations",
      json.array(manifest.dataset_limitations(value), json.string),
    ),
  ])
}

fn dataset_counts_json(
  prepared: Prepared,
  observations: List(manifest.ObservationHandle),
) -> Json {
  let listing_count =
    observations
    |> list.map(fn(value) { value.listing_id })
    |> list.unique
    |> list.length
  let date_count =
    observations
    |> list.map(fn(value) { date_text(value.observation_date) })
    |> list.unique
    |> list.length
  let lineage_links =
    observations
    |> list.fold(0, fn(total, value) {
      total + list.length(value.correction_lineage)
    })
  json.object([
    #("observations", json.int(list.length(observations))),
    #("distinctListingIds", json.int(listing_count)),
    #("distinctObservationDates", json.int(date_count)),
    #("suppliedOmissions", json.int(list.length(prepared.omissions))),
    #("suppliedReceiptRoots", json.int(list.length(prepared.receipt_roots))),
    #("correctionLineageLinks", json.int(lineage_links)),
    #(
      "factStates",
      json.object([
        #(
          "observationState",
          observations
            |> list.map(fn(value) { value.state })
            |> fact_counts
            |> fact_counts_json,
        ),
        #(
          "availabilityTime",
          observations
            |> list.map(fn(value) { value.availability_time })
            |> fact_counts
            |> fact_counts_json,
        ),
        #(
          "knowledgeTime",
          observations
            |> list.map(fn(value) { value.knowledge_time })
            |> fact_counts
            |> fact_counts_json,
        ),
        #(
          "correctionVintage",
          observations
            |> list.map(fn(value) { value.correction_vintage })
            |> fact_counts
            |> fact_counts_json,
        ),
      ]),
    ),
  ])
}

fn fact_counts(values: List(fact.Fact(value))) -> FactCounts {
  values
  |> list.fold(FactCounts(0, 0, 0, 0, 0, 0), fn(counts, value) {
    case value {
      fact.Known(_) -> FactCounts(..counts, known: counts.known + 1)
      fact.Unknown(_) -> FactCounts(..counts, unknown: counts.unknown + 1)
      fact.NotObtained(_) ->
        FactCounts(..counts, not_obtained: counts.not_obtained + 1)
      fact.NotApplicable(_) ->
        FactCounts(..counts, not_applicable: counts.not_applicable + 1)
      fact.Conflicting(_, _) ->
        FactCounts(..counts, conflicting: counts.conflicting + 1)
      fact.DecodeFailure(_, _) ->
        FactCounts(..counts, decode_failure: counts.decode_failure + 1)
    }
  })
}

fn fact_counts_json(value: FactCounts) -> Json {
  json.object([
    #("known", json.int(value.known)),
    #("unknown", json.int(value.unknown)),
    #("notObtained", json.int(value.not_obtained)),
    #("notApplicable", json.int(value.not_applicable)),
    #("conflicting", json.int(value.conflicting)),
    #("decodeFailure", json.int(value.decode_failure)),
  ])
}

fn omission_counts_json(values: List(PreparedOmission)) -> Json {
  let counts =
    values
    |> list.fold(GapCounts(0, 0, 0, 0), fn(counts, value) {
      case omission_state(value) {
        finance_ohlcv.MarketClosure ->
          GapCounts(..counts, market_closure: counts.market_closure + 1)
        finance_ohlcv.Suspension ->
          GapCounts(..counts, suspension: counts.suspension + 1)
        finance_ohlcv.ProviderOmission ->
          GapCounts(..counts, provider_omission: counts.provider_omission + 1)
        finance_ohlcv.UnavailableHistory ->
          GapCounts(
            ..counts,
            unavailable_history: counts.unavailable_history + 1,
          )
      }
    })
  json.object([
    #("total", json.int(list.length(values))),
    #("marketClosure", json.int(counts.market_closure)),
    #("suspension", json.int(counts.suspension)),
    #("providerOmission", json.int(counts.provider_omission)),
    #("unavailableHistory", json.int(counts.unavailable_history)),
    #("provenance", json.string("caller_supplied_finance_ohlcv_gap_projection")),
  ])
}

fn drill_entry_json(value: DrillEntry) -> Json {
  case value {
    ObservationEntry(value) ->
      json.object([
        #("kind", json.string("observation")),
        #("observation", observation_json(value)),
      ])
    OmissionEntry(value) ->
      json.object([
        #("kind", json.string("omission")),
        #("omission", omission_json(value)),
      ])
  }
}

fn observation_json(value: manifest.ObservationHandle) -> Json {
  json.object([
    #("observationId", json.string(value.observation_id)),
    #("listingId", json.string(value.listing_id)),
    #("mic", json.string(value.mic)),
    #("track", wire.track_json(value.track)),
    #("observationDate", json.string(date_text(value.observation_date))),
    #(
      "observationTime",
      fact.to_json(value.observation_time, wire.instant_json),
    ),
    #(
      "publicationTime",
      fact.to_json(value.publication_time, wire.instant_json),
    ),
    #(
      "availabilityTime",
      fact.to_json(value.availability_time, wire.instant_json),
    ),
    #("knowledgeTime", fact.to_json(value.knowledge_time, wire.instant_json)),
    #("retrievalTimeUnixMilliseconds", wire.instant_json(value.retrieval_time)),
    #("sourceCutoff", fact.to_json(value.source_cutoff, wire.instant_json)),
    #("correctionVintage", fact.to_json(value.correction_vintage, json.string)),
    #("correctionLineage", json.array(value.correction_lineage, wire.sha_json)),
    #("sessionType", fact.to_json(value.session_type, json.string)),
    #("calendarRef", fact.to_json(value.calendar_ref, wire.sha_json)),
    #("statusRef", fact.to_json(value.status_ref, wire.sha_json)),
    #("unit", fact.to_json(value.unit, json.string)),
    #("currency", fact.to_json(value.currency, json.string)),
    #("scale", fact.to_json(value.scale, json.int)),
    #("timezone", fact.to_json(value.timezone, json.string)),
    #("adjustmentBasis", fact.to_json(value.adjustment_basis, json.string)),
    #("quantitySemantics", fact.to_json(value.quantity_semantics, json.string)),
    #("entitlement", fact.to_json(value.entitlement, json.string)),
    #("licence", fact.to_json(value.licence, json.string)),
    #("state", fact.to_json(value.state, json.string)),
    #("contentHash", wire.sha_json(value.content_hash)),
    #(
      "corporateActionRefs",
      json.array(value.corporate_action_refs, wire.sha_json),
    ),
    #(
      "transformationRefs",
      json.array(value.transformation_refs, wire.sha_json),
    ),
  ])
}

fn vintage_json(value: manifest.ObservationHandle) -> Json {
  json.object([
    #("observationId", json.string(value.observation_id)),
    #("listingId", json.string(value.listing_id)),
    #("mic", json.string(value.mic)),
    #("track", wire.track_json(value.track)),
    #("observationDate", json.string(date_text(value.observation_date))),
    #(
      "publicationTime",
      fact.to_json(value.publication_time, wire.instant_json),
    ),
    #(
      "availabilityTime",
      fact.to_json(value.availability_time, wire.instant_json),
    ),
    #("knowledgeTime", fact.to_json(value.knowledge_time, wire.instant_json)),
    #("retrievalTimeUnixMilliseconds", wire.instant_json(value.retrieval_time)),
    #("sourceCutoff", fact.to_json(value.source_cutoff, wire.instant_json)),
    #("correctionVintage", fact.to_json(value.correction_vintage, json.string)),
    #("correctionLineage", json.array(value.correction_lineage, wire.sha_json)),
    #("state", fact.to_json(value.state, json.string)),
    #("contentHash", wire.sha_json(value.content_hash)),
    #("calendarRef", fact.to_json(value.calendar_ref, wire.sha_json)),
    #("statusRef", fact.to_json(value.status_ref, wire.sha_json)),
    #(
      "corporateActionRefs",
      json.array(value.corporate_action_refs, wire.sha_json),
    ),
    #(
      "transformationRefs",
      json.array(value.transformation_refs, wire.sha_json),
    ),
  ])
}

fn omission_json(value: PreparedOmission) -> Json {
  let finance_ohlcv.Gap(observation_date, state, evidence_reference) = value.gap
  let safe_evidence_reference =
    evidence_reference |> option.map(fn(value) { redact.url(value, []) })
  json.object([
    #("listingId", json.string(value.listing_id)),
    #("observationDate", json.string(date_text(observation_date))),
    #("state", json.string(gap_state_name(state))),
    #("evidenceReference", json.nullable(safe_evidence_reference, json.string)),
    #(
      "evidenceReferenceRedacted",
      json.bool(evidence_reference != safe_evidence_reference),
    ),
    #("provenance", json.string("caller_supplied_finance_ohlcv_gap_projection")),
  ])
}

fn inspection_projection_json(
  manifest_handle: Sha256,
  omissions: List(PreparedOmission),
  receipt_roots: List(Sha256),
) -> Json {
  json.object([
    #("schema", json.string("pi_sparkles_finance_dataset_inspection")),
    #("schemaVersion", json.int(1)),
    #("manifestHandle", wire.sha_json(manifest_handle)),
    #("omissions", json.array(omissions, canonical_omission_json)),
    #("receiptRoots", json.array(receipt_roots, wire.sha_json)),
  ])
}

fn canonical_omission_json(value: PreparedOmission) -> Json {
  let finance_ohlcv.Gap(observation_date, state, evidence_reference) = value.gap
  json.object([
    #("listingId", json.string(value.listing_id)),
    #("observationDate", json.string(date_text(observation_date))),
    #("state", json.string(gap_state_name(state))),
    #("evidenceReference", json.nullable(evidence_reference, json.string)),
    #("provenance", json.string("caller_supplied_finance_ohlcv_gap_projection")),
  ])
}

fn omission_date(value: PreparedOmission) -> time.Date {
  let finance_ohlcv.Gap(date, _, _) = value.gap
  date
}

fn omission_state(value: PreparedOmission) -> finance_ohlcv.GapState {
  let finance_ohlcv.Gap(_, state, _) = value.gap
  state
}

fn gap_state(value: String) -> Result(finance_ohlcv.GapState, DomainError) {
  case value {
    "market_closure" -> Ok(finance_ohlcv.MarketClosure)
    "suspension" -> Ok(finance_ohlcv.Suspension)
    "provider_omission" -> Ok(finance_ohlcv.ProviderOmission)
    "unavailable_history" -> Ok(finance_ohlcv.UnavailableHistory)
    _ ->
      Error(InvalidField(
        "dataset.omissions[].state",
        "expected market_closure, suspension, provider_omission, or unavailable_history",
      ))
  }
}

fn gap_state_name(value: finance_ohlcv.GapState) -> String {
  case value {
    finance_ohlcv.MarketClosure -> "market_closure"
    finance_ohlcv.Suspension -> "suspension"
    finance_ohlcv.ProviderOmission -> "provider_omission"
    finance_ohlcv.UnavailableHistory -> "unavailable_history"
  }
}

fn optional_text_matches(expected: Option(String), actual: String) -> Bool {
  case expected {
    None -> True
    Some(value) -> value == actual
  }
}

fn optional_date_matches(
  expected: Option(time.Date),
  actual: time.Date,
) -> Bool {
  case expected {
    None -> True
    Some(value) -> value == actual
  }
}

fn validate_optional_listing(
  value: Option(String),
) -> Result(Nil, DomainError) {
  case value {
    None -> Ok(Nil)
    Some(value) -> trimmed_text("listingId", value, 2000)
  }
}

fn optional_date(
  field: String,
  value: Option(String),
) -> Result(Option(time.Date), DomainError) {
  case value {
    None -> Ok(None)
    Some(value) -> date(field, value) |> result.map(Some)
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

fn sha(field: String, value: String) -> Result(Sha256, DomainError) {
  identity.sha256(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "expected exactly 64 hexadecimal SHA-256 characters")
  })
}

fn page_limit(offset: Int, limit: Int) -> Result(Nil, DomainError) {
  use _ <- result.try(integer_range(
    "offset",
    offset,
    0,
    maximum_supplement_entries,
  ))
  integer_range("limit", limit, 1, maximum_page_size)
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

fn count_bound(
  field: String,
  values: List(value),
  maximum: Int,
) -> Result(Nil, DomainError) {
  integer_range(field <> " count", list.length(values), 0, maximum)
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

fn validate_optional_text(
  field: String,
  value: Option(String),
  maximum: Int,
) -> Result(Nil, DomainError) {
  case value {
    None -> Ok(Nil)
    Some(value) -> trimmed_text(field, value, maximum)
  }
}
