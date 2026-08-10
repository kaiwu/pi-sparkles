import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_quote/decode
import pi_sparkles_stock_quote/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_cn_hk_us_quotes_retain_track_listing_and_source_lexemes_test() {
  let assert Ok(cn) = domain.run(input("cn", "XSHG", "600519", "CNY"))
  let assert Ok(hk) = domain.run(input("hk", "XHKG", "00700", "HKD"))
  let assert Ok(us) = domain.run(input("us", "XNAS", "AAPL", "USD"))

  contains(details(cn), "\"track\":\"cn\"")
  contains(details(cn), "\"timezone\":\"Asia/Shanghai\"")
  contains(details(hk), "\"track\":\"hk\"")
  contains(details(hk), "\"mic\":\"XHKG\"")
  contains(details(us), "\"track\":\"us\"")
  contains(details(us), "\"rawPrice\":\"189.1000\"")
  contains(details(us), "\"normalizedPrice\":\"189.1\"")
  contains(details(us), "\"rawSize\":\"7.00\"")
  contains(details(us), "\"normalizedSize\":\"7\"")
}

pub fn declared_entitlement_licence_and_receipt_survive_without_verification_test() {
  let base = input("us", "XNYS", "IBM", "USD")
  let source = base.source
  let delayed = decode.EntitlementInput("delayed", Some(900_000))
  let assert Ok(response) =
    domain.run(
      decode.Input(
        ..base,
        source: decode.SourceInput(..source, entitlement: delayed),
      ),
    )
  let text = details(response)
  contains(text, "\"state\":\"delayed\"")
  contains(text, "\"delayMilliseconds\":900000")
  contains(text, "\"evidenceId\":\"" <> receipt() <> "\"")
  contains(text, "\"redistribution\":\"no_redistribution\"")
  contains(text, "caller_or_provider_adapter_declared_unverified")
  contains(text, "\"receiptBinding\":\"caller_supplied_unverified\"")
}

pub fn crossed_quote_is_retained_and_not_interpreted_test() {
  let base = input("us", "XNAS", "AAPL", "USD")
  let quote = base.quote
  let crossed =
    decode.QuoteInput(
      ..quote,
      bid: decode.SideInput("V", "190.00", "1"),
      ask: decode.SideInput("V", "189.00", "1"),
    )
  let assert Ok(response) = domain.run(decode.Input(..base, quote: crossed))
  let text = details(response)
  contains(text, "\"rawPrice\":\"190.00\"")
  contains(text, "\"conflictAssessment\":\"not_performed_single_observation\"")
  contains(text, "locked_or_crossed_quote_interpretation")
  excludes(text, "verdict")
  excludes(text, "recommend")
}

pub fn track_mic_mismatch_and_normalized_identity_inputs_fail_closed_test() {
  case domain.run(input("cn", "XNAS", "AAPL", "USD")) {
    Error(domain.InvalidField("listing.mic", _)) -> Nil
    _ -> should.fail()
  }
  case domain.run(input("us", "xnas", "AAPL", "USD")) {
    Error(domain.InvalidField("listing.mic", _)) -> Nil
    _ -> should.fail()
  }
  case domain.run(input("us", "XNAS", "AAPL", "usd")) {
    Error(domain.InvalidField("quote.currency", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn invalid_time_decimal_size_and_entitlement_variants_fail_closed_test() {
  let base = input("us", "XNAS", "AAPL", "USD")
  let quote = base.quote
  case
    domain.run(
      decode.Input(
        ..base,
        quote: decode.QuoteInput(..quote, retrieved_at_unix_ms: 999),
      ),
    )
  {
    Error(domain.InvalidField("quote", _)) -> Nil
    _ -> should.fail()
  }
  case
    domain.run(
      decode.Input(
        ..base,
        quote: decode.QuoteInput(..quote, bid: decode.SideInput("V", "-1", "7")),
      ),
    )
  {
    Error(domain.InvalidField("quote.bid", _)) -> Nil
    _ -> should.fail()
  }
  case
    domain.run(
      decode.Input(
        ..base,
        quote: decode.QuoteInput(..quote, size_unit: "shares"),
      ),
    )
  {
    Error(domain.InvalidField("quote.sizeUnit", _)) -> Nil
    _ -> should.fail()
  }
  case
    domain.run(
      decode.Input(
        ..base,
        quote: decode.QuoteInput(..quote, condition_codes: list_of("R", 101)),
      ),
    )
  {
    Error(domain.InvalidField("quote.conditionCodes", _)) -> Nil
    _ -> should.fail()
  }
  let source = base.source
  case
    domain.run(
      decode.Input(
        ..base,
        source: decode.SourceInput(
          ..source,
          entitlement: decode.EntitlementInput("delayed", None),
        ),
      ),
    )
  {
    Error(domain.InvalidField("source.entitlement", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn unsafe_source_reference_is_redacted_and_never_leaks_test() {
  let secret = "do-not-leak"
  let base = input("hk", "XHKG", "00700", "HKD")
  let source = base.source
  let assert Ok(response) =
    domain.run(
      decode.Input(
        ..base,
        source: decode.SourceInput(
          ..source,
          reference: "https://user:password@example.test/quote?api_key="
            <> secret
            <> "#fragment",
        ),
      ),
    )
  let text = details(response)
  text |> string.contains(secret) |> should.be_false
  text |> string.contains("user:password") |> should.be_false
  text |> string.contains("#fragment") |> should.be_false
  contains(text, "\"referenceRedacted\":true")
}

pub fn source_and_licence_variants_are_strict_test() {
  let base = input("cn", "XSHE", "000001", "CNY")
  let source = base.source
  case
    domain.run(
      decode.Input(
        ..base,
        source: decode.SourceInput(..source, kind: "other", other_kind: None),
      ),
    )
  {
    Error(domain.InvalidField("source.otherKind", _)) -> Nil
    _ -> should.fail()
  }
  case
    domain.run(
      decode.Input(
        ..base,
        source: decode.SourceInput(..source, receipt_hash: "not-a-receipt"),
      ),
    )
  {
    Error(domain.InvalidField("source.receiptHash", _)) -> Nil
    _ -> should.fail()
  }
  let licence = source.licence
  case
    domain.run(
      decode.Input(
        ..base,
        source: decode.SourceInput(
          ..source,
          licence: decode.LicenceInput(
            ..licence,
            redistribution: "claimed_open",
          ),
        ),
      ),
    )
  {
    Error(domain.InvalidField("source.licence.redistribution", _)) -> Nil
    _ -> should.fail()
  }
}

fn input(
  track: String,
  mic: String,
  symbol: String,
  currency: String,
) -> decode.Input {
  decode.Input(
    track,
    decode.ListingInput("listing:" <> symbol, mic, symbol),
    decode.QuoteInput(
      "2026-08-10T10:00:00.123456789Z",
      1000,
      2000,
      currency,
      decode.SideInput("BID", "189.1000", "7.00"),
      decode.SideInput("ASK", "189.1200", "4"),
      ["R"],
      "C",
      "provider_reported_unverified",
    ),
    decode.SourceInput(
      "fixture-adapter",
      "https://example.test/quote?symbol=" <> symbol,
      "licensed_vendor",
      None,
      "fixture-feed",
      decode.EntitlementInput("real_time", None),
      decode.LicenceInput(
        "fixture-contract",
        "no_redistribution",
        Some("local analysis only"),
      ),
      receipt(),
    ),
  )
}

fn receipt() -> String {
  string.repeat("a", 64)
}

fn list_of(value: String, count: Int) -> List(String) {
  case count {
    0 -> []
    _ -> [value, ..list_of(value, count - 1)]
  }
}

fn details(value: domain.Response) -> String {
  value |> domain.details |> json.to_string
}

fn contains(value: String, expected: String) -> Nil {
  value |> string.contains(expected) |> should.be_true
}

fn excludes(value: String, expected: String) -> Nil {
  value |> string.contains(expected) |> should.be_false
}
