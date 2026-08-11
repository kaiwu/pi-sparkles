import finance_cache_contract as cache
import gleam/list
import gleam/option.{type Option, None, Some}

pub fn select(
  entries: List(cache.Entry),
  provider: Option(String),
  maximum_entries: Int,
) -> List(cache.Entry) {
  entries
  |> list.filter(fn(value) {
    case provider {
      None -> True
      Some(expected) -> cache.provider(value) == expected
    }
  })
  |> list.take(maximum_entries)
}

pub fn providers(entries: List(cache.Entry)) -> List(String) {
  entries
  |> list.map(cache.provider)
  |> unique([])
  |> list.reverse
}

fn unique(values: List(String), accumulated: List(String)) -> List(String) {
  case values {
    [] -> accumulated
    [value, ..rest] ->
      case list.contains(accumulated, value) {
        True -> unique(rest, accumulated)
        False -> unique(rest, [value, ..accumulated])
      }
  }
}
