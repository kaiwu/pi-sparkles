pub fn product() -> String {
  case read_product() {
    "" -> "pi-sparkles-stock-earnings-calendar/0.1"
    value -> value
  }
}

@external(javascript, "./environment_ffi.mjs", "read_product")
fn read_product() -> String

@external(javascript, "./environment_ffi.mjs", "read_contact")
pub fn contact() -> String

@external(javascript, "./environment_ffi.mjs", "read_now_milliseconds")
pub fn now_milliseconds() -> Int
