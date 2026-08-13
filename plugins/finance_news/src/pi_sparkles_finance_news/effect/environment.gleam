pub fn product() -> String {
  "pi-sparkles-finance-news/0.1"
}

@external(javascript, "./environment_ffi.mjs", "read_key_id")
pub fn key_id() -> String

@external(javascript, "./environment_ffi.mjs", "read_secret_key")
pub fn secret_key() -> String

@external(javascript, "./environment_ffi.mjs", "read_contact")
pub fn contact() -> String

@external(javascript, "./environment_ffi.mjs", "read_now_milliseconds")
pub fn now_milliseconds() -> Int
