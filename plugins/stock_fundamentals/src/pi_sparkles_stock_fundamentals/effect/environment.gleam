pub fn product() -> String {
  case read_product() {
    "" -> "pi-sparkles-stock-fundamentals/0.1"
    value -> value
  }
}

pub fn contact() -> String {
  read_contact()
}

@external(javascript, "./environment_ffi.mjs", "read_product")
fn read_product() -> String

@external(javascript, "./environment_ffi.mjs", "read_contact")
fn read_contact() -> String
