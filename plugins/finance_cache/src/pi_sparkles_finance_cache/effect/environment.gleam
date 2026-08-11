pub fn now_milliseconds() -> Int {
  read_now_milliseconds()
}

@external(javascript, "./environment_ffi.mjs", "read_now_milliseconds")
fn read_now_milliseconds() -> Int
