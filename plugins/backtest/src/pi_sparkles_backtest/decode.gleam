import finance_replay/fact.{type Fact}
import gleam/dynamic/decode as decoder

pub type DefinitionInput {
  DefinitionInput(canonical_json: String, content_hash: String)
}

pub type EventInput {
  EventInput(
    canonical_json: String,
    content_hash: String,
    elapsed_milliseconds: Int,
    session_increment: Int,
  )
}

pub type BudgetInput {
  BudgetInput(
    maximum_events: Int,
    maximum_bytes: Int,
    maximum_wall_time_milliseconds: Int,
    maximum_sessions: Int,
  )
}

pub type CancellationInput {
  Continue
  CancelBefore(
    replay_clock: Int,
    cancelled_at_unix_milliseconds: Int,
    cancelled_by: String,
  )
}

pub type RunInput {
  RunInput(
    cadence_policy: String,
    definition: DefinitionInput,
    events: List(EventInput),
    budget: BudgetInput,
    cancellation: CancellationInput,
  )
}

pub type InspectInput {
  InspectInput(run: RunInput, offset: Int, limit: Int, include_payloads: Bool)
}

pub type EnvironmentInput {
  EnvironmentInput(name: String, version: String, semantic: Bool)
}

pub type DependencyInput {
  DependencyInput(receipt_hash: Fact(String), reason: String)
}

pub type ManifestInput {
  ManifestInput(
    manifest_id: String,
    environment_versions: List(EnvironmentInput),
    trial_ids: List(String),
    ordered_source_hashes: List(String),
    transformation_receipts: List(String),
    calendar_receipts: List(String),
    rule_receipts: List(String),
    corporate_action_receipts: List(String),
    cost_receipts: List(String),
    seed_and_random_stream_facts: List(String),
    additional_effect_facts: List(String),
    output_receipt_hashes: List(String),
    checkpoint_hashes: List(String),
    entitlement_limitations: List(String),
    omitted_dependencies: List(DependencyInput),
    unknown_dependencies: List(DependencyInput),
    conflicting_dependencies: List(DependencyInput),
    export_provenance: String,
    privacy_policy: String,
  )
}

pub type ExportInput {
  ExportInput(
    run: RunInput,
    manifest: ManifestInput,
    offset: Int,
    maximum_events: Int,
    maximum_characters: Int,
  )
}

pub fn submit_run() -> decoder.Decoder(RunInput) {
  run_decoder()
}

pub fn inspect_events() -> decoder.Decoder(InspectInput) {
  use run <- decoder.field("run", run_decoder())
  use offset <- decoder.field("offset", decoder.int)
  use limit <- decoder.field("limit", decoder.int)
  use include_payloads <- decoder.field("includePayloads", decoder.bool)
  decoder.success(InspectInput(run, offset, limit, include_payloads))
}

pub fn export_manifest() -> decoder.Decoder(ExportInput) {
  use run <- decoder.field("run", run_decoder())
  use manifest <- decoder.field("manifest", manifest_decoder())
  use offset <- decoder.field("offset", decoder.int)
  use maximum_events <- decoder.field("maximumEvents", decoder.int)
  use maximum_characters <- decoder.field("maximumCharacters", decoder.int)
  decoder.success(ExportInput(
    run,
    manifest,
    offset,
    maximum_events,
    maximum_characters,
  ))
}

fn run_decoder() -> decoder.Decoder(RunInput) {
  use cadence_policy <- decoder.field("cadencePolicy", decoder.string)
  use definition <- decoder.field("definition", definition_decoder())
  use events <- decoder.field("events", decoder.list(of: event_decoder()))
  use budget <- decoder.field("budget", budget_decoder())
  use cancellation <- decoder.field("cancellation", cancellation_decoder())
  decoder.success(RunInput(
    cadence_policy,
    definition,
    events,
    budget,
    cancellation,
  ))
}

fn definition_decoder() -> decoder.Decoder(DefinitionInput) {
  use canonical_json <- decoder.field("canonicalJson", decoder.string)
  use content_hash <- decoder.field("contentHash", decoder.string)
  decoder.success(DefinitionInput(canonical_json, content_hash))
}

fn event_decoder() -> decoder.Decoder(EventInput) {
  use canonical_json <- decoder.field("canonicalJson", decoder.string)
  use content_hash <- decoder.field("contentHash", decoder.string)
  use elapsed <- decoder.field("elapsedMilliseconds", decoder.int)
  use sessions <- decoder.field("sessionIncrement", decoder.int)
  decoder.success(EventInput(canonical_json, content_hash, elapsed, sessions))
}

fn budget_decoder() -> decoder.Decoder(BudgetInput) {
  use events <- decoder.field("maximumEvents", decoder.int)
  use bytes <- decoder.field("maximumBytes", decoder.int)
  use wall <- decoder.field("maximumWallTimeMilliseconds", decoder.int)
  use sessions <- decoder.field("maximumSessions", decoder.int)
  decoder.success(BudgetInput(events, bytes, wall, sessions))
}

fn cancellation_decoder() -> decoder.Decoder(CancellationInput) {
  use kind <- decoder.field("kind", decoder.string)
  case kind {
    "continue" -> decoder.success(Continue)
    "cancel_before" -> {
      use clock <- decoder.field("replayClock", decoder.int)
      use at <- decoder.field("cancelledAtUnixMilliseconds", decoder.int)
      use by <- decoder.field("cancelledBy", decoder.string)
      decoder.success(CancelBefore(clock, at, by))
    }
    _ -> decoder.failure(Continue, "continue or cancel_before")
  }
}

fn manifest_decoder() -> decoder.Decoder(ManifestInput) {
  use manifest_id <- decoder.field("manifestId", decoder.string)
  use environments <- decoder.field(
    "environmentVersions",
    decoder.list(of: environment_decoder()),
  )
  use trials <- decoder.field("trialIds", decoder.list(of: decoder.string))
  use sources <- decoder.field(
    "orderedSourceHashes",
    decoder.list(of: decoder.string),
  )
  use transformations <- decoder.field(
    "transformationReceipts",
    decoder.list(of: decoder.string),
  )
  use calendars <- decoder.field(
    "calendarReceipts",
    decoder.list(of: decoder.string),
  )
  use rules <- decoder.field("ruleReceipts", decoder.list(of: decoder.string))
  use actions <- decoder.field(
    "corporateActionReceipts",
    decoder.list(of: decoder.string),
  )
  use costs <- decoder.field("costReceipts", decoder.list(of: decoder.string))
  use seeds <- decoder.field(
    "seedAndRandomStreamFacts",
    decoder.list(of: decoder.string),
  )
  use effects <- decoder.field(
    "additionalEffectFacts",
    decoder.list(of: decoder.string),
  )
  use outputs <- decoder.field(
    "outputReceiptHashes",
    decoder.list(of: decoder.string),
  )
  use checkpoints <- decoder.field(
    "checkpointHashes",
    decoder.list(of: decoder.string),
  )
  use limitations <- decoder.field(
    "entitlementLimitations",
    decoder.list(of: decoder.string),
  )
  use omitted <- decoder.field(
    "omittedDependencies",
    decoder.list(of: dependency_decoder()),
  )
  use unknown <- decoder.field(
    "unknownDependencies",
    decoder.list(of: dependency_decoder()),
  )
  use conflicting <- decoder.field(
    "conflictingDependencies",
    decoder.list(of: dependency_decoder()),
  )
  use provenance <- decoder.field("exportProvenance", decoder.string)
  use privacy <- decoder.field("privacyPolicy", decoder.string)
  decoder.success(ManifestInput(
    manifest_id,
    environments,
    trials,
    sources,
    transformations,
    calendars,
    rules,
    actions,
    costs,
    seeds,
    effects,
    outputs,
    checkpoints,
    limitations,
    omitted,
    unknown,
    conflicting,
    provenance,
    privacy,
  ))
}

fn environment_decoder() -> decoder.Decoder(EnvironmentInput) {
  use name <- decoder.field("name", decoder.string)
  use version <- decoder.field("version", decoder.string)
  use semantic <- decoder.field("semantic", decoder.bool)
  decoder.success(EnvironmentInput(name, version, semantic))
}

fn dependency_decoder() -> decoder.Decoder(DependencyInput) {
  use receipt <- decoder.field("receiptHash", fact.decoder(decoder.string))
  use reason <- decoder.field("reason", decoder.string)
  decoder.success(DependencyInput(receipt, reason))
}
