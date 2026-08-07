import finance_core/time
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/option.{type Option, None}
import pi_sparkles_swing_workbench/domain

pub type CandidateInput {
  CandidateInput(
    workflow_id: String,
    strategy_receipt_hash: identity.Sha256,
    strategy_receipt_payload: String,
    facts: List(domain.FactInput),
    attached_at: time.Instant,
  )
}

pub type PlanInput {
  PlanInput(
    workflow_id: String,
    source_strategy_receipt_hash: identity.Sha256,
    plan_receipt_hash: identity.Sha256,
    plan_payload: String,
    origin: domain.DeclarationOrigin,
    risk_receipt_references: List(identity.Sha256),
    rule_receipt_references: List(identity.Sha256),
    execution_receipt_references: List(identity.Sha256),
    created_at: time.Instant,
  )
}

pub type ReviewInput {
  ReviewInput(
    workflow_id: String,
    record_id: String,
    record_kind: String,
    payload_hash: identity.Sha256,
    payload: String,
    plan_receipt_reference: Option(identity.Sha256),
    evidence_references: List(identity.Sha256),
    observed_at: time.Instant,
  )
}

pub type JournalLinkInput {
  JournalLinkInput(
    workflow_id: String,
    journal_id: String,
    event_id: String,
    canonical_content_hash: identity.Sha256,
    relation: String,
    attached_at: time.Instant,
  )
}

pub type SnapshotInput {
  SnapshotInput(workflow_id: Option(String))
}

pub type PortableExportInput {
  PortableExportInput(
    path: String,
    workflow_id: Option(String),
    maximum_bytes: Int,
  )
}

pub type PortableImportInput {
  PortableImportInput(
    path: String,
    expected_content_hash: identity.Sha256,
    expected_current_revision: Int,
    maximum_bytes: Int,
  )
}

pub fn candidate_decoder() -> decode.Decoder(CandidateInput) {
  use workflow_id <- decode.field("workflowId", decode.string)
  use strategy_hash <- decode.field("strategyReceiptHash", sha_decoder())
  use payload <- decode.field("strategyReceiptPayload", decode.string)
  use facts <- decode.field("facts", decode.list(of: fact_decoder()))
  use attached_at <- decode.field("attachedAtUnixMs", instant_decoder())
  decode.success(CandidateInput(
    workflow_id,
    strategy_hash,
    payload,
    facts,
    attached_at,
  ))
}

pub fn plan_decoder() -> decode.Decoder(PlanInput) {
  use workflow_id <- decode.field("workflowId", decode.string)
  use source_hash <- decode.field("sourceStrategyReceiptHash", sha_decoder())
  use plan_hash <- decode.field("planReceiptHash", sha_decoder())
  use payload <- decode.field("planPayload", decode.string)
  use origin <- decode.field("origin", origin_decoder())
  use risk <- decode.field(
    "riskReceiptReferences",
    decode.list(of: sha_decoder()),
  )
  use rules <- decode.field(
    "ruleReceiptReferences",
    decode.list(of: sha_decoder()),
  )
  use execution <- decode.field(
    "executionReceiptReferences",
    decode.list(of: sha_decoder()),
  )
  use created_at <- decode.field("createdAtUnixMs", instant_decoder())
  decode.success(PlanInput(
    workflow_id,
    source_hash,
    plan_hash,
    payload,
    origin,
    risk,
    rules,
    execution,
    created_at,
  ))
}

pub fn review_decoder() -> decode.Decoder(ReviewInput) {
  use workflow_id <- decode.field("workflowId", decode.string)
  use record_id <- decode.field("recordId", decode.string)
  use record_kind <- decode.field("recordKind", decode.string)
  use payload_hash <- decode.field("payloadHash", sha_decoder())
  use payload <- decode.field("payload", decode.string)
  use plan_reference <- decode.optional_field(
    "planReceiptReference",
    None,
    decode.optional(sha_decoder()),
  )
  use references <- decode.field(
    "evidenceReferences",
    decode.list(of: sha_decoder()),
  )
  use observed_at <- decode.field("observedAtUnixMs", instant_decoder())
  decode.success(ReviewInput(
    workflow_id,
    record_id,
    record_kind,
    payload_hash,
    payload,
    plan_reference,
    references,
    observed_at,
  ))
}

pub fn journal_link_decoder() -> decode.Decoder(JournalLinkInput) {
  use workflow_id <- decode.field("workflowId", decode.string)
  use journal_id <- decode.field("journalId", decode.string)
  use event_id <- decode.field("eventId", decode.string)
  use content_hash <- decode.field("canonicalContentHash", sha_decoder())
  use relation <- decode.field("relation", decode.string)
  use attached_at <- decode.field("attachedAtUnixMs", instant_decoder())
  decode.success(JournalLinkInput(
    workflow_id,
    journal_id,
    event_id,
    content_hash,
    relation,
    attached_at,
  ))
}

pub fn snapshot_decoder() -> decode.Decoder(SnapshotInput) {
  use workflow_id <- decode.optional_field(
    "workflowId",
    None,
    decode.optional(decode.string),
  )
  decode.success(SnapshotInput(workflow_id))
}

pub fn portable_export_decoder() -> decode.Decoder(PortableExportInput) {
  use path <- decode.field("portablePath", decode.string)
  use workflow_id <- decode.optional_field(
    "workflowId",
    None,
    decode.optional(decode.string),
  )
  use maximum_bytes <- decode.field("maximumPortableBytes", decode.int)
  decode.success(PortableExportInput(path, workflow_id, maximum_bytes))
}

pub fn portable_import_decoder() -> decode.Decoder(PortableImportInput) {
  use path <- decode.field("portablePath", decode.string)
  use content_hash <- decode.field("expectedContentHash", sha_decoder())
  use expected_revision <- decode.field("expectedCurrentRevision", decode.int)
  use maximum_bytes <- decode.field("maximumPortableBytes", decode.int)
  decode.success(PortableImportInput(
    path,
    content_hash,
    expected_revision,
    maximum_bytes,
  ))
}

fn fact_decoder() -> decode.Decoder(domain.FactInput) {
  use id <- decode.field("factId", decode.string)
  use role <- decode.field("role", role_decoder())
  use state <- decode.field("state", state_decoder())
  use detail <- decode.field("detail", decode.string)
  use references <- decode.field(
    "receiptReferences",
    decode.list(of: sha_decoder()),
  )
  decode.success(domain.FactInput(id, role, state, detail, references))
}

fn role_decoder() -> decode.Decoder(domain.FactRole) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "required" -> decode.success(domain.Required)
      "optional" -> decode.success(domain.Optional)
      "ranking" -> decode.success(domain.Ranking)
      "context" -> decode.success(domain.Context)
      _ -> decode.failure(domain.Context, "known fact role")
    }
  })
}

fn state_decoder() -> decode.Decoder(domain.InformationState) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "known" -> decode.success(domain.Known)
      "unknown" -> decode.success(domain.Unknown)
      "not_obtained" -> decode.success(domain.NotObtained)
      "conflicting" -> decode.success(domain.Conflicting)
      "decode_failure" -> decode.success(domain.DecodeFailure)
      "declared" -> decode.success(domain.Declared)
      "unsupported" -> decode.success(domain.Unsupported)
      "stale" -> decode.success(domain.Stale)
      "late" -> decode.success(domain.Late)
      _ -> decode.failure(domain.Unknown, "known information state")
    }
  })
}

fn origin_decoder() -> decode.Decoder(domain.DeclarationOrigin) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "llm_authored" -> decode.success(domain.LlmAuthored)
      "user_authored" -> decode.success(domain.UserAuthored)
      _ -> decode.failure(domain.LlmAuthored, "known declaration origin")
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
      Error(_) ->
        decode.failure(placeholder_instant(), "valid Unix milliseconds")
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
