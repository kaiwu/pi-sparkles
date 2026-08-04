import gleam/list
import gleam/string

pub type SourceKind {
  Official
  Exchange
  Regulator
  LicensedVendor
  UserSupplied
  Synthetic
  Other(kind: String)
}

pub opaque type SourceRef {
  SourceRef(provider: String, reference: String, kind: SourceKind)
}

pub type SourceError {
  InvalidProvider
  InvalidReference
  UnsafeReference
}

pub fn new(
  provider provider: String,
  reference reference: String,
  kind kind: SourceKind,
) -> Result(SourceRef, SourceError) {
  case valid(provider), valid(reference) {
    False, _ -> Error(InvalidProvider)
    _, False -> Error(InvalidReference)
    True, True ->
      case contains_secret(reference) {
        True -> Error(UnsafeReference)
        False -> Ok(SourceRef(provider, reference, kind))
      }
  }
}

pub fn provider(source: SourceRef) -> String {
  let SourceRef(provider, _, _) = source
  provider
}

pub fn reference(source: SourceRef) -> String {
  let SourceRef(_, reference, _) = source
  reference
}

pub fn kind(source: SourceRef) -> SourceKind {
  let SourceRef(_, _, kind) = source
  kind
}

fn valid(value: String) -> Bool {
  value != "" && string.trim(value) == value
}

fn contains_secret(value: String) -> Bool {
  let lowered = string.lowercase(value)
  [
    "authorization=",
    "api_key=",
    "apikey=",
    "access_token=",
    "private_token=",
    "signature=",
    "x-amz-signature=",
    "cookie=",
  ]
  |> list.any(fn(marker) { string.contains(lowered, marker) })
}
