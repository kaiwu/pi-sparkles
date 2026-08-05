import finance_core/identifier.{type Resolution}
import finance_hkex/security_search.{type Security}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type SelectionError {
  NoCandidate
  AmbiguousCandidates(count: Int)
  StockIdMismatch
}

pub fn candidates(value: Resolution(Security)) -> List(Security) {
  case value {
    identifier.NoMatch -> []
    identifier.Unique(item) -> [item]
    identifier.Ambiguous(first, second, rest) -> [first, second, ..rest]
  }
}

pub fn select(
  resolution: Resolution(Security),
  stock_id: Option(Int),
) -> Result(Security, SelectionError) {
  let values = candidates(resolution)
  case stock_id {
    Some(expected) ->
      case
        values
        |> list.filter(fn(value) { security_search.stock_id(value) == expected })
      {
        [value] -> Ok(value)
        _ -> Error(StockIdMismatch)
      }
    None ->
      case values {
        [] -> Error(NoCandidate)
        [value] -> Ok(value)
        many -> Error(AmbiguousCandidates(list.length(many)))
      }
  }
}
