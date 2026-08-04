import gleam/list
import gleam/string

pub opaque type InstrumentId {
  InstrumentId(value: String)
}

pub opaque type Symbol {
  Symbol(value: String)
}

pub opaque type Mic {
  Mic(value: String)
}

pub type IdentifierError {
  Empty
  InvalidSymbol
  InvalidMic
}

pub type ExternalScheme {
  Figi
  Cik
  Isin
  Cusip
  Sedol
  ProviderDefined(provider: String)
}

pub type ExternalIdentifier {
  ExternalIdentifier(scheme: ExternalScheme, value: String)
}

pub fn instrument_id(value: String) -> Result(InstrumentId, IdentifierError) {
  case non_empty(value) {
    True -> Ok(InstrumentId(value))
    False -> Error(Empty)
  }
}

pub fn instrument_id_value(value: InstrumentId) -> String {
  let InstrumentId(value) = value
  value
}

pub fn symbol(value: String) -> Result(Symbol, IdentifierError) {
  case non_empty(value) && no_whitespace(value) {
    True -> Ok(Symbol(string.uppercase(value)))
    False -> Error(InvalidSymbol)
  }
}

pub fn symbol_value(value: Symbol) -> String {
  let Symbol(value) = value
  value
}

pub fn mic(value: String) -> Result(Mic, IdentifierError) {
  let normalized = string.uppercase(value)
  case
    string.length(normalized) == 4
    && { normalized |> string.to_graphemes |> list.all(is_ascii_alphanumeric) }
  {
    True -> Ok(Mic(normalized))
    False -> Error(InvalidMic)
  }
}

pub fn mic_value(value: Mic) -> String {
  let Mic(value) = value
  value
}

pub fn external_identifier(
  scheme: ExternalScheme,
  value: String,
) -> Result(ExternalIdentifier, IdentifierError) {
  case non_empty(value) {
    True -> Ok(ExternalIdentifier(scheme, value))
    False -> Error(Empty)
  }
}

fn non_empty(value: String) -> Bool {
  value != "" && string.trim(value) == value
}

fn no_whitespace(value: String) -> Bool {
  value
  |> string.to_graphemes
  |> list.all(fn(character) { string.trim(character) == character })
}

fn is_ascii_alphanumeric(character: String) -> Bool {
  string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", character)
}
