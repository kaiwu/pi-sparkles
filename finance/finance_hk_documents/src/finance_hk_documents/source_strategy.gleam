import finance_core/source
import finance_provider_strategy/strategy
import finance_track
import gleam/list
import gleam/string

pub type StrategyError {
  InvalidDocumentIdentity
}

/// HKEXnews remains the sole canonical route until another exact-artifact
/// channel has approved access and rights. Vendor fundamentals are not filing
/// fallback.
pub fn disclosure_plan(
  document_identity document_identity_value: String,
) -> Result(strategy.Plan, StrategyError) {
  case valid_identity(document_identity_value) {
    False -> Error(InvalidDocumentIdentity)
    True -> {
      let assert Ok(contract) =
        strategy.contract(
          family: "issuer_disclosure",
          identity: "HKEXnews:" <> document_identity_value,
          freshness: "published_artifact",
          unit_basis: "source_document",
          adjustment_basis: "not_applicable",
        )
      let assert Ok(origin) =
        source.new(
          provider: "HKEXnews",
          reference: "HKEXnews:" <> document_identity_value,
          kind: source.Exchange,
        )
      let assert Ok(channel) =
        strategy.channel(
          finance_track.Hk,
          "hk_hkexnews_direct",
          origin,
          strategy.Direct,
          strategy.CanonicalEvidence,
          strategy.VerifiedReadOnly,
          strategy.LocalAnalysisOnly,
          contract,
        )
      let assert Ok(value) =
        strategy.plan(finance_track.Hk, contract, strategy.CacheFirst, [channel])
      Ok(value)
    }
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
