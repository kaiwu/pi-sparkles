pub fn eastmoney_product() -> String {
  case read_eastmoney_product() {
    "" -> "pi-sparkles-cn-stock-quote/0.1"
    value -> value
  }
}

pub fn eastmoney_contact() -> String {
  read_eastmoney_contact()
}

pub fn tushare_token() -> String {
  read_tushare_token()
}

pub fn now_milliseconds() -> Int {
  read_now_milliseconds()
}

@external(javascript, "./environment_ffi.mjs", "read_eastmoney_product")
fn read_eastmoney_product() -> String

@external(javascript, "./environment_ffi.mjs", "read_eastmoney_contact")
fn read_eastmoney_contact() -> String

@external(javascript, "./environment_ffi.mjs", "read_tushare_token")
fn read_tushare_token() -> String

@external(javascript, "./environment_ffi.mjs", "read_now_milliseconds")
fn read_now_milliseconds() -> Int
