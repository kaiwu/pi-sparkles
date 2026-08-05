import finance_market_documents/document
import finance_provenance/identity.{type EvidenceId, type Sha256}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type Policy {
  Policy(
    allowed_media_types: List(String),
    paged_media_types: List(String),
    maximum_bytes: Int,
    maximum_pages: Int,
    maximum_redirects: Int,
    allow_cross_host_redirects: Bool,
  )
}

pub type Archive {
  NotArchive
  Archive(format: String)
}

pub type Ocr {
  NoOcr
  RequireOcr
}

/// Metadata produced by a bounded transport and media inspector.
///
/// The policy is pure: the effect shell owns streaming cancellation, hashing,
/// redirect observation, and page inspection, then submits these facts here.
pub type Metadata {
  Metadata(
    media_type: String,
    byte_length: Int,
    page_count: Option(Int),
    redirect_count: Int,
    cross_host_redirect: Bool,
    archive: Archive,
    ocr: Ocr,
    cancelled: Bool,
    content_hash: Option(Sha256),
  )
}

pub opaque type Accepted {
  Accepted(
    media_type: String,
    byte_length: Int,
    page_count: Option(Int),
    redirect_count: Int,
    content_hash: Sha256,
  )
}

pub type PolicyError {
  EmptyMediaAllowlist
  InvalidMediaType(value: String)
  DuplicateMediaType(value: String)
  PagedMediaNotAllowed(value: String)
  InvalidMaximumBytes
  InvalidMaximumPages
  InvalidMaximumRedirects
}

pub type ValidationError {
  Cancelled
  MalformedMetadata
  UnsupportedMediaType(received: String)
  AttachmentTooLarge(maximum: Int, received: Int)
  MissingPageCount(media_type: String)
  TooManyPages(maximum: Int, received: Int)
  TooManyRedirects(maximum: Int, received: Int)
  CrossHostRedirectRejected
  ArchiveUnsupported(format: String)
  OcrUnsupported
  MissingContentHash
}

pub fn new(
  allowed_media_types allowed: List(String),
  paged_media_types paged: List(String),
  maximum_bytes maximum_bytes_value: Int,
  maximum_pages maximum_pages_value: Int,
  maximum_redirects maximum_redirects_value: Int,
  allow_cross_host_redirects allow_cross_host: Bool,
) -> Result(Policy, PolicyError) {
  case
    allowed,
    first_invalid_media(allowed),
    first_duplicate(allowed),
    first_invalid_media(paged),
    first_duplicate(paged),
    first_not_allowed(paged, allowed),
    maximum_bytes_value > 0,
    maximum_pages_value > 0,
    maximum_redirects_value >= 0
  {
    [], _, _, _, _, _, _, _, _ -> Error(EmptyMediaAllowlist)
    _, Some(value), _, _, _, _, _, _, _ -> Error(InvalidMediaType(value))
    _, _, Some(value), _, _, _, _, _, _ -> Error(DuplicateMediaType(value))
    _, _, _, Some(value), _, _, _, _, _ -> Error(InvalidMediaType(value))
    _, _, _, _, Some(value), _, _, _, _ -> Error(DuplicateMediaType(value))
    _, _, _, _, _, Some(value), _, _, _ -> Error(PagedMediaNotAllowed(value))
    _, _, _, _, _, _, False, _, _ -> Error(InvalidMaximumBytes)
    _, _, _, _, _, _, _, False, _ -> Error(InvalidMaximumPages)
    _, _, _, _, _, _, _, _, False -> Error(InvalidMaximumRedirects)
    [_, ..], None, None, None, None, None, True, True, True ->
      Ok(Policy(
        allowed,
        paged,
        maximum_bytes_value,
        maximum_pages_value,
        maximum_redirects_value,
        allow_cross_host,
      ))
  }
}

pub fn validate(
  policy policy_value: Policy,
  metadata metadata_value: Metadata,
) -> Result(Accepted, ValidationError) {
  case metadata_value.cancelled {
    True -> Error(Cancelled)
    False -> validate_not_cancelled(policy_value, metadata_value)
  }
}

pub fn to_document_attachment(
  accepted accepted_value: Accepted,
  document_id document_id_value: document.DocumentId,
  name name_value: String,
  evidence_id evidence: EvidenceId,
) -> Result(document.Attachment, document.AttachmentError) {
  document.attachment(
    document_id: document_id_value,
    name: name_value,
    media_type: accepted_value.media_type,
    byte_length: accepted_value.byte_length,
    content_hash: accepted_value.content_hash,
    evidence_id: evidence,
  )
}

pub fn media_type(value: Accepted) -> String {
  value.media_type
}

pub fn byte_length(value: Accepted) -> Int {
  value.byte_length
}

pub fn page_count(value: Accepted) -> Option(Int) {
  value.page_count
}

pub fn redirect_count(value: Accepted) -> Int {
  value.redirect_count
}

pub fn content_hash(value: Accepted) -> Sha256 {
  value.content_hash
}

fn validate_not_cancelled(
  policy: Policy,
  metadata: Metadata,
) -> Result(Accepted, ValidationError) {
  case
    valid_metadata_shape(metadata),
    list.contains(policy.allowed_media_types, metadata.media_type),
    metadata.byte_length <= policy.maximum_bytes,
    pages_valid(policy, metadata),
    metadata.redirect_count <= policy.maximum_redirects,
    !metadata.cross_host_redirect || policy.allow_cross_host_redirects,
    metadata.archive,
    metadata.ocr,
    metadata.content_hash
  {
    False, _, _, _, _, _, _, _, _ -> Error(MalformedMetadata)
    _, False, _, _, _, _, _, _, _ ->
      Error(UnsupportedMediaType(metadata.media_type))
    _, _, False, _, _, _, _, _, _ ->
      Error(AttachmentTooLarge(policy.maximum_bytes, metadata.byte_length))
    _, _, _, MissingPages, _, _, _, _, _ ->
      Error(MissingPageCount(metadata.media_type))
    _, _, _, ExcessPages(received), _, _, _, _, _ ->
      Error(TooManyPages(policy.maximum_pages, received))
    _, _, _, PagesValid, False, _, _, _, _ ->
      Error(TooManyRedirects(policy.maximum_redirects, metadata.redirect_count))
    _, _, _, PagesValid, True, False, _, _, _ ->
      Error(CrossHostRedirectRejected)
    _, _, _, PagesValid, True, True, Archive(format), _, _ ->
      Error(ArchiveUnsupported(format))
    _, _, _, PagesValid, True, True, NotArchive, RequireOcr, _ ->
      Error(OcrUnsupported)
    _, _, _, PagesValid, True, True, NotArchive, NoOcr, None ->
      Error(MissingContentHash)
    True, True, True, PagesValid, True, True, NotArchive, NoOcr, Some(hash) ->
      Ok(Accepted(
        metadata.media_type,
        metadata.byte_length,
        metadata.page_count,
        metadata.redirect_count,
        hash,
      ))
  }
}

type PageValidation {
  PagesValid
  MissingPages
  ExcessPages(received: Int)
}

fn pages_valid(policy: Policy, metadata: Metadata) -> PageValidation {
  case
    list.contains(policy.paged_media_types, metadata.media_type),
    metadata.page_count
  {
    True, None -> MissingPages
    _, Some(received) if received > policy.maximum_pages -> ExcessPages(received)
    _, _ -> PagesValid
  }
}

fn valid_metadata_shape(value: Metadata) -> Bool {
  valid_media_type(value.media_type)
  && value.byte_length >= 0
  && value.redirect_count >= 0
  && case value.page_count {
    None -> True
    Some(pages) -> pages >= 0
  }
  && case value.archive {
    NotArchive -> True
    Archive(format) -> valid_name(format)
  }
}

fn first_invalid_media(values: List(String)) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case valid_media_type(first) {
        True -> first_invalid_media(rest)
        False -> Some(first)
      }
  }
}

fn first_duplicate(values: List(String)) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> Some(first)
        False -> first_duplicate(rest)
      }
  }
}

fn first_not_allowed(
  values: List(String),
  allowed: List(String),
) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case list.contains(allowed, first) {
        True -> first_not_allowed(rest, allowed)
        False -> Some(first)
      }
  }
}

fn valid_media_type(value: String) -> Bool {
  valid_name(value) && string.contains(value, "/")
}

fn valid_name(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 200
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}
