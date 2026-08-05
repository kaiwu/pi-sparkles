import finance_core/source.{type SourceRef}
import finance_core/time.{type Date, type Instant}
import finance_listing/listing.{type Key}
import finance_provenance/identity.{type EvidenceId, type Sha256}
import finance_track.{type Track}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type DocumentId {
  DocumentId(value: String)
}

pub opaque type Period {
  Period(start: Option(Date), end: Date)
}

pub opaque type Document {
  Document(
    id: DocumentId,
    track: Track,
    issuer: Key,
    kind: String,
    original_title: String,
    original_text: Option(String),
    language: String,
    published_at: Instant,
    period: Option(Period),
    source: SourceRef,
    evidence_id: EvidenceId,
  )
}

pub type RelationKind {
  Correction
  Replacement
  Supplement
  Translation
  ParallelLanguage
}

pub opaque type Relation {
  Relation(
    kind: RelationKind,
    earlier: DocumentId,
    later: DocumentId,
    evidence_id: EvidenceId,
  )
}

pub opaque type Attachment {
  Attachment(
    document_id: DocumentId,
    name: String,
    media_type: String,
    byte_length: Int,
    content_hash: Sha256,
    evidence_id: EvidenceId,
  )
}

pub type DocumentError {
  InvalidDocumentId
  TrackMismatch
  InvalidKind
  InvalidTitle
  InvalidOriginalText
  InvalidLanguage
  InvalidPeriod
}

pub type RelationError {
  SameDocument
  TrackMismatchBetweenDocuments
  IssuerMismatch
  PublishedBeforeEarlier
  LanguageMustDiffer
}

pub type AttachmentError {
  InvalidAttachmentName
  InvalidMediaType
  NegativeByteLength
}

pub fn document_id(value: String) -> Result(DocumentId, DocumentError) {
  case valid_single_line(value, 240) {
    True -> Ok(DocumentId(value))
    False -> Error(InvalidDocumentId)
  }
}

pub fn document_id_value(value: DocumentId) -> String {
  let DocumentId(value) = value
  value
}

pub fn period(
  start start: Option(Date),
  end end: Date,
) -> Result(Period, DocumentError) {
  case start {
    Some(start_date) ->
      case date_number(start_date) > date_number(end) {
        True -> Error(InvalidPeriod)
        False -> Ok(Period(start, end))
      }
    None -> Ok(Period(start, end))
  }
}

pub fn period_start(value: Period) -> Option(Date) {
  value.start
}

pub fn period_end(value: Period) -> Date {
  value.end
}

pub fn new(
  id id_value: DocumentId,
  track track_value: Track,
  issuer issuer_listing: Key,
  kind kind_value: String,
  original_title title: String,
  original_text text: Option(String),
  language language_value: String,
  published_at published: Instant,
  period document_period: Option(Period),
  source source_ref: SourceRef,
  evidence_id evidence: EvidenceId,
) -> Result(Document, DocumentError) {
  case
    listing.track(issuer_listing) == track_value,
    valid_token(kind_value),
    valid_single_line(title, 1000),
    valid_text(text),
    valid_single_line(language_value, 50)
  {
    False, _, _, _, _ -> Error(TrackMismatch)
    _, False, _, _, _ -> Error(InvalidKind)
    _, _, False, _, _ -> Error(InvalidTitle)
    _, _, _, False, _ -> Error(InvalidOriginalText)
    _, _, _, _, False -> Error(InvalidLanguage)
    True, True, True, True, True ->
      Ok(Document(
        id: id_value,
        track: track_value,
        issuer: issuer_listing,
        kind: kind_value,
        original_title: title,
        original_text: text,
        language: language_value,
        published_at: published,
        period: document_period,
        source: source_ref,
        evidence_id: evidence,
      ))
  }
}

pub fn relation(
  kind kind_value: RelationKind,
  earlier earlier_document: Document,
  later later_document: Document,
  evidence_id evidence: EvidenceId,
) -> Result(Relation, RelationError) {
  case
    earlier_document.id == later_document.id,
    earlier_document.track == later_document.track,
    earlier_document.issuer == later_document.issuer,
    time.unix_milliseconds(later_document.published_at)
    >= time.unix_milliseconds(earlier_document.published_at),
    languages_valid(kind_value, earlier_document, later_document)
  {
    True, _, _, _, _ -> Error(SameDocument)
    _, False, _, _, _ -> Error(TrackMismatchBetweenDocuments)
    _, _, False, _, _ -> Error(IssuerMismatch)
    _, _, _, False, _ -> Error(PublishedBeforeEarlier)
    _, _, _, _, False -> Error(LanguageMustDiffer)
    False, True, True, True, True ->
      Ok(Relation(kind_value, earlier_document.id, later_document.id, evidence))
  }
}

pub fn attachment(
  document_id id_value: DocumentId,
  name name_value: String,
  media_type media_type_value: String,
  byte_length byte_length_value: Int,
  content_hash hash: Sha256,
  evidence_id evidence: EvidenceId,
) -> Result(Attachment, AttachmentError) {
  case
    valid_single_line(name_value, 1000),
    valid_media_type(media_type_value),
    byte_length_value >= 0
  {
    False, _, _ -> Error(InvalidAttachmentName)
    _, False, _ -> Error(InvalidMediaType)
    _, _, False -> Error(NegativeByteLength)
    True, True, True ->
      Ok(Attachment(
        id_value,
        name_value,
        media_type_value,
        byte_length_value,
        hash,
        evidence,
      ))
  }
}

pub fn id(value: Document) -> DocumentId {
  value.id
}

pub fn track(value: Document) -> Track {
  value.track
}

pub fn issuer(value: Document) -> Key {
  value.issuer
}

pub fn kind(value: Document) -> String {
  value.kind
}

pub fn original_title(value: Document) -> String {
  value.original_title
}

pub fn original_text(value: Document) -> Option(String) {
  value.original_text
}

pub fn language(value: Document) -> String {
  value.language
}

pub fn published_at(value: Document) -> Instant {
  value.published_at
}

pub fn reporting_period(value: Document) -> Option(Period) {
  value.period
}

pub fn source(value: Document) -> SourceRef {
  value.source
}

pub fn evidence_id(value: Document) -> EvidenceId {
  value.evidence_id
}

pub fn relation_kind(value: Relation) -> RelationKind {
  value.kind
}

pub fn relation_earlier(value: Relation) -> DocumentId {
  value.earlier
}

pub fn relation_later(value: Relation) -> DocumentId {
  value.later
}

pub fn relation_evidence_id(value: Relation) -> EvidenceId {
  value.evidence_id
}

pub fn attachment_document_id(value: Attachment) -> DocumentId {
  value.document_id
}

pub fn attachment_name(value: Attachment) -> String {
  value.name
}

pub fn attachment_media_type(value: Attachment) -> String {
  value.media_type
}

pub fn attachment_byte_length(value: Attachment) -> Int {
  value.byte_length
}

pub fn attachment_content_hash(value: Attachment) -> Sha256 {
  value.content_hash
}

pub fn attachment_evidence_id(value: Attachment) -> EvidenceId {
  value.evidence_id
}

fn languages_valid(
  kind: RelationKind,
  earlier: Document,
  later: Document,
) -> Bool {
  case kind {
    Translation | ParallelLanguage -> earlier.language != later.language
    Correction | Replacement | Supplement -> True
  }
}

fn valid_token(value: String) -> Bool {
  value != ""
  && string.length(value) <= 100
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  }
}

fn valid_single_line(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn valid_text(value: Option(String)) -> Bool {
  case value {
    None -> True
    Some(text) -> text != ""
  }
}

fn valid_media_type(value: String) -> Bool {
  valid_single_line(value, 200) && string.contains(value, "/")
}

fn date_number(value: Date) -> Int {
  let #(year, month, day) = time.date_parts(value)
  year * 10_000 + month * 100 + day
}
