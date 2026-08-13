pub fn contact() -> String {
  case read_contact() {
    "" -> "unconfigured"
    value -> value
  }
}

@external(javascript, "./environment_ffi.mjs", "read_contact")
fn read_contact() -> String
