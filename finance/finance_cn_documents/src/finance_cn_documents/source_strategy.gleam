import finance_core/source
import finance_provider_strategy/strategy
import finance_track
import gleam/list
import gleam/string

pub type Venue {
  Sse
  Szse
  Bse
}

pub type StrategyError {
  InvalidDocumentIdentity
}

/// Authority-first local retrieval for one exact venue-issued document.
///
/// CNINFO is an availability route, not a replacement origin. Callers must
/// still validate that the returned artifact carries the requested exact
/// venue document identity before recording a successful attempt.
pub fn disclosure_plan(
  venue venue_value: Venue,
  document_identity document_identity_value: String,
) -> Result(strategy.Plan, StrategyError) {
  case valid_identity(document_identity_value) {
    False -> Error(InvalidDocumentIdentity)
    True -> {
      let contract = disclosure_contract(venue_value, document_identity_value)
      let origin = venue_source(venue_value, document_identity_value)
      let direct =
        channel(
          id: direct_id(venue_value),
          origin: origin,
          route: strategy.Direct,
          contract: contract,
        )
      let cninfo =
        channel(
          id: cninfo_id(venue_value),
          origin: origin,
          route: strategy.Via("CNINFO"),
          contract: contract,
        )
      let assert Ok(value) =
        strategy.plan(finance_track.Cn, contract, strategy.CacheFirst, [
          direct,
          cninfo,
        ])
      Ok(value)
    }
  }
}

fn disclosure_contract(venue: Venue, identity: String) -> strategy.Contract {
  let assert Ok(value) =
    strategy.contract(
      family: "issuer_disclosure",
      identity: venue_name(venue) <> ":" <> identity,
      freshness: "published_artifact",
      unit_basis: "source_document",
      adjustment_basis: "not_applicable",
    )
  value
}

fn venue_source(venue: Venue, identity: String) -> source.SourceRef {
  let assert Ok(value) =
    source.new(
      provider: venue_name(venue),
      reference: venue_name(venue) <> ":" <> identity,
      kind: source.Exchange,
    )
  value
}

fn channel(
  id id_value: String,
  origin origin_value: source.SourceRef,
  route route_value: strategy.Route,
  contract contract_value: strategy.Contract,
) -> strategy.Channel {
  let assert Ok(value) =
    strategy.channel(
      finance_track.Cn,
      id_value,
      origin_value,
      route_value,
      strategy.CanonicalEvidence,
      strategy.VerifiedReadOnly,
      strategy.LocalAnalysisOnly,
      contract_value,
    )
  value
}

fn venue_name(value: Venue) -> String {
  case value {
    Sse -> "SSE"
    Szse -> "SZSE"
    Bse -> "BSE"
  }
}

fn direct_id(value: Venue) -> String {
  case value {
    Sse -> "cn_sse_direct"
    Szse -> "cn_szse_direct"
    Bse -> "cn_bse_direct"
  }
}

fn cninfo_id(value: Venue) -> String {
  case value {
    Sse -> "cn_sse_via_cninfo"
    Szse -> "cn_szse_via_cninfo"
    Bse -> "cn_bse_via_cninfo"
  }
}

fn valid_identity(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 300
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
  && !contains_secret(value)
}

fn contains_secret(value: String) -> Bool {
  let lowered = string.lowercase(value)
  ["api_key=", "apikey=", "access_token=", "signature=", "cookie="]
  |> list.any(fn(marker) { string.contains(lowered, marker) })
}
