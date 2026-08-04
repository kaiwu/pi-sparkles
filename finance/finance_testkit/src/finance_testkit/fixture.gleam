import finance_core/time.{type Date}
import gleam/string

pub type Kind {
  Synthetic
  Authoritative
}

pub opaque type Metadata {
  Metadata(
    kind: Kind,
    source: String,
    licence: String,
    retrieved_on: Date,
    covered_market: String,
  )
}

pub type MetadataError {
  InvalidSource
  InvalidLicence
  InvalidCoveredMarket
}

pub fn metadata(
  kind kind: Kind,
  source source: String,
  licence licence: String,
  retrieved_on retrieved_on: Date,
  covered_market covered_market: String,
) -> Result(Metadata, MetadataError) {
  case valid(source), valid(licence), valid(covered_market) {
    False, _, _ -> Error(InvalidSource)
    _, False, _ -> Error(InvalidLicence)
    _, _, False -> Error(InvalidCoveredMarket)
    True, True, True ->
      Ok(Metadata(kind, source, licence, retrieved_on, covered_market))
  }
}

fn valid(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
