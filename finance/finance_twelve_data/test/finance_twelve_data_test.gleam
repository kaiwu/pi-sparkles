import finance_core/time
import finance_http/request as http_request
import finance_twelve_data
import finance_twelve_data/request
import finance_twelve_data/response
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn access_is_opaque_and_authorization_is_secret_test() {
  finance_twelve_data.access("short")
  |> should.equal(Error(finance_twelve_data.InvalidApiKey))
  let assert Ok(access) = finance_twelve_data.access("test-api-key-123")
  let assert Ok(value) = request.profile(access, "AAPL", "XNGS")
  http_request.origin(value) |> should.equal("https://api.twelvedata.com")
  http_request.path(value) |> should.equal("/profile")
  http_request.query(value)
  |> should.equal([
    http_request.QueryParameter("symbol", "AAPL", http_request.Public),
    http_request.QueryParameter("mic_code", "XNGS", http_request.Public),
    http_request.QueryParameter("country", "US", http_request.Public),
  ])
  http_request.headers(value)
  |> should.equal([
    http_request.Header("accept", "application/json", http_request.Public),
    http_request.Header(
      "authorization",
      "apikey test-api-key-123",
      http_request.Secret,
    ),
  ])
  http_request.timeout(value)
  |> time.duration_milliseconds
  |> should.equal(15_000)
}

pub fn request_rejects_noncanonical_symbols_and_unsupported_mics_test() {
  let assert Ok(access) = finance_twelve_data.access("test-api-key-123")
  request.profile(access, "aapl", "XNGS")
  |> should.equal(Error(request.InvalidSymbol))
  request.profile(access, "AAPL", "XHKG")
  |> should.equal(Error(request.UnsupportedMic))
}

pub fn profile_fixture_preserves_nullable_provider_fields_test() {
  let fixture =
    "{\"symbol\":\"AAPL\",\"name\":\"Apple Inc.\",\"exchange\":\"NASDAQ\",\"mic_code\":\"XNGS\",\"sector\":\"Technology\",\"industry\":\"Consumer Electronics\",\"employees\":150000,\"website\":\"https://www.apple.com\",\"description\":\"Designs devices and services.\",\"type\":\"Common Stock\",\"CEO\":\"Mr. Timothy D. Cook\",\"address\":\"One Apple Park Way\",\"address2\":null,\"city\":\"Cupertino\",\"zip\":\"95014\",\"state\":\"CA\",\"country\":\"United States\",\"phone\":\"408-996-1010\"}"
  let assert Ok(value) = response.decode_profile(fixture)
  value.symbol |> should.equal("AAPL")
  value.mic |> should.equal("XNGS")
  value.employees |> should.equal(Some("150000"))
  value.chief_executive |> should.equal(Some("Mr. Timothy D. Cook"))
  value.address_2 |> should.equal(None)
}

pub fn statistics_fixture_preserves_large_exact_share_lexemes_test() {
  let fixture =
    "{\"meta\":{\"symbol\":\"AAPL\",\"name\":\"Apple Inc.\",\"currency\":\"USD\",\"exchange\":\"NASDAQ\",\"mic_code\":\"XNGS\",\"exchange_timezone\":\"America/New_York\"},\"statistics\":{\"stock_statistics\":{\"shares_outstanding\":9007199254740993,\"float_shares\":14569223952}}}"
  let assert Ok(value) = response.decode_statistics(fixture)
  value.shares_outstanding |> should.equal(Some("9007199254740993"))
  value.float_shares |> should.equal(Some("14569223952"))
}

pub fn statistics_rejects_fractional_share_counts_test() {
  let fixture =
    "{\"meta\":{\"symbol\":\"AAPL\",\"name\":\"Apple Inc.\",\"currency\":\"USD\",\"exchange\":\"NASDAQ\",\"mic_code\":\"XNGS\",\"exchange_timezone\":\"America/New_York\"},\"statistics\":{\"stock_statistics\":{\"shares_outstanding\":1.5,\"float_shares\":1}}}"
  response.decode_statistics(fixture) |> should.be_error
}
