import finance_thesis as thesis
import gleam/dynamic/decode
import gleam/option.{type Option, None}

pub type AppendInput {
  AppendInput(
    path: String,
    expected_revision: Int,
    maximum_bytes: Int,
    draft: thesis.Draft,
  )
}

pub type InspectInput {
  InspectInput(
    path: String,
    maximum_bytes: Int,
    thesis_id: String,
    version: Option(Int),
    include_history: Bool,
    include_private: Bool,
    maximum_history: Int,
  )
}

pub type CompareInput {
  CompareInput(
    path: String,
    maximum_bytes: Int,
    thesis_id: String,
    left_version: Int,
    right_version: Int,
    include_private: Bool,
  )
}

pub type ExportInput {
  ExportInput(
    path: String,
    maximum_bytes: Int,
    include_private: Bool,
    include_review_visible: Bool,
    include_exportable: Bool,
    maximum_events: Int,
  )
}

pub fn append_decoder() -> decode.Decoder(AppendInput) {
  use path <- decode.field("path", decode.string)
  use revision <- decode.field("expectedRevision", decode.int)
  use maximum <- decode.field("maximumBytes", decode.int)
  use journal <- decode.field("journalId", decode.string)
  use thesis_id <- decode.field("thesisId", decode.string)
  use event <- decode.field("eventId", decode.string)
  use kind <- decode.field("kind", decode.string)
  use version <- decode.field("version", decode.int)
  use parent <- optional_string("parentEventId")
  use author_kind <- decode.field("authorKind", decode.string)
  use author <- decode.field("authorId", decode.string)
  use recorded <- decode.field("recordedAt", decode.string)
  use subject <- decode.field("subject", subject_decoder())
  use horizon <- decode.field("horizon", decode.string)
  use claims <- decode.field("claims", decode.list(claim_decoder()))
  use privacy <- decode.field("privacy", decode.string)
  use reason <- optional_string("reason")
  use key <- decode.field("idempotencyKey", decode.string)
  decode.success(AppendInput(
    path,
    revision,
    maximum,
    thesis.Draft(
      journal,
      thesis_id,
      event,
      kind,
      version,
      parent,
      author_kind,
      author,
      recorded,
      subject,
      horizon,
      claims,
      privacy,
      reason,
      key,
    ),
  ))
}

pub fn inspect_decoder() -> decode.Decoder(InspectInput) {
  use path <- decode.field("path", decode.string)
  use maximum <- decode.field("maximumBytes", decode.int)
  use thesis_id <- decode.field("thesisId", decode.string)
  use version <- decode.optional_field(
    "version",
    None,
    decode.optional(decode.int),
  )
  use history <- decode.field("includeHistory", decode.bool)
  use private <- decode.field("includePrivate", decode.bool)
  use max_history <- decode.field("maximumHistory", decode.int)
  decode.success(InspectInput(
    path,
    maximum,
    thesis_id,
    version,
    history,
    private,
    max_history,
  ))
}

pub fn compare_decoder() -> decode.Decoder(CompareInput) {
  use path <- decode.field("path", decode.string)
  use maximum <- decode.field("maximumBytes", decode.int)
  use thesis_id <- decode.field("thesisId", decode.string)
  use left <- decode.field("leftVersion", decode.int)
  use right <- decode.field("rightVersion", decode.int)
  use private <- decode.field("includePrivate", decode.bool)
  decode.success(CompareInput(path, maximum, thesis_id, left, right, private))
}

pub fn export_decoder() -> decode.Decoder(ExportInput) {
  use path <- decode.field("path", decode.string)
  use maximum_bytes <- decode.field("maximumBytes", decode.int)
  use private <- decode.field("includePrivate", decode.bool)
  use review <- decode.field("includeReviewVisible", decode.bool)
  use exportable <- decode.field("includeExportable", decode.bool)
  use maximum_events <- decode.field("maximumEvents", decode.int)
  decode.success(ExportInput(
    path,
    maximum_bytes,
    private,
    review,
    exportable,
    maximum_events,
  ))
}

fn subject_decoder() -> decode.Decoder(thesis.Subject) {
  use track <- decode.field("track", decode.string)
  use issuer <- decode.field("issuerId", decode.string)
  use listing <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use symbol <- decode.field("symbol", decode.string)
  decode.success(thesis.Subject(track, issuer, listing, mic, symbol))
}

fn evidence_decoder() -> decode.Decoder(thesis.EvidenceLink) {
  use id <- decode.field("linkId", decode.string)
  use relation <- decode.field("relation", decode.string)
  use receipt <- decode.field("receiptSha256", decode.string)
  use state <- decode.field("sourceState", decode.string)
  use corrected <- optional_string("correctedBy")
  decode.success(thesis.EvidenceLink(id, relation, receipt, state, corrected))
}

fn claim_decoder() -> decode.Decoder(thesis.Claim) {
  use id <- decode.field("claimId", decode.string)
  use text <- decode.field("text", decode.string)
  use state <- decode.field("state", decode.string)
  use evidence <- decode.field("evidence", decode.list(evidence_decoder()))
  decode.success(thesis.Claim(id, text, state, evidence))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}
