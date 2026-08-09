import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type OmissionInput {
  OmissionInput(
    listing_id: String,
    observation_date: String,
    state: String,
    evidence_reference: Option(String),
  )
}

pub type DatasetInput {
  DatasetInput(
    manifest_json: String,
    manifest_hash: String,
    omissions: List(OmissionInput),
    receipt_roots: List(String),
  )
}

pub type InspectInput {
  InspectInput(dataset: DatasetInput)
}

pub type DrillInput {
  DrillInput(
    dataset: DatasetInput,
    listing_id: String,
    observation_date: String,
    offset: Int,
    limit: Int,
  )
}

pub type VintagesInput {
  VintagesInput(
    dataset: DatasetInput,
    listing_id: Option(String),
    observation_date: Option(String),
    offset: Int,
    limit: Int,
  )
}

pub fn inspect_dataset() -> decoder.Decoder(InspectInput) {
  use dataset <- decoder.field("dataset", dataset_decoder())
  decoder.success(InspectInput(dataset))
}

pub fn drill_observation() -> decoder.Decoder(DrillInput) {
  use dataset <- decoder.field("dataset", dataset_decoder())
  use listing_id <- decoder.field("listingId", decoder.string)
  use observation_date <- decoder.field("observationDate", decoder.string)
  use offset <- decoder.field("offset", decoder.int)
  use limit <- decoder.field("limit", decoder.int)
  decoder.success(DrillInput(
    dataset,
    listing_id,
    observation_date,
    offset,
    limit,
  ))
}

pub fn list_vintages() -> decoder.Decoder(VintagesInput) {
  use dataset <- decoder.field("dataset", dataset_decoder())
  use listing_id <- optional_string("listingId")
  use observation_date <- optional_string("observationDate")
  use offset <- decoder.field("offset", decoder.int)
  use limit <- decoder.field("limit", decoder.int)
  decoder.success(VintagesInput(
    dataset,
    listing_id,
    observation_date,
    offset,
    limit,
  ))
}

fn dataset_decoder() -> decoder.Decoder(DatasetInput) {
  use manifest_json <- decoder.field("manifestJson", decoder.string)
  use manifest_hash <- decoder.field("manifestHash", decoder.string)
  use omissions <- decoder.field(
    "omissions",
    decoder.list(of: omission_decoder()),
  )
  use receipt_roots <- decoder.field(
    "receiptRoots",
    decoder.list(of: decoder.string),
  )
  decoder.success(DatasetInput(
    manifest_json,
    manifest_hash,
    omissions,
    receipt_roots,
  ))
}

fn omission_decoder() -> decoder.Decoder(OmissionInput) {
  use listing_id <- decoder.field("listingId", decoder.string)
  use observation_date <- decoder.field("observationDate", decoder.string)
  use state <- decoder.field("state", decoder.string)
  use evidence_reference <- optional_string("evidenceReference")
  decoder.success(OmissionInput(
    listing_id,
    observation_date,
    state,
    evidence_reference,
  ))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}
