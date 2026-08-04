import finance_core/identifier
import finance_openfigi/response.{type Candidate}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub fn resolve(
  candidates: List(Candidate),
) -> identifier.Resolution(Candidate) {
  candidates
  |> list.sort(by: fn(left, right) { string.compare(left.figi, right.figi) })
  |> identifier.resolve
}

pub fn candidate_label(value: Candidate) -> String {
  [
    optional_value(value.ticker, "ticker unavailable"),
    optional_value(value.name, "name unavailable"),
    "FIGI " <> value.figi,
    "exchange " <> optional_value(value.exchange_code, "unavailable"),
    optional_value(value.security_type, "type unavailable"),
  ]
  |> string.join(" | ")
}

pub fn resolution_name(value: identifier.Resolution(Candidate)) -> String {
  case value {
    identifier.NoMatch -> "no_match"
    identifier.Unique(_) -> "unique"
    identifier.Ambiguous(_, _, _) -> "ambiguous"
  }
}

fn optional_value(value: Option(String), fallback: String) -> String {
  case value {
    Some(value) -> value
    None -> fallback
  }
}
