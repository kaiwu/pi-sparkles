import finance_core/time.{type Instant}
import finance_provenance/identity.{type Sha256}
import gleam/int
import gleam/list
import gleam/string

pub type SourceKind {
  BrokerObservation
  ExchangeObservation
  ProviderObservation
  ExternalDocumentation
  MarketRule
  CalendarObservation
  CallerDeclared
  LlmInstruction
  Calculated
}

pub opaque type Source {
  Source(
    kind: SourceKind,
    reference: Sha256,
    effective_at: Instant,
    retrieved_at: Instant,
    currency: String,
    unit: String,
    source_lexeme: String,
    scope: String,
    retained_alternatives: List(String),
  )
}

pub type Sourced(value) {
  Sourced(value: value, source: Source)
}

pub type Fact(value) {
  Known(value: Sourced(value))
  Unknown(source: Source, reason: String)
  NotObtained(source: Source, reason: String)
  Conflicting(alternatives: List(Sourced(value)))
  DecodeFailure(source: Source, raw: String, reason: String)
  NotApplicable(source: Source, reason: String)
}

pub type FactError {
  InvalidText(field: String)
  EmptyConflict
}

pub fn source(
  kind kind_value: SourceKind,
  reference reference_value: Sha256,
  effective_at effective_value: Instant,
  retrieved_at retrieved_value: Instant,
  currency currency_value: String,
  unit unit_value: String,
  source_lexeme lexeme_value: String,
  scope scope_value: String,
  retained_alternatives alternative_values: List(String),
) -> Result(Source, FactError) {
  case
    valid_text(currency_value),
    valid_text(unit_value),
    valid_text(scope_value)
  {
    False, _, _ -> Error(InvalidText("currency"))
    _, False, _ -> Error(InvalidText("unit"))
    _, _, False -> Error(InvalidText("scope"))
    True, True, True ->
      Ok(Source(
        kind_value,
        reference_value,
        effective_value,
        retrieved_value,
        currency_value,
        unit_value,
        lexeme_value,
        scope_value,
        alternative_values,
      ))
  }
}

pub fn known(value: value, source: Source) -> Fact(value) {
  Known(Sourced(value, source))
}

pub fn conflicting(
  alternatives: List(Sourced(value)),
) -> Result(Fact(value), FactError) {
  case alternatives {
    [] -> Error(EmptyConflict)
    _ -> Ok(Conflicting(alternatives))
  }
}

pub fn known_value(value: Fact(value)) -> Result(Sourced(value), String) {
  case value {
    Known(sourced) -> Ok(sourced)
    Unknown(_, reason) -> Error("unknown:" <> reason)
    NotObtained(_, reason) -> Error("not_obtained:" <> reason)
    Conflicting(alternatives) ->
      Error(
        "conflicting_alternatives:"
        <> alternatives
        |> list.length
        |> int.to_string,
      )
    DecodeFailure(_, raw, reason) ->
      Error("decode_failure:" <> reason <> ":" <> raw)
    NotApplicable(_, reason) -> Error("not_applicable:" <> reason)
  }
}

pub fn sourced_value(value: Sourced(value)) -> value {
  value.value
}

pub fn sourced_source(value: Sourced(value)) -> Source {
  value.source
}

pub fn source_kind(value: Source) -> SourceKind {
  value.kind
}

pub fn source_kind_name(value: SourceKind) -> String {
  case value {
    BrokerObservation -> "broker_observation"
    ExchangeObservation -> "exchange_observation"
    ProviderObservation -> "provider_observation"
    ExternalDocumentation -> "external_documentation"
    MarketRule -> "market_rule"
    CalendarObservation -> "calendar_observation"
    CallerDeclared -> "caller_declared"
    LlmInstruction -> "llm_instruction"
    Calculated -> "calculated"
  }
}

pub fn source_reference(value: Source) -> Sha256 {
  value.reference
}

pub fn effective_at(value: Source) -> Instant {
  value.effective_at
}

pub fn retrieved_at(value: Source) -> Instant {
  value.retrieved_at
}

pub fn currency(value: Source) -> String {
  value.currency
}

pub fn unit(value: Source) -> String {
  value.unit
}

pub fn source_lexeme(value: Source) -> String {
  value.source_lexeme
}

pub fn scope(value: Source) -> String {
  value.scope
}

pub fn retained_alternatives(value: Source) -> List(String) {
  value.retained_alternatives
}

pub fn state_name(value: Fact(value)) -> String {
  case value {
    Known(_) -> "known"
    Unknown(_, _) -> "unknown"
    NotObtained(_, _) -> "not_obtained"
    Conflicting(_) -> "conflicting"
    DecodeFailure(_, _, _) -> "decode_failure"
    NotApplicable(_, _) -> "not_applicable"
  }
}

pub fn fact_sources(value: Fact(value)) -> List(Source) {
  case value {
    Known(Sourced(_, source))
    | Unknown(source, _)
    | NotObtained(source, _)
    | DecodeFailure(source, _, _)
    | NotApplicable(source, _) -> [source]
    Conflicting(alternatives) -> list.map(alternatives, sourced_source)
  }
}

fn valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
