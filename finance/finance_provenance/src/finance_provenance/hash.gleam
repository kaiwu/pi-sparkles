import finance_provenance/canonical
import finance_provenance/identity.{type IdentityError, type Sha256}
import finance_provenance/manifest.{type Manifest}

@external(javascript, "./hash_ffi.mjs", "sha256_hex")
fn sha256_hex(value: String) -> String

pub fn text(value: String) -> Result(Sha256, IdentityError) {
  value |> sha256_hex |> identity.sha256
}

pub fn manifest(value: Manifest) -> Result(Sha256, IdentityError) {
  value |> canonical.encode_manifest |> text
}
