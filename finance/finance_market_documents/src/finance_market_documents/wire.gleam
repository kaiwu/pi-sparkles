import finance_core/currency
import finance_core/identifier
import finance_core/market
import finance_core/source
import finance_core/time
import finance_listing/listing
import finance_provenance/identity
import finance_track
import gleam/dynamic/decode
import gleam/json.{type Json}

/// Shared lossless wire primitives for market documents and their accounting
/// facts. Provider adapters may compose these codecs but may not weaken them.
pub fn listing_json(value: listing.Key) -> Json {
  json.object([
    #("track", json.string(finance_track.name(listing.track(value)))),
    #(
      "instrumentId",
      value
        |> listing.instrument_id
        |> identifier.instrument_id_value
        |> json.string,
    ),
    #(
      "symbol",
      value |> listing.symbol |> identifier.symbol_value |> json.string,
    ),
    #("mic", value |> listing.mic |> identifier.mic_value |> json.string),
  ])
}

pub fn listing_decoder() -> decode.Decoder(listing.Key) {
  use track <- decode.field("track", track_decoder())
  use instrument_value <- decode.field("instrumentId", decode.string)
  use symbol_value <- decode.field("symbol", decode.string)
  use mic_value <- decode.field("mic", decode.string)
  case
    identifier.instrument_id(instrument_value),
    identifier.symbol(symbol_value),
    identifier.mic(mic_value)
  {
    Ok(instrument), Ok(symbol), Ok(mic) ->
      decode.success(listing.new(track, instrument, symbol, mic))
    _, _, _ -> decode.failure(placeholder_listing(), "valid listing identity")
  }
}

pub fn date_json(value: time.Date) -> Json {
  let #(year, month, day) = time.date_parts(value)
  json.object([
    #("year", json.int(year)),
    #("month", json.int(month)),
    #("day", json.int(day)),
  ])
}

pub fn date_decoder() -> decode.Decoder(time.Date) {
  use year <- decode.field("year", decode.int)
  use month <- decode.field("month", decode.int)
  use day <- decode.field("day", decode.int)
  case time.date(year, month, day) {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(placeholder_date(), "valid Gregorian date")
  }
}

pub fn source_json(value: source.SourceRef) -> Json {
  json.object([
    #("provider", json.string(source.provider(value))),
    #("reference", json.string(source.reference(value))),
    #("kind", source_kind_json(source.kind(value))),
  ])
}

pub fn source_decoder() -> decode.Decoder(source.SourceRef) {
  use provider <- decode.field("provider", decode.string)
  use reference <- decode.field("reference", decode.string)
  use kind <- decode.field("kind", source_kind_decoder())
  case source.new(provider, reference, kind) {
    Ok(value) -> decode.success(value)
    Error(_) ->
      decode.failure(placeholder_source(), "valid safe source reference")
  }
}

pub fn evidence_id_json(value: identity.EvidenceId) -> Json {
  value |> identity.evidence_id_value |> json.string
}

pub fn evidence_id_decoder() -> decode.Decoder(identity.EvidenceId) {
  decode.string
  |> decode.then(fn(value) {
    case identity.sha256(value) {
      Ok(hash) -> decode.success(identity.evidence_id(hash))
      Error(_) ->
        decode.failure(placeholder_evidence_id(), "SHA-256 evidence id")
    }
  })
}

pub fn unit_json(value: market.Unit) -> Json {
  case value {
    market.Scalar -> tagged("scalar")
    market.Currency(value) -> tagged_value("currency", currency.code(value))
    market.CurrencyPerShare(value) ->
      tagged_value("currency_per_share", currency.code(value))
    market.Shares -> tagged("shares")
    market.Contracts -> tagged("contracts")
    market.Percent -> tagged("percent")
    market.BasisPoints -> tagged("basis_points")
    market.Ratio -> tagged("ratio")
    market.CustomUnit(value) -> tagged_value("custom", market.label(value))
  }
}

pub fn unit_decoder() -> decode.Decoder(market.Unit) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "scalar" -> decode.success(market.Scalar)
    "shares" -> decode.success(market.Shares)
    "contracts" -> decode.success(market.Contracts)
    "percent" -> decode.success(market.Percent)
    "basis_points" -> decode.success(market.BasisPoints)
    "ratio" -> decode.success(market.Ratio)
    "currency" -> currency_unit_decoder(False)
    "currency_per_share" -> currency_unit_decoder(True)
    "custom" -> {
      use value <- decode.field("value", decode.string)
      case market.custom_unit(value) {
        Ok(value) -> decode.success(value)
        Error(_) -> decode.failure(market.Scalar, "valid custom unit")
      }
    }
    _ -> decode.failure(market.Scalar, "known market unit")
  }
}

pub fn track_decoder() -> decode.Decoder(finance_track.Track) {
  decode.string
  |> decode.then(fn(value) {
    case finance_track.from_name(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(finance_track.Us, "cn, hk, or us track")
    }
  })
}

fn source_kind_json(value: source.SourceKind) -> Json {
  case value {
    source.Official -> tagged("official")
    source.Exchange -> tagged("exchange")
    source.Regulator -> tagged("regulator")
    source.LicensedVendor -> tagged("licensed_vendor")
    source.UserSupplied -> tagged("user_supplied")
    source.Synthetic -> tagged("synthetic")
    source.Other(value) -> tagged_value("other", value)
  }
}

fn source_kind_decoder() -> decode.Decoder(source.SourceKind) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "official" -> decode.success(source.Official)
    "exchange" -> decode.success(source.Exchange)
    "regulator" -> decode.success(source.Regulator)
    "licensed_vendor" -> decode.success(source.LicensedVendor)
    "user_supplied" -> decode.success(source.UserSupplied)
    "synthetic" -> decode.success(source.Synthetic)
    "other" -> {
      use value <- decode.field("value", decode.string)
      decode.success(source.Other(value))
    }
    _ -> decode.failure(source.Synthetic, "known source kind")
  }
}

fn currency_unit_decoder(per_share: Bool) -> decode.Decoder(market.Unit) {
  use code <- decode.field("value", decode.string)
  case currency.from_code(code) {
    Ok(value) ->
      case per_share {
        True -> decode.success(market.CurrencyPerShare(value))
        False -> decode.success(market.Currency(value))
      }
    Error(_) -> decode.failure(market.Scalar, "valid ISO currency")
  }
}

fn tagged(tag: String) -> Json {
  json.object([#("tag", json.string(tag))])
}

fn tagged_value(tag: String, value: String) -> Json {
  json.object([#("tag", json.string(tag)), #("value", json.string(value))])
}

fn placeholder_listing() -> listing.Key {
  let assert Ok(instrument) = identifier.instrument_id("wire-placeholder")
  let assert Ok(symbol) = identifier.symbol("PLACEHOLDER")
  let assert Ok(mic) = identifier.mic("XNAS")
  listing.new(finance_track.Us, instrument, symbol, mic)
}

fn placeholder_date() -> time.Date {
  let assert Ok(value) = time.date(1970, 1, 1)
  value
}

fn placeholder_source() -> source.SourceRef {
  let assert Ok(value) =
    source.new("wire-placeholder", "placeholder", source.Synthetic)
  value
}

fn placeholder_evidence_id() -> identity.EvidenceId {
  let assert Ok(hash) =
    identity.sha256(
      "0000000000000000000000000000000000000000000000000000000000000000",
    )
  identity.evidence_id(hash)
}
