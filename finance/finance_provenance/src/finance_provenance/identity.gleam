import gleam/list
import gleam/string

pub opaque type Sha256 {
  Sha256(value: String)
}

pub opaque type SourceFingerprint {
  SourceFingerprint(value: Sha256)
}

pub opaque type EvidenceId {
  EvidenceId(value: Sha256)
}

pub type IdentityError {
  InvalidSha256
}

pub fn sha256(value: String) -> Result(Sha256, IdentityError) {
  let normalized = string.lowercase(value)
  case
    string.length(normalized) == 64
    && {
      normalized
      |> string.to_graphemes
      |> list.all(fn(character) {
        string.contains("0123456789abcdef", character)
      })
    }
  {
    True -> Ok(Sha256(normalized))
    False -> Error(InvalidSha256)
  }
}

pub fn sha256_value(value: Sha256) -> String {
  let Sha256(value) = value
  value
}

pub fn source_fingerprint(value: Sha256) -> SourceFingerprint {
  SourceFingerprint(value)
}

pub fn source_fingerprint_value(value: SourceFingerprint) -> String {
  let SourceFingerprint(value) = value
  sha256_value(value)
}

pub fn evidence_id(value: Sha256) -> EvidenceId {
  EvidenceId(value)
}

pub fn evidence_id_value(value: EvidenceId) -> String {
  let EvidenceId(value) = value
  sha256_value(value)
}
