import finance_core/time.{type Date}
import finance_ohlcv/fact.{type Fact}

pub type SourceKind {
  ExchangeFeed
  VendorFeed
  PublicWeb
  CredentialedApi
  UnknownSourceKind
}

pub type StatementAuthority {
  Sourced(reference: String, effective_date: Date)
  CallerDeclaredAuthority
  HostPolicyAuthority(reference: String)
}

/// A rights predicate never forces missing terms into true or false.
pub type RightsPredicate {
  SourcedTrue(reference: String, effective_date: Date)
  SourcedFalse(reference: String, effective_date: Date)
  UnknownPredicate(reason: String)
  CallerDeclared(value: Bool)
  HostPolicy(value: Bool, reference: String)
}

pub type Entitlement {
  RealTime
  Delayed(minutes: Int)
  EndOfDay
  UnknownEntitlement
}

pub opaque type RightsFacts {
  RightsFacts(
    provider: Fact(String),
    source_kind: Fact(SourceKind),
    licence_label: Fact(String),
    licence_source: Fact(StatementAuthority),
    attribution_required: RightsPredicate,
    attribution_text: Fact(String),
    redistribution: RightsPredicate,
    entitlement: Fact(Entitlement),
    cache: RightsPredicate,
    retention_limit_days: Fact(Int),
    source_limitations: Fact(String),
  )
}

pub fn new(
  provider provider_value: Fact(String),
  source_kind source_kind_value: Fact(SourceKind),
  licence_label licence_label_value: Fact(String),
  licence_source licence_source_value: Fact(StatementAuthority),
  attribution_required attribution_value: RightsPredicate,
  attribution_text attribution_text_value: Fact(String),
  redistribution redistribution_value: RightsPredicate,
  entitlement entitlement_value: Fact(Entitlement),
  cache cache_value: RightsPredicate,
  retention_limit_days retention_value: Fact(Int),
  source_limitations limitations_value: Fact(String),
) -> RightsFacts {
  RightsFacts(
    provider_value,
    source_kind_value,
    licence_label_value,
    licence_source_value,
    attribution_value,
    attribution_text_value,
    redistribution_value,
    entitlement_value,
    cache_value,
    retention_value,
    limitations_value,
  )
}

pub fn provider(value: RightsFacts) -> Fact(String) {
  value.provider
}

pub fn source_kind(value: RightsFacts) -> Fact(SourceKind) {
  value.source_kind
}

pub fn licence_label(value: RightsFacts) -> Fact(String) {
  value.licence_label
}

pub fn licence_source(value: RightsFacts) -> Fact(StatementAuthority) {
  value.licence_source
}

pub fn attribution_required(value: RightsFacts) -> RightsPredicate {
  value.attribution_required
}

pub fn attribution_text(value: RightsFacts) -> Fact(String) {
  value.attribution_text
}

pub fn redistribution(value: RightsFacts) -> RightsPredicate {
  value.redistribution
}

pub fn entitlement(value: RightsFacts) -> Fact(Entitlement) {
  value.entitlement
}

pub fn cache(value: RightsFacts) -> RightsPredicate {
  value.cache
}

pub fn retention_limit_days(value: RightsFacts) -> Fact(Int) {
  value.retention_limit_days
}

pub fn source_limitations(value: RightsFacts) -> Fact(String) {
  value.source_limitations
}
