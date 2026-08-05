import finance_core/time.{type Date}
import finance_listing/effective.{type Interval}
import finance_listing/listing.{type Key}
import finance_provenance/identity.{type EvidenceId}
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub opaque type Alias {
  Alias(
    listing: Key,
    name: String,
    language: String,
    effective: Interval,
    evidence_id: Option(EvidenceId),
  )
}

pub type AliasError {
  InvalidName
  InvalidLanguage
}

pub fn new(
  listing listing: Key,
  name name: String,
  language language: String,
  effective effective: Interval,
  evidence_id evidence_id: Option(EvidenceId),
) -> Result(Alias, AliasError) {
  case valid_text(name), valid_language(language) {
    False, _ -> Error(InvalidName)
    _, False -> Error(InvalidLanguage)
    True, True -> Ok(Alias(listing, name, language, effective, evidence_id))
  }
}

pub fn listing(value: Alias) -> Key {
  value.listing
}

pub fn name(value: Alias) -> String {
  value.name
}

pub fn language(value: Alias) -> String {
  value.language
}

pub fn effective(value: Alias) -> Interval {
  value.effective
}

pub fn evidence_id(value: Alias) -> Option(EvidenceId) {
  value.evidence_id
}

pub fn active_on(aliases: List(Alias), date: Date) -> List(Alias) {
  aliases
  |> list.filter(fn(item) { effective.contains(item.effective, date) })
}

fn valid_text(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn valid_language(value: String) -> Bool {
  value != ""
  && string.length(value) <= 35
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-",
        character,
      )
    })
  }
}
