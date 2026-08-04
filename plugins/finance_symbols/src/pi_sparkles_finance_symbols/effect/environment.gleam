import gleam/option.{type Option, None, Some}

pub fn openfigi_api_key() -> Option(String) {
  case read_openfigi_api_key() {
    "" -> None
    value -> Some(value)
  }
}

@external(javascript, "./environment_ffi.mjs", "read_openfigi_api_key")
fn read_openfigi_api_key() -> String
