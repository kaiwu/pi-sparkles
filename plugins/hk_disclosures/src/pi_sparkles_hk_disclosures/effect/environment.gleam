pub fn product() -> String {
  case read_product() {
    "" -> "pi-sparkles-hk-disclosures/0.1"
    value -> value
  }
}

pub fn contact() -> String {
  read_contact()
}

pub fn now_milliseconds() -> Int {
  read_now_milliseconds()
}

@external(javascript, "./environment_ffi.mjs", "read_product")
fn read_product() -> String

@external(javascript, "./environment_ffi.mjs", "read_contact")
fn read_contact() -> String

@external(javascript, "./environment_ffi.mjs", "read_now_milliseconds")
fn read_now_milliseconds() -> Int
