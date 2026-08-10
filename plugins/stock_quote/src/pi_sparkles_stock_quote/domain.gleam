import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/observation
import finance_core/source
import finance_core/time
import finance_provenance/evidence
import finance_provenance/hash
import finance_provenance/identity
import finance_provenance/redact
import finance_quote
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pi_sparkles_stock_quote/decode

const maximum_safe_integer = 9_007_199_254_740_991

pub opaque type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
}

type SafeSource {
  SafeSource(value: source.SourceRef, reference_redacted: Bool)
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> Json {
  value.details
}

pub fn error_message(value: DomainError) -> String {
  let InvalidField(field, reason) = value
  "Invalid exact stock-quote field " <> field <> ": " <> reason
}

pub fn run(input: decode.Input) -> Result(Response, DomainError) {
  use track <- result.try(parse_track(input.track))
  use listing_id <- result.try(bounded_text(
    "listing.listingId",
    input.listing.listing_id,
    2000,
  ))
  use mic <- result.try(parse_mic(input.listing.mic))
  use _ <- result.try(validate_track_mic(track, mic))
  use symbol <- result.try(symbol(input.listing.symbol))
  use provider <- result.try(bounded_text(
    "source.provider",
    input.source.provider,
    200,
  ))
  use feed <- result.try(bounded_text("source.feed", input.source.feed, 200))
  use kind <- result.try(source_kind(input.source))
  use safe_source <- result.try(make_safe_source(
    provider,
    input.source.reference,
    kind,
  ))
  use receipt <- result.try(sha("source.receiptHash", input.source.receipt_hash))
  use licence <- result.try(licence(input.source.licence))
  use entitlement <- result.try(entitlement(input.source.entitlement))
  use as_of <- result.try(instant(
    "quote.asOfUnixMilliseconds",
    input.quote.as_of_unix_ms,
  ))
  use retrieved_at <- result.try(instant(
    "quote.retrievedAtUnixMilliseconds",
    input.quote.retrieved_at_unix_ms,
  ))
  use quote_currency <- result.try(parse_currency(input.quote.currency))
  use bid <- result.try(side("quote.bid", input.quote.bid))
  use ask <- result.try(side("quote.ask", input.quote.ask))
  use _ <- result.try(exact_size_unit(input.quote.size_unit))
  use _ <- result.try(count_bound(
    "quote.conditionCodes",
    input.quote.condition_codes,
    100,
  ))
  use quote <- result.try(
    finance_quote.quote(
      input.quote.provider_timestamp,
      as_of,
      quote_currency,
      bid,
      ask,
      input.quote.condition_codes,
      input.quote.tape,
      finance_quote.ProviderReportedSize,
    )
    |> result.map_error(fn(error) {
      InvalidField("quote", string.inspect(error))
    }),
  )
  let timezone = market_timezone(track)
  let receipt_text = identity.sha256_value(receipt)
  use observed <- result.try(
    finance_quote.observe_with_metadata(
      quote,
      retrieved_at: retrieved_at,
      timezone: timezone,
      source: safe_source.value,
      expected_provider: provider,
      evidence_id: Some(receipt_text),
      entitlement: entitlement,
    )
    |> result.map_error(fn(error) {
      InvalidField("quote", string.inspect(error))
    }),
  )
  let limitations = limitations()
  use context <- result.try(
    track_context.new(
      track: track,
      market_scope: finance_track.name(track) <> "_stock_quote",
      venue_mic: Some(mic),
      board: None,
      timezone: Some(timezone),
      source_language: source_language(track),
      providers: [provider],
      entitlement: context_entitlement(entitlement),
      limitations: limitations,
    )
    |> result.map_error(fn(error) {
      InvalidField("trackContext", string.inspect(error))
    }),
  )
  Ok(Response(
    finance_track.name(track)
      <> " quote | "
      <> symbol
      <> " @ "
      <> identifier.mic_value(mic)
      <> " | bid "
      <> finance_quote.raw(finance_quote.price(finance_quote.bid(quote)))
      <> " ask "
      <> finance_quote.raw(finance_quote.price(finance_quote.ask(quote)))
      <> " "
      <> currency.code(quote_currency),
    json.object(
      list.append(track_json.result_fields(context), [
        #("schemaVersion", json.int(1)),
        #("operation", json.string("stock_quote")),
        #(
          "listing",
          json.object([
            #("listingId", json.string(listing_id)),
            #("mic", json.string(identifier.mic_value(mic))),
            #("symbol", json.string(symbol)),
            #("identityStatus", json.string("caller_supplied_unverified")),
          ]),
        ),
        #("observation", observation_json(observed)),
        #("source", source_json(safe_source, kind, feed, receipt_text)),
        #("licence", licence_json(licence)),
        #(
          "unknownFacts",
          json.array(
            [
              "freshness",
              "latency",
              "market_session",
              "listing_identity_authority",
              "provider_size_semantics",
              "locked_or_crossed_quote_interpretation",
            ],
            json.string,
          ),
        ),
        #("conflictAssessment", json.string("not_performed_single_observation")),
        #("decisionOwner", json.string("llm")),
        #(
          "pluginDecisionFields",
          json.array([], fn(value: String) { json.string(value) }),
        ),
        #("limitations", json.array(limitations, json.string)),
      ]),
    ),
  ))
}

fn parse_track(value: String) -> Result(finance_track.Track, DomainError) {
  finance_track.from_name(value)
  |> result.map_error(fn(_) {
    InvalidField("track", "expected exactly cn, hk, or us")
  })
}

fn parse_mic(value: String) -> Result(identifier.Mic, DomainError) {
  use parsed <- result.try(
    identifier.mic(value)
    |> result.map_error(fn(_) {
      InvalidField("listing.mic", "expected an exact four-character MIC")
    }),
  )
  case identifier.mic_value(parsed) == value {
    True -> Ok(parsed)
    False ->
      Error(InvalidField(
        "listing.mic",
        "MIC must already use its exact uppercase representation",
      ))
  }
}

fn validate_track_mic(
  track: finance_track.Track,
  mic: identifier.Mic,
) -> Result(Nil, DomainError) {
  let value = identifier.mic_value(mic)
  let allowed = case track {
    finance_track.Cn -> ["XSHG", "XSHE", "XBSE"]
    finance_track.Hk -> ["XHKG"]
    finance_track.Us -> ["XNYS", "XNAS"]
  }
  case list.contains(allowed, value) {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "listing.mic",
        "MIC is outside the first-slice allowlist for explicit track "
          <> finance_track.name(track)
          <> ": "
          <> string.join(allowed, ", "),
      ))
  }
}

fn symbol(value: String) -> Result(String, DomainError) {
  use exact <- result.try(bounded_text("listing.symbol", value, 100))
  case
    exact
    |> string.to_graphemes
    |> list.all(fn(character) { string.trim(character) == character })
  {
    True -> Ok(exact)
    False ->
      Error(InvalidField(
        "listing.symbol",
        "expected an exact provider symbol without whitespace",
      ))
  }
}

fn parse_currency(value: String) -> Result(currency.Currency, DomainError) {
  use parsed <- result.try(
    currency.from_code(value)
    |> result.map_error(fn(_) {
      InvalidField("quote.currency", "expected a three-letter currency code")
    }),
  )
  case currency.code(parsed) == value {
    True -> Ok(parsed)
    False ->
      Error(InvalidField(
        "quote.currency",
        "currency must already use its exact uppercase representation",
      ))
  }
}

fn side(
  field: String,
  value: decode.SideInput,
) -> Result(finance_quote.Side, DomainError) {
  use raw_price <- result.try(bounded_text(
    field <> ".rawPrice",
    value.raw_price,
    500,
  ))
  use raw_size <- result.try(bounded_text(
    field <> ".rawSize",
    value.raw_size,
    500,
  ))
  use price <- result.try(
    finance_quote.exact(raw_price)
    |> result.map_error(fn(_) {
      InvalidField(field <> ".rawPrice", "expected an exact decimal lexeme")
    }),
  )
  use size <- result.try(
    finance_quote.exact(raw_size)
    |> result.map_error(fn(_) {
      InvalidField(field <> ".rawSize", "expected an exact decimal lexeme")
    }),
  )
  finance_quote.side(value.exchange, price, size)
  |> result.map_error(fn(error) { InvalidField(field, string.inspect(error)) })
}

fn exact_size_unit(value: String) -> Result(Nil, DomainError) {
  case value {
    "provider_reported_unverified" -> Ok(Nil)
    _ ->
      Error(InvalidField(
        "quote.sizeUnit",
        "expected provider_reported_unverified; the shell does not infer lot or share semantics",
      ))
  }
}

fn source_kind(
  value: decode.SourceInput,
) -> Result(source.SourceKind, DomainError) {
  case value.kind, value.other_kind {
    "official", None -> Ok(source.Official)
    "exchange", None -> Ok(source.Exchange)
    "regulator", None -> Ok(source.Regulator)
    "licensed_vendor", None -> Ok(source.LicensedVendor)
    "user_supplied", None -> Ok(source.UserSupplied)
    "synthetic", None -> Ok(source.Synthetic)
    "other", Some(kind) -> {
      use exact <- result.try(bounded_text("source.otherKind", kind, 200))
      Ok(source.Other(exact))
    }
    "other", None ->
      Error(InvalidField(
        "source.otherKind",
        "other source kind requires exact otherKind text",
      ))
    _, Some(_) ->
      Error(InvalidField(
        "source.otherKind",
        "otherKind is only allowed when kind is other",
      ))
    _, None ->
      Error(InvalidField("source.kind", "unsupported explicit source kind"))
  }
}

fn make_safe_source(
  provider: String,
  raw_reference: String,
  kind: source.SourceKind,
) -> Result(SafeSource, DomainError) {
  use _ <- result.try(bounded_text("source.reference", raw_reference, 8000))
  let projected = redact.url(raw_reference, [])
  case source.new(provider, projected, kind) {
    Ok(value) -> Ok(SafeSource(value, projected != raw_reference))
    Error(source.UnsafeReference) -> {
      use digest <- result.try(
        hash.text(raw_reference)
        |> result.map_error(fn(_) {
          InvalidField("source.reference", "safe reference hashing failed")
        }),
      )
      let fallback =
        "redacted-reference:sha256:" <> identity.sha256_value(digest)
      source.new(provider, fallback, kind)
      |> result.map(fn(value) { SafeSource(value, True) })
      |> result.map_error(fn(_) {
        InvalidField("source.reference", "could not construct a safe source")
      })
    }
    Error(_) ->
      Error(InvalidField(
        "source.reference",
        "expected trimmed non-empty source reference",
      ))
  }
}

fn entitlement(
  value: decode.EntitlementInput,
) -> Result(observation.Entitlement, DomainError) {
  case value.state, value.delay_milliseconds {
    "real_time", None -> Ok(observation.RealTime)
    "end_of_day", None -> Ok(observation.EndOfDay)
    "unknown", None -> Ok(observation.UnknownEntitlement)
    "delayed", Some(milliseconds) -> {
      use _ <- result.try(integer_range(
        "source.entitlement.delayMilliseconds",
        milliseconds,
        1,
        maximum_safe_integer,
      ))
      time.duration(milliseconds)
      |> result.map(observation.Delayed)
      |> result.map_error(fn(_) {
        InvalidField(
          "source.entitlement.delayMilliseconds",
          "delay is outside the supported duration range",
        )
      })
    }
    _, _ ->
      Error(InvalidField(
        "source.entitlement",
        "real_time, end_of_day, and unknown forbid delayMilliseconds; delayed requires it",
      ))
  }
}

fn licence(
  value: decode.LicenceInput,
) -> Result(evidence.Licence, DomainError) {
  use label <- result.try(bounded_text("source.licence.label", value.label, 500))
  use notes <- result.try(optional_bounded_text(
    "source.licence.notes",
    value.notes,
    4000,
  ))
  use redistribution <- result.try(redistribution(value.redistribution))
  Ok(evidence.Licence(label, redistribution, notes))
}

fn redistribution(
  value: String,
) -> Result(evidence.Redistribution, DomainError) {
  case value {
    "public_domain" -> Ok(evidence.PublicDomain)
    "attribution_required" -> Ok(evidence.AttributionRequired)
    "internal_use_only" -> Ok(evidence.InternalUseOnly)
    "no_redistribution" -> Ok(evidence.NoRedistribution)
    "unknown" -> Ok(evidence.UnknownRedistribution)
    _ ->
      Error(InvalidField(
        "source.licence.redistribution",
        "unsupported explicit redistribution state",
      ))
  }
}

fn instant(field: String, value: Int) -> Result(time.Instant, DomainError) {
  use _ <- result.try(integer_range(field, value, 0, maximum_safe_integer))
  time.instant(value)
  |> result.map_error(fn(_) { InvalidField(field, "instant is out of range") })
}

fn market_timezone(track: finance_track.Track) -> time.Timezone {
  let name = case track {
    finance_track.Cn -> "Asia/Shanghai"
    finance_track.Hk -> "Asia/Hong_Kong"
    finance_track.Us -> "America/New_York"
  }
  let assert Ok(value) = time.timezone(name)
  value
}

fn source_language(track: finance_track.Track) -> String {
  case track {
    finance_track.Cn -> "zh-CN"
    finance_track.Hk -> "zh-HK"
    finance_track.Us -> "en-US"
  }
}

fn context_entitlement(value: observation.Entitlement) -> String {
  case value {
    observation.RealTime -> "declared_real_time"
    observation.Delayed(_) -> "declared_delayed"
    observation.EndOfDay -> "declared_end_of_day"
    observation.UnknownEntitlement -> "unknown"
  }
}

fn observation_json(
  observed: observation.Observation(finance_quote.Quote),
) -> Json {
  let quote = observed.value
  json.object([
    #("kind", json.string("finance_quote")),
    #("providerTimestamp", json.string(finance_quote.source_timestamp(quote))),
    #("asOfUnixMilliseconds", json.int(time.unix_milliseconds(observed.as_of))),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(observed.retrieved_at)),
    ),
    #(
      "timezone",
      json.nullable(observed.timezone, fn(zone) {
        json.string(time.timezone_name(zone))
      }),
    ),
    #("currency", json.string(currency.code(finance_quote.currency(quote)))),
    #("bid", side_json(finance_quote.bid(quote))),
    #("ask", side_json(finance_quote.ask(quote))),
    #(
      "conditionCodes",
      json.array(finance_quote.conditions(quote), json.string),
    ),
    #("tape", json.string(finance_quote.tape(quote))),
    #("sizeUnit", json.string("provider_reported_unverified")),
    #("evidenceId", json.nullable(observed.evidence_id, json.string)),
    #("freshness", json.object([#("state", json.string("unknown"))])),
    #("entitlement", entitlement_json(observed.entitlement)),
    #("quality", json.string("reported")),
    #(
      "unit",
      json.object([
        #("kind", json.string("currency_per_share")),
        #("currency", json.string(currency.code(finance_quote.currency(quote)))),
      ]),
    ),
    #("adjustment", json.null()),
    #("session", json.null()),
  ])
}

fn side_json(value: finance_quote.Side) -> Json {
  json.object([
    #("exchange", json.string(finance_quote.exchange(value))),
    #("rawPrice", json.string(finance_quote.raw(finance_quote.price(value)))),
    #(
      "normalizedPrice",
      json.string(
        value
        |> finance_quote.price
        |> finance_quote.normalized
        |> decimal.to_string,
      ),
    ),
    #("rawSize", json.string(finance_quote.raw(finance_quote.size(value)))),
    #(
      "normalizedSize",
      json.string(
        value
        |> finance_quote.size
        |> finance_quote.normalized
        |> decimal.to_string,
      ),
    ),
  ])
}

fn source_json(
  safe: SafeSource,
  kind: source.SourceKind,
  feed: String,
  receipt_hash: String,
) -> Json {
  json.object([
    #("provider", json.string(source.provider(safe.value))),
    #("reference", json.string(source.reference(safe.value))),
    #("referenceRedacted", json.bool(safe.reference_redacted)),
    #("kind", json.string(source_kind_name(kind))),
    #("otherKind", json.nullable(source_other_kind(kind), json.string)),
    #("feed", json.string(feed)),
    #("receiptHash", json.string(receipt_hash)),
    #("receiptBinding", json.string("caller_supplied_unverified")),
  ])
}

fn source_kind_name(value: source.SourceKind) -> String {
  case value {
    source.Official -> "official"
    source.Exchange -> "exchange"
    source.Regulator -> "regulator"
    source.LicensedVendor -> "licensed_vendor"
    source.UserSupplied -> "user_supplied"
    source.Synthetic -> "synthetic"
    source.Other(_) -> "other"
  }
}

fn source_other_kind(value: source.SourceKind) -> Option(String) {
  case value {
    source.Other(kind) -> Some(kind)
    _ -> None
  }
}

fn entitlement_json(value: observation.Entitlement) -> Json {
  let #(state, delay) = case value {
    observation.RealTime -> #("real_time", None)
    observation.Delayed(value) -> #(
      "delayed",
      Some(time.duration_milliseconds(value)),
    )
    observation.EndOfDay -> #("end_of_day", None)
    observation.UnknownEntitlement -> #("unknown", None)
  }
  json.object([
    #("state", json.string(state)),
    #("delayMilliseconds", json.nullable(delay, json.int)),
    #("status", json.string("caller_or_provider_adapter_declared_unverified")),
  ])
}

fn licence_json(value: evidence.Licence) -> Json {
  json.object([
    #("label", json.string(value.label)),
    #("redistribution", json.string(redistribution_name(value.redistribution))),
    #("notes", json.nullable(value.notes, json.string)),
    #("status", json.string("caller_or_provider_adapter_declared_unverified")),
  ])
}

fn redistribution_name(value: evidence.Redistribution) -> String {
  case value {
    evidence.PublicDomain -> "public_domain"
    evidence.AttributionRequired -> "attribution_required"
    evidence.InternalUseOnly -> "internal_use_only"
    evidence.NoRedistribution -> "no_redistribution"
    evidence.UnknownRedistribution -> "unknown"
  }
}

fn limitations() -> List(String) {
  [
    "caller_supplied_listing_identity_not_verified",
    "source_receipt_hash_not_origin_authentication",
    "licence_and_entitlement_are_caller_or_adapter_declarations",
    "freshness_latency_and_session_unknown",
    "provider_size_semantics_unverified",
    "single_observation_no_conflict_reconciliation",
    "no_network_provider_selection_fallback_or_trading_decision",
  ]
}

fn sha(field: String, value: String) -> Result(identity.Sha256, DomainError) {
  use parsed <- result.try(
    identity.sha256(value)
    |> result.map_error(fn(_) {
      InvalidField(field, "expected an exact SHA-256 hexadecimal string")
    }),
  )
  case identity.sha256_value(parsed) == value {
    True -> Ok(parsed)
    False ->
      Error(InvalidField(
        field,
        "SHA-256 must already use its canonical lowercase representation",
      ))
  }
}

fn bounded_text(
  field: String,
  value: String,
  maximum: Int,
) -> Result(String, DomainError) {
  case
    value != ""
    && string.trim(value) == value
    && string.length(value) <= maximum
    && !string.contains(value, "\r")
    && !string.contains(value, "\n")
    && !string.contains(value, "\t")
  {
    True -> Ok(value)
    False ->
      Error(InvalidField(
        field,
        "expected trimmed non-empty text within "
          <> int.to_string(maximum)
          <> " characters",
      ))
  }
}

fn optional_bounded_text(
  field: String,
  value: Option(String),
  maximum: Int,
) -> Result(Option(String), DomainError) {
  case value {
    None -> Ok(None)
    Some(value) -> {
      use exact <- result.try(bounded_text(field, value, maximum))
      Ok(Some(exact))
    }
  }
}

fn integer_range(
  field: String,
  value: Int,
  minimum: Int,
  maximum: Int,
) -> Result(Nil, DomainError) {
  case value >= minimum && value <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "expected integer from "
          <> int.to_string(minimum)
          <> " through "
          <> int.to_string(maximum),
      ))
  }
}

fn count_bound(
  field: String,
  values: List(value),
  maximum: Int,
) -> Result(Nil, DomainError) {
  case list.length(values) <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "expected at most " <> int.to_string(maximum) <> " entries",
      ))
  }
}
