import finance_core/decimal
import finance_core/time
import finance_journal/comparison
import finance_journal/event
import finance_journal/information
import finance_journal/metric
import finance_provenance/identity
import finance_track
import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import pi_sparkles_trade_journal/domain

pub type EntryInput {
  EntryInput(
    path: String,
    expected_revision: Int,
    maximum_journal_bytes: Int,
    entry: domain.EntryData,
  )
}

pub type SearchInput {
  SearchInput(
    path: String,
    expected_journal_id: Option(String),
    workflow_id: Option(String),
    kinds: List(event.EventKind),
    attribution_names: List(String),
    privacy_states: List(event.Privacy),
    include_superseded: Bool,
    include_private_payloads: Bool,
    maximum_events: Int,
    maximum_journal_bytes: Int,
  )
}

pub type ExportInput {
  ExportInput(
    path: String,
    expected_journal_id: Option(String),
    include_private: Bool,
    include_review_visible: Bool,
    include_exportable: Bool,
    include_superseded: Bool,
    maximum_events: Int,
    maximum_journal_bytes: Int,
  )
}

pub type ImportInput {
  ImportInput(
    path: String,
    expected_revision: Int,
    jsonl: String,
    maximum_import_events: Int,
    maximum_journal_bytes: Int,
  )
}

pub type ContextInput {
  ContextInput(
    path: String,
    expected_journal_id: Option(String),
    include_superseded: Bool,
    maximum_journal_bytes: Int,
  )
}

pub type ComparisonInput {
  ComparisonInput(
    instruction_receipt: identity.Sha256,
    plan_receipt: identity.Sha256,
    observation_receipts: List(identity.Sha256),
    missing_policy: String,
    conflict_policy: String,
    fields: List(comparison.FieldRequest),
  )
}

pub type MetricInput {
  MetricInput(
    instruction_receipt: identity.Sha256,
    currency: String,
    scale: Int,
    rounding: decimal.RoundingMode,
    fills: List(metric.FillInput),
    costs: List(metric.CostInput),
  )
}

pub fn entry_decoder() -> decode.Decoder(EntryInput) {
  use path <- decode.field("journalPath", decode.string)
  use expected_revision <- decode.field("expectedRevision", decode.int)
  use maximum_bytes <- decode.field("maximumJournalBytes", decode.int)
  use journal_id <- decode.field("journalId", decode.string)
  use event_id <- decode.field("eventId", decode.string)
  use kind <- decode.field("eventKind", decode.string)
  use identity_kind <- decode.field("identityScope", decode.string)
  use track <- optional_field("track", track_decoder())
  use listing_id <- optional_field("listingId", decode.string)
  use mic <- optional_field("mic", decode.string)
  use symbol <- optional_field("symbol", decode.string)
  use workflow_id <- optional_field("workflowId", decode.string)
  use position_id <- optional_field("positionId", decode.string)
  use review_id <- optional_field("reviewId", decode.string)
  use attribution_kind <- decode.field("attributionKind", decode.string)
  use attribution_id <- optional_field("authorOrSourceId", decode.string)
  use attribution_receipt <- optional_field("attributionReceipt", sha_decoder())
  use result_receipt <- optional_field("resultReceipt", sha_decoder())
  use context_receipt <- optional_field("contextReceipt", sha_decoder())
  use stage <- optional_field("stage", decode.string)
  use payload <- decode.field("payload", decode.string)
  use occurrence <- optional_field("occurrenceTimeUnixMs", instant_decoder())
  use recording <- decode.field("recordingTimeUnixMs", instant_decoder())
  use timezone <- optional_field("timezone", decode.string)
  use privacy <- decode.field("privacy", privacy_decoder())
  use references <- decode.field(
    "references",
    decode.list(of: reference_decoder()),
  )
  use supersedes <- optional_field("supersedes", decode.string)
  use import_provenance <- optional_field("importProvenance", decode.string)
  use idempotency_key <- decode.field("idempotencyKey", decode.string)
  decode.success(EntryInput(
    path,
    expected_revision,
    maximum_bytes,
    domain.EntryData(
      journal_id,
      event_id,
      kind,
      domain.IdentityInput(identity_kind, track, listing_id, mic, symbol),
      workflow_id,
      position_id,
      review_id,
      domain.AttributionInput(
        attribution_kind,
        attribution_id,
        attribution_receipt,
        result_receipt,
        context_receipt,
      ),
      stage,
      payload,
      occurrence,
      recording,
      timezone,
      privacy,
      references,
      supersedes,
      import_provenance,
      idempotency_key,
    ),
  ))
}

pub fn search_decoder() -> decode.Decoder(SearchInput) {
  use path <- decode.field("journalPath", decode.string)
  use journal_id <- optional_field("journalId", decode.string)
  use workflow_id <- optional_field("workflowId", decode.string)
  use kinds <- decode.field("eventKinds", decode.list(of: kind_decoder()))
  use attributions <- decode.field(
    "attributionKinds",
    decode.list(of: decode.string),
  )
  use privacy <- decode.field(
    "privacyClassifications",
    decode.list(of: privacy_decoder()),
  )
  use include_superseded <- decode.field("includeSuperseded", decode.bool)
  use include_private <- decode.field("includePrivatePayloads", decode.bool)
  use maximum_events <- decode.field("maximumEvents", decode.int)
  use maximum_bytes <- decode.field("maximumJournalBytes", decode.int)
  decode.success(SearchInput(
    path,
    journal_id,
    workflow_id,
    kinds,
    attributions,
    privacy,
    include_superseded,
    include_private,
    maximum_events,
    maximum_bytes,
  ))
}

pub fn export_decoder() -> decode.Decoder(ExportInput) {
  use path <- decode.field("journalPath", decode.string)
  use journal_id <- optional_field("journalId", decode.string)
  use include_private <- decode.field("includePrivate", decode.bool)
  use include_review <- decode.field("includeReviewVisible", decode.bool)
  use include_exportable <- decode.field("includeExportable", decode.bool)
  use include_superseded <- decode.field("includeSuperseded", decode.bool)
  use maximum_events <- decode.field("maximumEvents", decode.int)
  use maximum_bytes <- decode.field("maximumJournalBytes", decode.int)
  decode.success(ExportInput(
    path,
    journal_id,
    include_private,
    include_review,
    include_exportable,
    include_superseded,
    maximum_events,
    maximum_bytes,
  ))
}

pub fn import_decoder() -> decode.Decoder(ImportInput) {
  use path <- decode.field("journalPath", decode.string)
  use expected_revision <- decode.field("expectedRevision", decode.int)
  use jsonl <- decode.field("jsonl", decode.string)
  use maximum_events <- decode.field("maximumImportEvents", decode.int)
  use maximum_bytes <- decode.field("maximumJournalBytes", decode.int)
  decode.success(ImportInput(
    path,
    expected_revision,
    jsonl,
    maximum_events,
    maximum_bytes,
  ))
}

pub fn context_decoder() -> decode.Decoder(ContextInput) {
  use path <- decode.field("journalPath", decode.string)
  use journal_id <- optional_field("journalId", decode.string)
  use include_superseded <- decode.field("includeSuperseded", decode.bool)
  use maximum_bytes <- decode.field("maximumJournalBytes", decode.int)
  decode.success(ContextInput(
    path,
    journal_id,
    include_superseded,
    maximum_bytes,
  ))
}

pub fn comparison_decoder() -> decode.Decoder(ComparisonInput) {
  use instruction <- decode.field("instructionReceipt", sha_decoder())
  use plan <- decode.field("planReceipt", sha_decoder())
  use observations <- decode.field(
    "observationReceipts",
    decode.list(of: sha_decoder()),
  )
  use missing_policy <- decode.field("missingPolicy", decode.string)
  use conflict_policy <- decode.field("conflictPolicy", decode.string)
  use fields <- decode.field(
    "fields",
    decode.list(of: comparison_field_decoder()),
  )
  decode.success(ComparisonInput(
    instruction,
    plan,
    observations,
    missing_policy,
    conflict_policy,
    fields,
  ))
}

pub fn metric_decoder() -> decode.Decoder(MetricInput) {
  use instruction <- decode.field("instructionReceipt", sha_decoder())
  use currency <- decode.field("currency", decode.string)
  use scale <- decode.field("scale", decode.int)
  use rounding <- decode.field("rounding", rounding_decoder())
  use fills <- decode.field("fills", decode.list(of: fill_decoder()))
  use costs <- decode.field("costs", decode.list(of: cost_decoder()))
  decode.success(MetricInput(
    instruction,
    currency,
    scale,
    rounding,
    fills,
    costs,
  ))
}

fn optional_field(
  name: String,
  decoder: decode.Decoder(a),
  next: fn(Option(a)) -> decode.Decoder(b),
) -> decode.Decoder(b) {
  decode.optional_field(name, None, decode.optional(decoder), next)
}

fn reference_decoder() -> decode.Decoder(event.Reference) {
  use kind <- decode.field("kind", decode.string)
  use hash <- decode.field("hash", sha_decoder())
  decode.success(event.Reference(kind, hash))
}

fn comparison_field_decoder() -> decode.Decoder(comparison.FieldRequest) {
  use field <- decode.field("field", decode.string)
  use planned <- decode.field("planned", information_decoder())
  use observed <- decode.field("observed", information_decoder())
  use mode <- decode.field("mode", comparison_mode_decoder())
  use unit <- decode.field("unit", decode.string)
  decode.success(comparison.FieldRequest(field, planned, observed, mode, unit))
}

fn comparison_mode_decoder() -> decode.Decoder(comparison.Mode) {
  use kind <- decode.field("kind", decode.string)
  use scale <- decode.optional_field("scale", None, decode.optional(decode.int))
  use rounding <- decode.optional_field(
    "rounding",
    None,
    decode.optional(rounding_decoder()),
  )
  case kind, scale, rounding {
    "exact_equality", None, None -> decode.success(comparison.ExactEquality)
    "decimal_delta", Some(scale), Some(rounding) ->
      decode.success(comparison.DecimalDelta(scale, rounding))
    _, _, _ ->
      decode.failure(comparison.ExactEquality, "valid comparison mode shape")
  }
}

fn information_decoder() -> decode.Decoder(information.Information(String)) {
  use state <- decode.field("state", decode.string)
  use value <- decode.optional_field(
    "value",
    None,
    decode.optional(decode.string),
  )
  use reason <- decode.optional_field(
    "reason",
    None,
    decode.optional(decode.string),
  )
  use alternatives <- decode.optional_field(
    "alternatives",
    [],
    decode.list(of: decode.string),
  )
  use raw <- decode.optional_field("raw", None, decode.optional(decode.string))
  case state, value, reason, alternatives, raw {
    "known", Some(value), None, [], None ->
      decode.success(information.Known(value))
    "unknown", None, Some(reason), [], None ->
      decode.success(information.Unknown(reason))
    "not_asked", None, None, [], None -> decode.success(information.NotAsked)
    "not_obtained", None, Some(reason), [], None ->
      decode.success(information.NotObtained(reason))
    "declined", None, None, [], None -> decode.success(information.Declined)
    "not_applicable", None, Some(reason), [], None ->
      decode.success(information.NotApplicable(reason))
    "conflicting", None, Some(reason), alternatives, None ->
      decode.success(information.Conflicting(alternatives, reason))
    "decode_failure", None, Some(reason), [], Some(raw) ->
      decode.success(information.DecodeFailure(raw, reason))
    "redacted", None, Some(reason), [], None ->
      decode.success(information.Redacted(reason))
    "superseded", None, Some(id), [], None ->
      decode.success(information.Superseded(id))
    _, _, _, _, _ ->
      decode.failure(information.NotAsked, "valid information-state shape")
  }
}

fn fill_decoder() -> decode.Decoder(metric.FillInput) {
  use id <- decode.field("fillId", decode.string)
  use role <- decode.field("role", cash_flow_role_decoder())
  use quantity <- decode.field("quantityLexeme", decode.string)
  use price <- decode.field("priceLexeme", decode.string)
  use source <- decode.field("sourceReceipt", sha_decoder())
  decode.success(metric.FillInput(id, role, quantity, price, source))
}

fn cost_decoder() -> decode.Decoder(metric.CostInput) {
  use id <- decode.field("costId", decode.string)
  use amount <- decode.field("amountLexeme", decode.string)
  use source <- decode.field("sourceReceipt", sha_decoder())
  decode.success(metric.CostInput(id, amount, source))
}

fn cash_flow_role_decoder() -> decode.Decoder(metric.CashFlowRole) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "entry" -> decode.success(metric.Entry)
      "exit" -> decode.success(metric.Exit)
      _ -> decode.failure(metric.Entry, "entry or exit")
    }
  })
}

fn rounding_decoder() -> decode.Decoder(decimal.RoundingMode) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "toward_zero" -> decode.success(decimal.TowardZero)
      "away_from_zero" -> decode.success(decimal.AwayFromZero)
      "half_up" -> decode.success(decimal.HalfUp)
      "half_even" -> decode.success(decimal.HalfEven)
      _ -> decode.failure(decimal.HalfEven, "known decimal rounding mode")
    }
  })
}

fn kind_decoder() -> decode.Decoder(event.EventKind) {
  decode.string
  |> decode.then(fn(value) {
    case event.kind_from_name(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(event.Declaration, "known journal event kind")
    }
  })
}

fn privacy_decoder() -> decode.Decoder(event.Privacy) {
  decode.string
  |> decode.then(fn(value) {
    case event.privacy_from_name(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(event.Private, "known privacy classification")
    }
  })
}

fn track_decoder() -> decode.Decoder(finance_track.Track) {
  decode.string
  |> decode.then(fn(value) {
    case finance_track.from_name(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(finance_track.Us, "cn, hk, or us")
    }
  })
}

fn sha_decoder() -> decode.Decoder(identity.Sha256) {
  decode.string
  |> decode.then(fn(value) {
    case identity.sha256(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder_sha(), "SHA-256 hex")
    }
  })
}

fn instant_decoder() -> decode.Decoder(time.Instant) {
  decode.int
  |> decode.then(fn(value) {
    case time.instant(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder_instant(), "Unix milliseconds")
    }
  })
}

fn placeholder_sha() -> identity.Sha256 {
  let assert Ok(value) =
    identity.sha256(
      "0000000000000000000000000000000000000000000000000000000000000000",
    )
  value
}

fn placeholder_instant() -> time.Instant {
  let assert Ok(value) = time.instant(0)
  value
}
