import finance_calendar/date
import finance_core/time.{type Date, type Instant}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/fact.{type Fact}
import finance_replay/wire
import finance_track.{type Track}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

pub type Interval {
  Interval(start: Date, end: Date)
}

pub type OpenInterval {
  OpenInterval(start: Date, end: Option(Date))
}

pub type UniverseDefinitionKind {
  ExactEnumerated
  RuleProjection(receipt: Sha256)
  ImportedDeclaration(source: String)
}

pub type Provenance {
  ProviderObserved
  AuthorityObserved
  CallerDeclared
  Imported
}

pub type MembershipState {
  MembershipKnown
  MembershipUnknown(reason: String)
  MembershipConflicting(alternatives: List(String), reason: String)
}

pub type Membership {
  Membership(
    listing_id: String,
    mic: String,
    track: Track,
    symbol: Fact(String),
    symbol_interval: Fact(OpenInterval),
    listing_interval: OpenInterval,
    security_class: Fact(String),
    status_interval: Fact(OpenInterval),
    membership_effective: Date,
    membership_end: Fact(Date),
    publication_time: Fact(Instant),
    knowledge_time: Fact(Instant),
    retrieval_time: Instant,
    source_receipt: Sha256,
    correction_lineage: List(Sha256),
    state: MembershipState,
  )
}

pub opaque type UniverseManifest {
  UniverseManifest(
    manifest_id: String,
    version: String,
    track: Track,
    definition_kind: UniverseDefinitionKind,
    as_of_time: Instant,
    coverage: Interval,
    source_receipt: Sha256,
    provenance: Provenance,
    limitations: List(String),
    memberships: List(Membership),
    digest: Sha256,
  )
}

pub type ObservationHandle {
  ObservationHandle(
    observation_id: String,
    listing_id: String,
    mic: String,
    track: Track,
    observation_date: Date,
    observation_time: Fact(Instant),
    publication_time: Fact(Instant),
    availability_time: Fact(Instant),
    knowledge_time: Fact(Instant),
    retrieval_time: Instant,
    source_cutoff: Fact(Instant),
    correction_vintage: Fact(String),
    correction_lineage: List(Sha256),
    session_type: Fact(String),
    calendar_ref: Fact(Sha256),
    status_ref: Fact(Sha256),
    unit: Fact(String),
    currency: Fact(String),
    scale: Fact(Int),
    timezone: Fact(String),
    adjustment_basis: Fact(String),
    quantity_semantics: Fact(String),
    entitlement: Fact(String),
    licence: Fact(String),
    state: Fact(String),
    content_hash: Sha256,
    corporate_action_refs: List(Sha256),
    transformation_refs: List(Sha256),
  )
}

pub opaque type DatasetManifest {
  DatasetManifest(
    manifest_id: String,
    version: String,
    provider: String,
    source: String,
    track: Track,
    coverage: Interval,
    observations: List(ObservationHandle),
    limitations: List(String),
    digest: Sha256,
  )
}

pub type ManifestError {
  InvalidText(field: String)
  InvalidInterval(field: String)
  TrackMismatch(expected: Track, received: Track)
  DuplicateObservationId(String)
  TooManyEntries(received: Int, maximum: Int)
  HashMismatch
  InvalidJson
}

pub const maximum_manifest_entries = 10_000

pub fn interval(start: Date, end: Date) -> Result(Interval, ManifestError) {
  case date.compare(start, end) == order.Gt {
    True -> Error(InvalidInterval("interval"))
    False -> Ok(Interval(start, end))
  }
}

pub fn open_interval(
  start: Date,
  end: Option(Date),
) -> Result(OpenInterval, ManifestError) {
  case end {
    Some(end) ->
      case date.compare(start, end) == order.Gt {
        True -> Error(InvalidInterval("open_interval"))
        False -> Ok(OpenInterval(start, Some(end)))
      }
    _ -> Ok(OpenInterval(start, end))
  }
}

pub fn universe(
  manifest_id: String,
  version: String,
  track: Track,
  definition_kind: UniverseDefinitionKind,
  as_of_time: Instant,
  coverage: Interval,
  source_receipt: Sha256,
  provenance: Provenance,
  limitations: List(String),
  memberships: List(Membership),
) -> Result(UniverseManifest, ManifestError) {
  use _ <- result.try(validate_text(manifest_id, "manifest_id"))
  use _ <- result.try(validate_text(version, "version"))
  use _ <- result.try(validate_definition_kind(definition_kind))
  use _ <- result.try(validate_texts(limitations, "limitation"))
  use _ <- result.try(validate_entry_count(memberships))
  use _ <- result.try(validate_memberships(memberships, track))
  let payload =
    universe_payload(
      manifest_id,
      version,
      track,
      definition_kind,
      as_of_time,
      coverage,
      source_receipt,
      provenance,
      limitations,
      memberships,
    )
  let assert Ok(digest) = payload |> json.to_string |> hash.text
  Ok(UniverseManifest(
    manifest_id,
    version,
    track,
    definition_kind,
    as_of_time,
    coverage,
    source_receipt,
    provenance,
    limitations,
    memberships,
    digest,
  ))
}

pub fn dataset(
  manifest_id: String,
  version: String,
  provider: String,
  source: String,
  track: Track,
  coverage: Interval,
  observations: List(ObservationHandle),
  limitations: List(String),
) -> Result(DatasetManifest, ManifestError) {
  use _ <- result.try(validate_text(manifest_id, "manifest_id"))
  use _ <- result.try(validate_text(version, "version"))
  use _ <- result.try(validate_text(provider, "provider"))
  use _ <- result.try(validate_text(source, "source"))
  use _ <- result.try(validate_texts(limitations, "limitation"))
  use _ <- result.try(validate_entry_count(observations))
  use _ <- result.try(validate_observations(observations, track, []))
  let payload =
    dataset_payload(
      manifest_id,
      version,
      provider,
      source,
      track,
      coverage,
      observations,
      limitations,
    )
  let assert Ok(digest) = payload |> json.to_string |> hash.text
  Ok(DatasetManifest(
    manifest_id,
    version,
    provider,
    source,
    track,
    coverage,
    observations,
    limitations,
    digest,
  ))
}

pub fn encode_universe(value: UniverseManifest) -> String {
  json.object([
    #("payload", universe_to_json(value)),
    #("canonical_content_hash", wire.sha_json(value.digest)),
  ])
  |> json.to_string
}

pub fn decode_universe(
  input: String,
) -> Result(UniverseManifest, ManifestError) {
  case json.parse(input, universe_envelope_decoder()) {
    Error(_) -> Error(InvalidJson)
    Ok(#(value, expected)) ->
      case value.digest == expected {
        True -> Ok(value)
        False -> Error(HashMismatch)
      }
  }
}

pub fn encode_dataset(value: DatasetManifest) -> String {
  json.object([
    #("payload", dataset_to_json(value)),
    #("canonical_content_hash", wire.sha_json(value.digest)),
  ])
  |> json.to_string
}

pub fn decode_dataset(input: String) -> Result(DatasetManifest, ManifestError) {
  case json.parse(input, dataset_envelope_decoder()) {
    Error(_) -> Error(InvalidJson)
    Ok(#(value, expected)) ->
      case value.digest == expected {
        True -> Ok(value)
        False -> Error(HashMismatch)
      }
  }
}

pub fn universe_to_json(value: UniverseManifest) -> json.Json {
  with_digest(
    universe_payload(
      value.manifest_id,
      value.version,
      value.track,
      value.definition_kind,
      value.as_of_time,
      value.coverage,
      value.source_receipt,
      value.provenance,
      value.limitations,
      value.memberships,
    ),
    value.digest,
  )
}

pub fn dataset_to_json(value: DatasetManifest) -> json.Json {
  with_digest(
    dataset_payload(
      value.manifest_id,
      value.version,
      value.provider,
      value.source,
      value.track,
      value.coverage,
      value.observations,
      value.limitations,
    ),
    value.digest,
  )
}

fn with_digest(payload: json.Json, digest: Sha256) -> json.Json {
  json.object([
    #("content", payload),
    #("content_hash", wire.sha_json(digest)),
  ])
}

fn universe_payload(
  manifest_id: String,
  version: String,
  track: Track,
  definition_kind: UniverseDefinitionKind,
  as_of_time: Instant,
  coverage: Interval,
  source_receipt: Sha256,
  provenance: Provenance,
  limitations: List(String),
  memberships: List(Membership),
) -> json.Json {
  json.object([
    #("schema", json.string("finance_replay_universe_manifest")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("manifest_id", json.string(manifest_id)),
    #("version", json.string(version)),
    #("track", wire.track_json(track)),
    #("definition_kind", definition_kind_json(definition_kind)),
    #("as_of_time_unix_ms", wire.instant_json(as_of_time)),
    #("coverage", interval_json(coverage)),
    #("source_receipt", wire.sha_json(source_receipt)),
    #("provenance", provenance_json(provenance)),
    #("limitations", json.array(limitations, json.string)),
    #("memberships", json.array(memberships, membership_json)),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

fn dataset_payload(
  manifest_id: String,
  version: String,
  provider: String,
  source: String,
  track: Track,
  coverage: Interval,
  observations: List(ObservationHandle),
  limitations: List(String),
) -> json.Json {
  json.object([
    #("schema", json.string("finance_replay_dataset_manifest")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("manifest_id", json.string(manifest_id)),
    #("version", json.string(version)),
    #("provider", json.string(provider)),
    #("source_or_import_provenance", json.string(source)),
    #("track", wire.track_json(track)),
    #("coverage", interval_json(coverage)),
    #("observations", json.array(observations, observation_json)),
    #("limitations", json.array(limitations, json.string)),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

fn membership_json(value: Membership) -> json.Json {
  let Membership(
    listing_id,
    mic,
    track,
    symbol,
    symbol_interval,
    listing_interval,
    security_class,
    status_interval,
    membership_effective,
    membership_end,
    publication_time,
    knowledge_time,
    retrieval_time,
    source_receipt,
    correction_lineage,
    state,
  ) = value
  json.object([
    #("listing_id", json.string(listing_id)),
    #("mic", json.string(mic)),
    #("track", wire.track_json(track)),
    #("symbol", fact.to_json(symbol, json.string)),
    #("symbol_interval", fact.to_json(symbol_interval, open_interval_json)),
    #("listing_interval", open_interval_json(listing_interval)),
    #("security_class", fact.to_json(security_class, json.string)),
    #("status_interval", fact.to_json(status_interval, open_interval_json)),
    #("membership_effective", wire.date_json(membership_effective)),
    #("membership_end", fact.to_json(membership_end, wire.date_json)),
    #("publication_time", fact.to_json(publication_time, wire.instant_json)),
    #("knowledge_time", fact.to_json(knowledge_time, wire.instant_json)),
    #("retrieval_time_unix_ms", wire.instant_json(retrieval_time)),
    #("source_receipt", wire.sha_json(source_receipt)),
    #("correction_lineage", json.array(correction_lineage, wire.sha_json)),
    #("state", membership_state_json(state)),
  ])
}

fn observation_json(value: ObservationHandle) -> json.Json {
  let ObservationHandle(
    observation_id,
    listing_id,
    mic,
    track,
    observation_date,
    observation_time,
    publication_time,
    availability_time,
    knowledge_time,
    retrieval_time,
    source_cutoff,
    correction_vintage,
    correction_lineage,
    session_type,
    calendar_ref,
    status_ref,
    unit,
    currency,
    scale,
    timezone,
    adjustment_basis,
    quantity_semantics,
    entitlement,
    licence,
    state,
    content_hash,
    corporate_action_refs,
    transformation_refs,
  ) = value
  json.object([
    #("observation_id", json.string(observation_id)),
    #("listing_id", json.string(listing_id)),
    #("mic", json.string(mic)),
    #("track", wire.track_json(track)),
    #("observation_date", wire.date_json(observation_date)),
    #("observation_time", fact.to_json(observation_time, wire.instant_json)),
    #("publication_time", fact.to_json(publication_time, wire.instant_json)),
    #("availability_time", fact.to_json(availability_time, wire.instant_json)),
    #("knowledge_time", fact.to_json(knowledge_time, wire.instant_json)),
    #("retrieval_time_unix_ms", wire.instant_json(retrieval_time)),
    #("source_cutoff", fact.to_json(source_cutoff, wire.instant_json)),
    #("correction_vintage", fact.to_json(correction_vintage, json.string)),
    #("correction_lineage", json.array(correction_lineage, wire.sha_json)),
    #("session_type", fact.to_json(session_type, json.string)),
    #("calendar_ref", fact.to_json(calendar_ref, wire.sha_json)),
    #("status_ref", fact.to_json(status_ref, wire.sha_json)),
    #("unit", fact.to_json(unit, json.string)),
    #("currency", fact.to_json(currency, json.string)),
    #("scale", fact.to_json(scale, json.int)),
    #("timezone", fact.to_json(timezone, json.string)),
    #("adjustment_basis", fact.to_json(adjustment_basis, json.string)),
    #("quantity_semantics", fact.to_json(quantity_semantics, json.string)),
    #("entitlement", fact.to_json(entitlement, json.string)),
    #("licence", fact.to_json(licence, json.string)),
    #("state", fact.to_json(state, json.string)),
    #("content_hash", wire.sha_json(content_hash)),
    #("corporate_action_refs", json.array(corporate_action_refs, wire.sha_json)),
    #("transformation_refs", json.array(transformation_refs, wire.sha_json)),
  ])
}

fn universe_envelope_decoder() -> decode.Decoder(#(UniverseManifest, Sha256)) {
  use payload <- decode.field("payload", universe_wrapper_decoder())
  use expected <- decode.field("canonical_content_hash", wire.sha_decoder())
  decode.success(#(payload, expected))
}

fn universe_wrapper_decoder() -> decode.Decoder(UniverseManifest) {
  use content <- decode.field("content", universe_payload_decoder())
  use supplied <- decode.field("content_hash", wire.sha_decoder())
  let #(
    id,
    version,
    track,
    kind,
    as_of,
    coverage,
    source,
    provenance,
    limitations,
    memberships,
  ) = content
  case
    universe(
      id,
      version,
      track,
      kind,
      as_of,
      coverage,
      source,
      provenance,
      limitations,
      memberships,
    )
  {
    Ok(value) if value.digest == supplied -> decode.success(value)
    _ -> decode.failure(placeholder_universe(), "valid universe manifest")
  }
}

fn universe_payload_decoder() -> decode.Decoder(
  #(
    String,
    String,
    Track,
    UniverseDefinitionKind,
    Instant,
    Interval,
    Sha256,
    Provenance,
    List(String),
    List(Membership),
  ),
) {
  use schema <- decode.field("schema", decode.string)
  use version_number <- decode.field("schema_version", decode.int)
  use decision_owner <- decode.field("decision_owner", decode.string)
  use id <- decode.field("manifest_id", decode.string)
  use version <- decode.field("version", decode.string)
  use track <- decode.field("track", wire.track_decoder())
  use kind <- decode.field("definition_kind", definition_kind_decoder())
  use as_of <- decode.field("as_of_time_unix_ms", wire.instant_decoder())
  use coverage <- decode.field("coverage", interval_decoder())
  use source <- decode.field("source_receipt", wire.sha_decoder())
  use provenance <- decode.field("provenance", provenance_decoder())
  use limitations <- decode.field("limitations", decode.list(of: decode.string))
  use memberships <- decode.field(
    "memberships",
    decode.list(of: membership_decoder()),
  )
  case schema, version_number, decision_owner {
    "finance_replay_universe_manifest", 1, "llm" ->
      decode.success(#(
        id,
        version,
        track,
        kind,
        as_of,
        coverage,
        source,
        provenance,
        limitations,
        memberships,
      ))
    _, _, _ -> decode.failure(placeholder_universe_payload(), "universe v1")
  }
}

fn dataset_envelope_decoder() -> decode.Decoder(#(DatasetManifest, Sha256)) {
  use payload <- decode.field("payload", dataset_wrapper_decoder())
  use expected <- decode.field("canonical_content_hash", wire.sha_decoder())
  decode.success(#(payload, expected))
}

fn dataset_wrapper_decoder() -> decode.Decoder(DatasetManifest) {
  use content <- decode.field("content", dataset_payload_decoder())
  use supplied <- decode.field("content_hash", wire.sha_decoder())
  let #(id, version, provider, source, track, coverage, observations, limits) =
    content
  case
    dataset(
      id,
      version,
      provider,
      source,
      track,
      coverage,
      observations,
      limits,
    )
  {
    Ok(value) if value.digest == supplied -> decode.success(value)
    _ -> decode.failure(placeholder_dataset(), "valid dataset manifest")
  }
}

fn dataset_payload_decoder() -> decode.Decoder(
  #(
    String,
    String,
    String,
    String,
    Track,
    Interval,
    List(ObservationHandle),
    List(String),
  ),
) {
  use schema <- decode.field("schema", decode.string)
  use version_number <- decode.field("schema_version", decode.int)
  use decision_owner <- decode.field("decision_owner", decode.string)
  use id <- decode.field("manifest_id", decode.string)
  use version <- decode.field("version", decode.string)
  use provider <- decode.field("provider", decode.string)
  use source <- decode.field("source_or_import_provenance", decode.string)
  use track <- decode.field("track", wire.track_decoder())
  use coverage <- decode.field("coverage", interval_decoder())
  use observations <- decode.field(
    "observations",
    decode.list(of: observation_decoder()),
  )
  use limitations <- decode.field("limitations", decode.list(of: decode.string))
  case schema, version_number, decision_owner {
    "finance_replay_dataset_manifest", 1, "llm" ->
      decode.success(#(
        id,
        version,
        provider,
        source,
        track,
        coverage,
        observations,
        limitations,
      ))
    _, _, _ -> decode.failure(placeholder_dataset_payload(), "dataset v1")
  }
}

fn membership_decoder() -> decode.Decoder(Membership) {
  use listing_id <- decode.field("listing_id", decode.string)
  use mic <- decode.field("mic", decode.string)
  use track <- decode.field("track", wire.track_decoder())
  use symbol <- decode.field("symbol", fact.decoder(decode.string))
  use symbol_interval <- decode.field(
    "symbol_interval",
    fact.decoder(open_interval_decoder()),
  )
  use listing_interval <- decode.field(
    "listing_interval",
    open_interval_decoder(),
  )
  use security_class <- decode.field(
    "security_class",
    fact.decoder(decode.string),
  )
  use status_interval <- decode.field(
    "status_interval",
    fact.decoder(open_interval_decoder()),
  )
  use effective <- decode.field("membership_effective", wire.date_decoder())
  use end <- decode.field("membership_end", fact.decoder(wire.date_decoder()))
  use publication <- decode.field(
    "publication_time",
    fact.decoder(wire.instant_decoder()),
  )
  use knowledge <- decode.field(
    "knowledge_time",
    fact.decoder(wire.instant_decoder()),
  )
  use retrieval <- decode.field(
    "retrieval_time_unix_ms",
    wire.instant_decoder(),
  )
  use source <- decode.field("source_receipt", wire.sha_decoder())
  use lineage <- decode.field(
    "correction_lineage",
    decode.list(of: wire.sha_decoder()),
  )
  use state <- decode.field("state", membership_state_decoder())
  decode.success(Membership(
    listing_id,
    mic,
    track,
    symbol,
    symbol_interval,
    listing_interval,
    security_class,
    status_interval,
    effective,
    end,
    publication,
    knowledge,
    retrieval,
    source,
    lineage,
    state,
  ))
}

fn observation_decoder() -> decode.Decoder(ObservationHandle) {
  use id <- decode.field("observation_id", decode.string)
  use listing_id <- decode.field("listing_id", decode.string)
  use mic <- decode.field("mic", decode.string)
  use track <- decode.field("track", wire.track_decoder())
  use observation_date <- decode.field("observation_date", wire.date_decoder())
  use observation_time <- decode.field(
    "observation_time",
    fact.decoder(wire.instant_decoder()),
  )
  use publication <- decode.field(
    "publication_time",
    fact.decoder(wire.instant_decoder()),
  )
  use availability <- decode.field(
    "availability_time",
    fact.decoder(wire.instant_decoder()),
  )
  use knowledge <- decode.field(
    "knowledge_time",
    fact.decoder(wire.instant_decoder()),
  )
  use retrieval <- decode.field(
    "retrieval_time_unix_ms",
    wire.instant_decoder(),
  )
  use cutoff <- decode.field(
    "source_cutoff",
    fact.decoder(wire.instant_decoder()),
  )
  use vintage <- decode.field("correction_vintage", fact.decoder(decode.string))
  use lineage <- decode.field(
    "correction_lineage",
    decode.list(of: wire.sha_decoder()),
  )
  use session <- decode.field("session_type", fact.decoder(decode.string))
  use calendar <- decode.field("calendar_ref", fact.decoder(wire.sha_decoder()))
  use status <- decode.field("status_ref", fact.decoder(wire.sha_decoder()))
  use unit <- decode.field("unit", fact.decoder(decode.string))
  use currency <- decode.field("currency", fact.decoder(decode.string))
  use scale <- decode.field("scale", fact.decoder(decode.int))
  use timezone <- decode.field("timezone", fact.decoder(decode.string))
  use adjustment <- decode.field(
    "adjustment_basis",
    fact.decoder(decode.string),
  )
  use quantity <- decode.field(
    "quantity_semantics",
    fact.decoder(decode.string),
  )
  use entitlement <- decode.field("entitlement", fact.decoder(decode.string))
  use licence <- decode.field("licence", fact.decoder(decode.string))
  use state <- decode.field("state", fact.decoder(decode.string))
  use content_hash <- decode.field("content_hash", wire.sha_decoder())
  use corporate <- decode.field(
    "corporate_action_refs",
    decode.list(of: wire.sha_decoder()),
  )
  use transformations <- decode.field(
    "transformation_refs",
    decode.list(of: wire.sha_decoder()),
  )
  decode.success(ObservationHandle(
    id,
    listing_id,
    mic,
    track,
    observation_date,
    observation_time,
    publication,
    availability,
    knowledge,
    retrieval,
    cutoff,
    vintage,
    lineage,
    session,
    calendar,
    status,
    unit,
    currency,
    scale,
    timezone,
    adjustment,
    quantity,
    entitlement,
    licence,
    state,
    content_hash,
    corporate,
    transformations,
  ))
}

fn interval_json(value: Interval) -> json.Json {
  let Interval(start, end) = value
  json.object([
    #("start", wire.date_json(start)),
    #("end", wire.date_json(end)),
  ])
}

fn interval_decoder() -> decode.Decoder(Interval) {
  use start <- decode.field("start", wire.date_decoder())
  use end <- decode.field("end", wire.date_decoder())
  case interval(start, end) {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(placeholder_interval(), "valid interval")
  }
}

fn open_interval_json(value: OpenInterval) -> json.Json {
  let OpenInterval(start, end) = value
  json.object([
    #("start", wire.date_json(start)),
    #("end", json.nullable(end, wire.date_json)),
  ])
}

fn open_interval_decoder() -> decode.Decoder(OpenInterval) {
  use start <- decode.field("start", wire.date_decoder())
  use end <- decode.optional_field(
    "end",
    None,
    decode.optional(wire.date_decoder()),
  )
  case open_interval(start, end) {
    Ok(value) -> decode.success(value)
    Error(_) ->
      decode.failure(placeholder_open_interval(), "valid open interval")
  }
}

fn definition_kind_json(value: UniverseDefinitionKind) -> json.Json {
  case value {
    ExactEnumerated -> tagged("exact_enumerated")
    RuleProjection(receipt) ->
      json.object([
        #("kind", json.string("rule_projection")),
        #("receipt", wire.sha_json(receipt)),
      ])
    ImportedDeclaration(source) ->
      json.object([
        #("kind", json.string("imported_declaration")),
        #("source", json.string(source)),
      ])
  }
}

fn definition_kind_decoder() -> decode.Decoder(UniverseDefinitionKind) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "exact_enumerated" -> decode.success(ExactEnumerated)
    "rule_projection" -> {
      use receipt <- decode.field("receipt", wire.sha_decoder())
      decode.success(RuleProjection(receipt))
    }
    "imported_declaration" -> {
      use source <- decode.field("source", decode.string)
      decode.success(ImportedDeclaration(source))
    }
    _ -> decode.failure(ExactEnumerated, "known universe definition kind")
  }
}

fn provenance_json(value: Provenance) -> json.Json {
  case value {
    ProviderObserved -> json.string("provider_observed")
    AuthorityObserved -> json.string("authority_observed")
    CallerDeclared -> json.string("caller_declared")
    Imported -> json.string("imported")
  }
}

fn provenance_decoder() -> decode.Decoder(Provenance) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "provider_observed" -> decode.success(ProviderObserved)
      "authority_observed" -> decode.success(AuthorityObserved)
      "caller_declared" -> decode.success(CallerDeclared)
      "imported" -> decode.success(Imported)
      _ -> decode.failure(Imported, "known manifest provenance")
    }
  })
}

fn membership_state_json(value: MembershipState) -> json.Json {
  case value {
    MembershipKnown -> tagged("known")
    MembershipUnknown(reason) ->
      json.object([
        #("state", json.string("unknown")),
        #("reason", json.string(reason)),
      ])
    MembershipConflicting(alternatives, reason) ->
      json.object([
        #("state", json.string("conflicting")),
        #("alternatives", json.array(alternatives, json.string)),
        #("reason", json.string(reason)),
      ])
  }
}

fn membership_state_decoder() -> decode.Decoder(MembershipState) {
  use state <- decode.field("state", decode.string)
  case state {
    "known" -> decode.success(MembershipKnown)
    "unknown" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(MembershipUnknown(reason))
    }
    "conflicting" -> {
      use alternatives <- decode.field(
        "alternatives",
        decode.list(of: decode.string),
      )
      use reason <- decode.field("reason", decode.string)
      decode.success(MembershipConflicting(alternatives, reason))
    }
    _ ->
      decode.failure(MembershipUnknown("placeholder"), "known membership state")
  }
}

fn tagged(kind: String) -> json.Json {
  json.object([#("kind", json.string(kind))])
}

fn validate_memberships(
  values: List(Membership),
  expected_track: Track,
) -> Result(Nil, ManifestError) {
  case values {
    [] -> Ok(Nil)
    [Membership(listing_id, mic, track, ..), ..rest] -> {
      use _ <- result.try(validate_text(listing_id, "listing_id"))
      use _ <- result.try(validate_text(mic, "mic"))
      case track == expected_track {
        False -> Error(TrackMismatch(expected_track, track))
        True -> validate_memberships(rest, expected_track)
      }
    }
  }
}

fn validate_observations(
  values: List(ObservationHandle),
  expected_track: Track,
  seen: List(String),
) -> Result(Nil, ManifestError) {
  case values {
    [] -> Ok(Nil)
    [ObservationHandle(id, listing_id, mic, track, ..), ..rest] -> {
      use _ <- result.try(validate_text(id, "observation_id"))
      use _ <- result.try(validate_text(listing_id, "listing_id"))
      use _ <- result.try(validate_text(mic, "mic"))
      case track == expected_track, list.contains(seen, id) {
        False, _ -> Error(TrackMismatch(expected_track, track))
        _, True -> Error(DuplicateObservationId(id))
        True, False -> validate_observations(rest, expected_track, [id, ..seen])
      }
    }
  }
}

fn validate_definition_kind(
  value: UniverseDefinitionKind,
) -> Result(Nil, ManifestError) {
  case value {
    ImportedDeclaration(source) -> validate_text(source, "import_source")
    _ -> Ok(Nil)
  }
}

fn validate_entry_count(values: List(a)) -> Result(Nil, ManifestError) {
  let count = list.length(values)
  case count > maximum_manifest_entries {
    True -> Error(TooManyEntries(count, maximum_manifest_entries))
    False -> Ok(Nil)
  }
}

fn validate_text(value: String, field: String) -> Result(Nil, ManifestError) {
  case wire.valid_text(value, 1000) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn validate_texts(
  values: List(String),
  field: String,
) -> Result(Nil, ManifestError) {
  case list.all(values, fn(value) { wire.valid_text(value, 2000) }) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn placeholder_interval() -> Interval {
  let date = wire.placeholder_date()
  Interval(date, date)
}

fn placeholder_open_interval() -> OpenInterval {
  OpenInterval(wire.placeholder_date(), None)
}

fn placeholder_universe_payload() {
  #(
    "placeholder",
    "placeholder",
    finance_track.Us,
    ExactEnumerated,
    wire.placeholder_instant(),
    placeholder_interval(),
    wire.placeholder_sha(),
    Imported,
    [],
    [],
  )
}

fn placeholder_dataset_payload() {
  #(
    "placeholder",
    "placeholder",
    "placeholder",
    "placeholder",
    finance_track.Us,
    placeholder_interval(),
    [],
    [],
  )
}

fn placeholder_universe() -> UniverseManifest {
  let assert Ok(value) =
    universe(
      "placeholder",
      "placeholder",
      finance_track.Us,
      ExactEnumerated,
      wire.placeholder_instant(),
      placeholder_interval(),
      wire.placeholder_sha(),
      Imported,
      [],
      [],
    )
  value
}

fn placeholder_dataset() -> DatasetManifest {
  let assert Ok(value) =
    dataset(
      "placeholder",
      "placeholder",
      "placeholder",
      "placeholder",
      finance_track.Us,
      placeholder_interval(),
      [],
      [],
    )
  value
}

pub fn universe_digest(value: UniverseManifest) -> Sha256 {
  value.digest
}

pub fn universe_memberships(value: UniverseManifest) -> List(Membership) {
  value.memberships
}

pub fn universe_track(value: UniverseManifest) -> Track {
  value.track
}

pub fn dataset_digest(value: DatasetManifest) -> Sha256 {
  value.digest
}

pub fn dataset_observations(value: DatasetManifest) -> List(ObservationHandle) {
  value.observations
}

pub fn dataset_track(value: DatasetManifest) -> Track {
  value.track
}
