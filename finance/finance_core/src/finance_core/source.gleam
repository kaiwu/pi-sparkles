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
}

pub fn new(
  provider provider: String,
  reference reference: String,
  kind kind: SourceKind,
) -> Result(SourceRef, SourceError) {
  case valid(provider), valid(reference) {
    False, _ -> Error(InvalidProvider)
    _, False -> Error(InvalidReference)
    True, True -> Ok(SourceRef(provider, reference, kind))
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
