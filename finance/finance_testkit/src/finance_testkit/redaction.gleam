import gleam/list
import gleam/string

pub type Leak {
  Leak(secret_label: String)
}

pub fn find_leaks(
  output: String,
  forbidden: List(#(String, String)),
) -> List(Leak) {
  forbidden
  |> list.filter_map(fn(item) {
    let #(label, secret) = item
    case secret != "" && string.contains(output, secret) {
      True -> Ok(Leak(label))
      False -> Error(Nil)
    }
  })
}

pub fn is_safe(output: String, forbidden: List(#(String, String))) -> Bool {
  output |> find_leaks(forbidden) |> list.is_empty
}
