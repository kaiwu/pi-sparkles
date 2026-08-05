import finance_document_attachment
import finance_document_attachment/policy
import finance_market_documents/document
import finance_provenance/identity
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_document_attachment.status()
  |> should.equal(finance_document_attachment.Experimental)
}

pub fn accepted_pdf_is_bounded_hashed_and_constructs_document_metadata_test() {
  let assert Ok(accepted) = policy.validate(standard_policy(), metadata())
  policy.byte_length(accepted) |> should.equal(1024)
  policy.page_count(accepted) |> should.equal(Some(2))
  accepted
  |> policy.content_hash
  |> identity.sha256_value
  |> should.equal(string.repeat("a", 64))

  let assert Ok(document_id) = document.document_id("synthetic-document")
  let assert Ok(attachment) =
    policy.to_document_attachment(
      accepted,
      document_id,
      "公告.pdf",
      evidence_id(),
    )
  document.attachment_media_type(attachment)
  |> should.equal("application/pdf")
}

pub fn malformed_oversized_paged_and_redirected_inputs_fail_closed_test() {
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), byte_length: -1),
  )
  |> should.equal(Error(policy.MalformedMetadata))
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), byte_length: 2049),
  )
  |> should.equal(Error(policy.AttachmentTooLarge(2048, 2049)))
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), page_count: None),
  )
  |> should.equal(Error(policy.MissingPageCount("application/pdf")))
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), page_count: Some(4)),
  )
  |> should.equal(Error(policy.TooManyPages(3, 4)))
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), redirect_count: 2),
  )
  |> should.equal(Error(policy.TooManyRedirects(1, 2)))
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), cross_host_redirect: True),
  )
  |> should.equal(Error(policy.CrossHostRedirectRejected))
}

pub fn cancellation_archive_ocr_media_and_hash_fail_closed_test() {
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), cancelled: True),
  )
  |> should.equal(Error(policy.Cancelled))
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), archive: policy.Archive("zip")),
  )
  |> should.equal(Error(policy.ArchiveUnsupported("zip")))
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), ocr: policy.RequireOcr),
  )
  |> should.equal(Error(policy.OcrUnsupported))
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), media_type: "text/html", page_count: None),
  )
  |> should.equal(Error(policy.UnsupportedMediaType("text/html")))
  policy.validate(
    standard_policy(),
    policy.Metadata(..metadata(), content_hash: None),
  )
  |> should.equal(Error(policy.MissingContentHash))
}

pub fn content_hash_is_part_of_attachment_identity_test() {
  let assert Ok(first) = policy.validate(standard_policy(), metadata())
  let assert Ok(second) =
    policy.validate(
      standard_policy(),
      policy.Metadata(..metadata(), content_hash: Some(hash("b"))),
    )
  should.be_false(policy.content_hash(first) == policy.content_hash(second))
}

fn standard_policy() -> policy.Policy {
  let assert Ok(value) =
    policy.new(
      allowed_media_types: ["application/pdf", "text/plain"],
      paged_media_types: ["application/pdf"],
      maximum_bytes: 2048,
      maximum_pages: 3,
      maximum_redirects: 1,
      allow_cross_host_redirects: False,
    )
  value
}

fn metadata() -> policy.Metadata {
  policy.Metadata(
    media_type: "application/pdf",
    byte_length: 1024,
    page_count: Some(2),
    redirect_count: 0,
    cross_host_redirect: False,
    archive: policy.NotArchive,
    ocr: policy.NoOcr,
    cancelled: False,
    content_hash: Some(hash("a")),
  )
}

fn hash(character: String) -> identity.Sha256 {
  let assert Ok(value) = identity.sha256(string.repeat(character, 64))
  value
}

fn evidence_id() -> identity.EvidenceId {
  identity.evidence_id(hash("e"))
}
