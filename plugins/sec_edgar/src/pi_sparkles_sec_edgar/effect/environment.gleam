pub fn product() -> String {
  "pi-sparkles-sec-edgar/0.1"
}

pub fn contact() -> String {
  read_contact()
}

@external(javascript, "./environment_ffi.mjs", "read_contact")
fn read_contact() -> String
