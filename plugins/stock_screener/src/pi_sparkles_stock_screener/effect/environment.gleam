pub fn key_id() -> String {
  read_key_id()
}

pub fn secret_key() -> String {
  read_secret_key()
}

pub fn product() -> String {
  "pi-sparkles-stock-screener/0.1"
}

pub fn contact() -> String {
  read_contact()
}

pub fn now_milliseconds() -> Int {
  read_now_milliseconds()
}

@external(javascript, "./environment_ffi.mjs", "read_key_id")
fn read_key_id() -> String

@external(javascript, "./environment_ffi.mjs", "read_secret_key")
fn read_secret_key() -> String

@external(javascript, "./environment_ffi.mjs", "read_contact")
fn read_contact() -> String

@external(javascript, "./environment_ffi.mjs", "read_now_milliseconds")
fn read_now_milliseconds() -> Int
