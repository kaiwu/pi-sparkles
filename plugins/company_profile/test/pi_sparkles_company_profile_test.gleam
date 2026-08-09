import finance_core/time
import finance_provenance/identity
import finance_twelve_data/request as provider_request
import finance_twelve_data/response
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_company_profile/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn input_requires_exact_uppercase_symbol_and_supported_us_mic_test() {
  domain.input("aapl", "XNGS")
  |> should.equal(Error(domain.InvalidSymbol))
  domain.input("AAPL", "XHKG")
  |> should.equal(Error(domain.UnsupportedMic))
  domain.input("AAPL", "XNGS")
  |> should.equal(Ok(domain.Input("AAPL", "XNGS")))
}

pub fn complete_profile_preserves_exact_mic_snapshot_fields_and_shares_test() {
  let assert Ok(input) = domain.input("AAPL", "XNGS")
  let assert Ok(output) = domain.assemble(input, complete_capture())
  output.summary
  |> should.equal(
    "Twelve Data profile for AAPL at XNGS: Apple Inc., 14687356000 provider-reported shares outstanding. Snapshot retrieval time is not a field effective date; no quality or investment judgment is made.",
  )
  let details = json.to_string(output.details)
  string.contains(details, "\"track\":\"us\"") |> should.be_true
  string.contains(details, "\"venueMic\":\"XNGS\"") |> should.be_true
  string.contains(details, "\"chiefExecutive\":\"Tim Cook\"")
  |> should.be_true
  string.contains(details, "\"rawValue\":\"14687356000\"")
  |> should.be_true
  string.contains(details, "\"fieldEffectiveAt\":null")
  |> should.be_true
  string.contains(details, "\"classificationTaxonomy\":null")
  |> should.be_true
  string.contains(details, "\"investmentJudgment\":null")
  |> should.be_true
}

pub fn absent_share_fields_remain_not_supplied_test() {
  let assert Ok(input) = domain.input("AAPL", "XNGS")
  let capture = complete_capture()
  let assert Ok(output) =
    domain.assemble(
      input,
      domain.Capture(
        ..capture,
        statistics: response.Statistics(
          "AAPL",
          "Apple Inc.",
          "USD",
          "NASDAQ",
          "XNGS",
          "America/New_York",
          None,
          None,
        ),
      ),
    )
  let details = json.to_string(output.details)
  string.contains(details, "\"state\":\"not_supplied\"")
  |> should.be_true
  string.contains(details, "\"tag\":\"missing\"") |> should.be_true
}

pub fn requested_listing_mismatch_fails_before_any_profile_claim_test() {
  let assert Ok(input) = domain.input("MSFT", "XNGS")
  domain.assemble(input, complete_capture())
  |> should.equal(Error(domain.RequestedListingMismatch))
}

pub fn profile_and_statistics_must_join_on_name_exchange_symbol_and_mic_test() {
  let assert Ok(input) = domain.input("AAPL", "XNGS")
  let capture = complete_capture()
  domain.assemble(
    input,
    domain.Capture(
      ..capture,
      statistics: response.Statistics(
        "AAPL",
        "Different Issuer",
        "USD",
        "NASDAQ",
        "XNGS",
        "America/New_York",
        Some("14687356000"),
        Some("14569223952"),
      ),
    ),
  )
  |> should.equal(Error(domain.CrossResponseIdentityMismatch))
}

pub fn invalid_provider_timezone_fails_closed_test() {
  let assert Ok(input) = domain.input("AAPL", "XNGS")
  let capture = complete_capture()
  let result =
    domain.assemble(
      input,
      domain.Capture(
        ..capture,
        statistics: response.Statistics(
          "AAPL",
          "Apple Inc.",
          "USD",
          "NASDAQ",
          "XNGS",
          "not a timezone",
          Some("14687356000"),
          Some("14569223952"),
        ),
      ),
    )
  case result {
    Error(domain.InvalidTimezone(_)) -> True |> should.be_true
    _ -> should.fail()
  }
}

pub fn receipt_endpoint_must_match_the_exact_provider_operation_test() {
  let assert Ok(input) = domain.input("AAPL", "XNGS")
  let capture = complete_capture()
  let assert Ok(hash) =
    identity.sha256(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
  domain.assemble(
    input,
    domain.Capture(
      ..capture,
      profile_receipt: domain.Receipt("/wrong", 10, hash, None, None, None),
    ),
  )
  |> should.equal(Error(domain.InvalidReceipt))
}

fn complete_capture() -> domain.Capture {
  let assert Ok(profile_hash) =
    identity.sha256(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
  let assert Ok(statistics_hash) =
    identity.sha256(
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    )
  let assert Ok(retrieved_at) = time.instant(1_786_227_200_000)
  domain.Capture(
    response.Profile(
      "AAPL",
      "Apple Inc.",
      "NASDAQ",
      "XNGS",
      Some("Technology"),
      Some("Consumer Electronics"),
      Some("150000"),
      Some("https://www.apple.com"),
      Some("Designs devices and services."),
      Some("Common Stock"),
      Some("Tim Cook"),
      Some("One Apple Park Way"),
      None,
      Some("Cupertino"),
      Some("95014"),
      Some("CA"),
      Some("United States"),
      Some("408-996-1010"),
    ),
    domain.Receipt(
      provider_request.profile_path,
      500,
      profile_hash,
      Some("10"),
      Some("550"),
      Some("10"),
    ),
    response.Statistics(
      "AAPL",
      "Apple Inc.",
      "USD",
      "NASDAQ",
      "XNGS",
      "America/New_York",
      Some("14687356000"),
      Some("14569223952"),
    ),
    domain.Receipt(
      provider_request.statistics_path,
      1000,
      statistics_hash,
      Some("60"),
      Some("500"),
      Some("50"),
    ),
    retrieved_at,
  )
}
