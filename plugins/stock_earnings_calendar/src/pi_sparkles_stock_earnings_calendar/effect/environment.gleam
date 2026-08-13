pub fn product() -> String {
  "pi-sparkles-stock-earnings-calendar/0.1"
}

@external(javascript, "./environment_ffi.mjs", "read_contact")
pub fn contact() -> String

@external(javascript, "./environment_ffi.mjs", "read_now_milliseconds")
pub fn now_milliseconds() -> Int
