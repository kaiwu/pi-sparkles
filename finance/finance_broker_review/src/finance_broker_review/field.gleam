import gleam/list
import gleam/string

pub fn is_market_depth_name(value: String) -> Bool {
  let normalized = normalize_name(value)
  list.any(["bid", "ask", "offer"], fn(term) {
    normalized == term
    || string.starts_with(normalized, term <> "_")
    || string.ends_with(normalized, "_" <> term)
    || string.contains(normalized, "_" <> term <> "_")
    || string.starts_with(normalized, "best_" <> term)
    || string.contains(normalized, "best" <> term)
    || string.contains(normalized, term <> "price")
    || string.contains(normalized, term <> "size")
  })
  || string.contains(normalized, "marketdepth")
  || string.contains(normalized, "market_depth")
  || string.contains(normalized, "orderbook")
  || string.contains(normalized, "order_book")
}

pub fn is_sensitive_name(value: String) -> Bool {
  let normalized = normalize_name(value)
  list.any(
    [
      "password",
      "passwd",
      "secret",
      "token",
      "api_key",
      "authorization_header",
      "credential",
      "private_key",
      "cookie",
      "account_number",
      "account_id",
      "subaccount_id",
      "email",
      "phone",
      "tax_id",
    ],
    fn(term) {
      normalized == term
      || string.starts_with(normalized, term <> "_")
      || string.ends_with(normalized, "_" <> term)
      || string.contains(normalized, "_" <> term <> "_")
    },
  )
  || list.any(
    [
      "apikey",
      "authtoken",
      "accesstoken",
      "refreshtoken",
      "privatekey",
      "accountnumber",
      "accountid",
      "subaccountid",
      "taxid",
    ],
    fn(term) { normalized == term || string.contains(normalized, term) },
  )
}

pub fn contains_sensitive_lexeme(value: String) -> Bool {
  let normalized = value |> string.trim |> string.lowercase
  string.starts_with(normalized, "bearer ")
  || string.starts_with(normalized, "basic ")
  || list.any(
    [
      "api_key=",
      "apikey=",
      "token=",
      "password=",
      "passwd=",
      "secret=",
      "authorization:",
      "cookie:",
      "set-cookie:",
      "private key",
      "-----begin",
    ],
    fn(marker) { string.contains(normalized, marker) },
  )
}

pub fn has_control_characters(value: String) -> Bool {
  value
  |> string.to_utf_codepoints
  |> list.any(fn(codepoint) {
    let number = string.utf_codepoint_to_int(codepoint)
    number < 32 || number == 127
  })
}

fn normalize_name(value: String) -> String {
  value
  |> string.trim
  |> string.lowercase
  |> string.replace("-", "_")
  |> string.replace(".", "_")
  |> string.replace(" ", "_")
}
