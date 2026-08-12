import gleam/list
import gleam/string

pub fn is_market_depth_name(value: String) -> Bool {
  let normalized =
    value
    |> string.trim
    |> string.lowercase
    |> string.replace("-", "_")
    |> string.replace(".", "_")
    |> string.replace(" ", "_")
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
