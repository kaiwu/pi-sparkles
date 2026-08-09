import finance_core/identifier
import finance_core/market
import finance_core/observation
import finance_core/observation_json
import finance_core/source
import finance_core/time.{type Instant}
import finance_provenance/identity.{type Sha256}
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import finance_twelve_data/request as provider_request
import finance_twelve_data/response.{type Profile, type Statistics}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

const provider = "Twelve Data"

pub type Input {
  Input(symbol: String, mic: String)
}

pub type Receipt {
  Receipt(
    endpoint: String,
    response_byte_length: Int,
    content_sha256: Sha256,
    api_credits_used: Option(String),
    api_credits_left: Option(String),
    api_credits_request: Option(String),
  )
}

pub type Capture {
  Capture(
    profile: Profile,
    profile_receipt: Receipt,
    statistics: Statistics,
    statistics_receipt: Receipt,
    retrieved_at: Instant,
  )
}

pub type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  InvalidSymbol
  UnsupportedMic
  InvalidReceipt
  RequestedListingMismatch
  CrossResponseIdentityMismatch
  InvalidSource(source.SourceError)
  InvalidMic(identifier.IdentifierError)
  InvalidTimezone(time.TimeError)
  InvalidTrackContext(track_context.ContextError)
}

pub fn input(symbol: String, mic: String) -> Result(Input, Error) {
  case valid_symbol(symbol), supported_mic(mic) {
    False, _ -> Error(InvalidSymbol)
    _, False -> Error(UnsupportedMic)
    True, True -> Ok(Input(symbol, mic))
  }
}

pub fn assemble(input: Input, capture: Capture) -> Result(Output, Error) {
  use Nil <- result.try(validate_receipt(
    capture.profile_receipt,
    provider_request.profile_path,
  ))
  use Nil <- result.try(validate_receipt(
    capture.statistics_receipt,
    provider_request.statistics_path,
  ))
  use Nil <- result.try(validate_identity(input, capture))
  use mic <- result.try(
    identifier.mic(input.mic) |> result.map_error(InvalidMic),
  )
  use timezone <- result.try(
    time.timezone(capture.statistics.exchange_timezone)
    |> result.map_error(InvalidTimezone),
  )
  use context <- result.try(
    track_context.new(
      track: finance_track.Us,
      market_scope: "us_twelve_data_company_profile",
      venue_mic: Some(mic),
      board: None,
      timezone: Some(timezone),
      source_language: "en-US",
      providers: [provider],
      entitlement: "caller_twelve_data_subscription",
      limitations: [
        "provider_listing_snapshot_not_exchange_identity_proof",
        "field_effective_dates_not_supplied",
        "classification_taxonomy_not_named",
        "no_cross_listing_fallback",
        "no_profile_to_dossier_judgment",
      ],
    )
    |> result.map_error(InvalidTrackContext),
  )
  use profile_source <- result.try(
    source.new(
      provider,
      source_reference(provider_request.profile_path, input),
      source.LicensedVendor,
    )
    |> result.map_error(InvalidSource),
  )
  use statistics_source <- result.try(
    source.new(
      provider,
      source_reference(provider_request.statistics_path, input),
      source.LicensedVendor,
    )
    |> result.map_error(InvalidSource),
  )
  let profile_observation =
    observation.Observation(
      value: capture.profile,
      as_of: capture.retrieved_at,
      retrieved_at: capture.retrieved_at,
      timezone: None,
      source: profile_source,
      evidence_id: Some(identity.sha256_value(
        capture.profile_receipt.content_sha256,
      )),
      freshness: observation.UnknownFreshness,
      entitlement: observation.UnknownEntitlement,
      quality: observation.Reported,
      unit: None,
      adjustment: None,
      session: None,
    )
  let statistics_observation =
    observation.Observation(
      value: capture.statistics,
      as_of: capture.retrieved_at,
      retrieved_at: capture.retrieved_at,
      timezone: Some(timezone),
      source: statistics_source,
      evidence_id: Some(identity.sha256_value(
        capture.statistics_receipt.content_sha256,
      )),
      freshness: observation.UnknownFreshness,
      entitlement: observation.UnknownEntitlement,
      quality: case
        capture.statistics.shares_outstanding,
        capture.statistics.float_shares
      {
        None, None -> observation.Missing(observation.Unavailable)
        _, _ -> observation.Reported
      },
      unit: Some(market.Shares),
      adjustment: None,
      session: None,
    )
  let fields = [
    #("schema", json.string("pi-sparkles/company-profile-result")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string("company_profile")),
    #(
      "listing",
      json.object([
        #("symbol", json.string(input.symbol)),
        #("mic", json.string(input.mic)),
        #("exchange", json.string(capture.profile.exchange)),
        #(
          "identityState",
          json.string("exact_provider_match_not_exchange_authority_proof"),
        ),
      ]),
    ),
    #("profile", observation_json.to_json(profile_observation, profile_json)),
    #(
      "shares",
      observation_json.to_json(statistics_observation, statistics_json),
    ),
    #(
      "source",
      json.object([
        #("provider", json.string(provider)),
        #("api", json.string("REST profile and statistics")),
        #(
          "retrievedAtUnixMs",
          capture.retrieved_at
            |> time.unix_milliseconds
            |> int.to_string
            |> json.string,
        ),
        #("profile", receipt_json(capture.profile_receipt)),
        #("statistics", receipt_json(capture.statistics_receipt)),
        #(
          "receiptState",
          json.string(
            "sha256_response_content_bound_not_provider_signature_or_origin_authentication",
          ),
        ),
        #("termsReference", json.string("https://twelvedata.com/terms")),
      ]),
    ),
    #(
      "scope",
      json.object([
        #("providerSnapshotAsOf", json.string("retrieval_time_only")),
        #("fieldEffectiveAt", json.null()),
        #("classificationTaxonomy", json.null()),
        #("classificationEffectiveAt", json.null()),
        #("chiefExecutiveEffectiveAt", json.null()),
        #("sharesMeasurementAt", json.null()),
        #("sharesBasis", json.string("provider_stock_statistics_fields")),
        #(
          "nullMeaning",
          json.string("provider_did_not_supply_field_in_response"),
        ),
        #("crossListingFallback", json.null()),
        #("issuerAuthorityProof", json.null()),
        #("exchangeAuthorityProof", json.null()),
        #("qualityRating", json.null()),
        #("investmentJudgment", json.null()),
      ]),
    ),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], json.string)),
  ]
  Ok(Output(
    summary(input, capture),
    json.object(list.append(fields, track_json.result_fields(context))),
  ))
}

pub fn error_message(value: Error) -> String {
  case value {
    InvalidSymbol ->
      "company_profile requires an uppercase 1-20 character US symbol"
    UnsupportedMic ->
      "company_profile supports exact XNYS, XNAS, XNGS, XNCM, or XNMS MIC only"
    InvalidReceipt -> "company_profile source receipt was invalid"
    RequestedListingMismatch ->
      "Twelve Data profile did not match the exact requested symbol and MIC"
    CrossResponseIdentityMismatch ->
      "Twelve Data profile and statistics identities did not match exactly"
    InvalidSource(_) -> "company_profile source reference was invalid"
    InvalidMic(_) -> "company_profile returned an invalid MIC"
    InvalidTimezone(_) ->
      "company_profile statistics returned an invalid exchange timezone"
    InvalidTrackContext(_) ->
      "company_profile could not construct the exact US track context"
  }
}

fn validate_identity(input: Input, capture: Capture) -> Result(Nil, Error) {
  case
    capture.profile.symbol == input.symbol
    && capture.profile.mic == input.mic
    && capture.profile.name != ""
    && capture.profile.exchange != "",
    capture.statistics.symbol == capture.profile.symbol
    && capture.statistics.mic == capture.profile.mic
    && capture.statistics.name == capture.profile.name
    && capture.statistics.exchange == capture.profile.exchange
  {
    False, _ -> Error(RequestedListingMismatch)
    _, False -> Error(CrossResponseIdentityMismatch)
    True, True -> Ok(Nil)
  }
}

fn validate_receipt(value: Receipt, endpoint: String) -> Result(Nil, Error) {
  case value.endpoint == endpoint && value.response_byte_length >= 0 {
    True -> Ok(Nil)
    False -> Error(InvalidReceipt)
  }
}

fn valid_symbol(value: String) -> Bool {
  value != ""
  && string.length(value) <= 20
  && string.uppercase(value) == value
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-", character)
    })
  }
}

fn supported_mic(value: String) -> Bool {
  list.contains(["XNYS", "XNAS", "XNGS", "XNCM", "XNMS"], value)
}

fn source_reference(endpoint: String, input: Input) -> String {
  "https://api.twelvedata.com"
  <> endpoint
  <> "?symbol="
  <> input.symbol
  <> "&mic_code="
  <> input.mic
  <> "&country=US"
}

fn receipt_json(value: Receipt) -> json.Json {
  json.object([
    #("endpoint", json.string(value.endpoint)),
    #("responseByteLength", json.int(value.response_byte_length)),
    #("contentSha256", json.string(identity.sha256_value(value.content_sha256))),
    #("apiCreditsUsed", json.nullable(value.api_credits_used, json.string)),
    #("apiCreditsLeft", json.nullable(value.api_credits_left, json.string)),
    #(
      "apiCreditsRequest",
      json.nullable(value.api_credits_request, json.string),
    ),
  ])
}

fn profile_json(value: Profile) -> json.Json {
  json.object([
    #("symbol", json.string(value.symbol)),
    #("name", json.string(value.name)),
    #("exchange", json.string(value.exchange)),
    #("mic", json.string(value.mic)),
    #("sector", json.nullable(value.sector, json.string)),
    #("industry", json.nullable(value.industry, json.string)),
    #("employeesRaw", json.nullable(value.employees, json.string)),
    #("website", json.nullable(value.website, json.string)),
    #("description", json.nullable(value.description, json.string)),
    #("securityType", json.nullable(value.security_type, json.string)),
    #("chiefExecutive", json.nullable(value.chief_executive, json.string)),
    #("address", json.nullable(value.address, json.string)),
    #("address2", json.nullable(value.address_2, json.string)),
    #("city", json.nullable(value.city, json.string)),
    #("postalCode", json.nullable(value.postal_code, json.string)),
    #("state", json.nullable(value.state, json.string)),
    #("country", json.nullable(value.country, json.string)),
    #("phone", json.nullable(value.phone, json.string)),
  ])
}

fn statistics_json(value: Statistics) -> json.Json {
  json.object([
    #("symbol", json.string(value.symbol)),
    #("name", json.string(value.name)),
    #("exchange", json.string(value.exchange)),
    #("mic", json.string(value.mic)),
    #("currency", json.string(value.currency)),
    #("exchangeTimezone", json.string(value.exchange_timezone)),
    #("outstanding", share_json(value.shares_outstanding, "shares_outstanding")),
    #("float", share_json(value.float_shares, "float_shares")),
  ])
}

fn share_json(value: Option(String), provider_field: String) -> json.Json {
  case value {
    None ->
      json.object([
        #("state", json.string("not_supplied")),
        #("providerField", json.string(provider_field)),
        #("rawValue", json.null()),
        #("unit", json.string("shares")),
      ])
    Some(raw) ->
      json.object([
        #("state", json.string("observed")),
        #("providerField", json.string(provider_field)),
        #("rawValue", json.string(raw)),
        #("unit", json.string("shares")),
      ])
  }
}

fn summary(input: Input, capture: Capture) -> String {
  let shares = case capture.statistics.shares_outstanding {
    None -> "shares outstanding not supplied"
    Some(raw) -> raw <> " provider-reported shares outstanding"
  }
  "Twelve Data profile for "
  <> input.symbol
  <> " at "
  <> input.mic
  <> ": "
  <> capture.profile.name
  <> ", "
  <> shares
  <> ". Snapshot retrieval time is not a field effective date; no quality or investment judgment is made."
}
