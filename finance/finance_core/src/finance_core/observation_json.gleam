import finance_core/adjustment
import finance_core/currency
import finance_core/market
import finance_core/observation
import finance_core/source
import finance_core/time
import gleam/dynamic/decode
import gleam/json.{type Json}

pub const schema_version = 1

pub fn encode(
  value: observation.Observation(value),
  encode_value: fn(value) -> Json,
) -> String {
  value
  |> to_json(encode_value)
  |> json.to_string
}

pub fn to_json(
  value: observation.Observation(value),
  encode_value: fn(value) -> Json,
) -> Json {
  json.object([
    #("schemaVersion", json.int(schema_version)),
    #("value", encode_value(value.value)),
    #("asOfUnixMs", json.int(time.unix_milliseconds(value.as_of))),
    #("retrievedAtUnixMs", json.int(time.unix_milliseconds(value.retrieved_at))),
    #("source", source_json(value.source)),
    #("evidenceId", json.nullable(value.evidence_id, json.string)),
    #("freshness", freshness_json(value.freshness)),
    #("entitlement", entitlement_json(value.entitlement)),
    #("quality", quality_json(value.quality)),
    #("unit", json.nullable(value.unit, unit_json)),
    #("adjustment", json.nullable(value.adjustment, adjustment_json)),
    #("session", json.nullable(value.session, session_json)),
  ])
}

pub fn decode(
  input: String,
  value_decoder: decode.Decoder(value),
) -> Result(observation.Observation(value), json.DecodeError) {
  json.parse(input, observation_decoder(value_decoder))
}

pub fn observation_decoder(
  value_decoder: decode.Decoder(value),
) -> decode.Decoder(observation.Observation(value)) {
  use _version <- decode.field("schemaVersion", version_decoder())
  use value <- decode.field("value", value_decoder)
  use as_of <- decode.field("asOfUnixMs", instant_decoder())
  use retrieved_at <- decode.field("retrievedAtUnixMs", instant_decoder())
  use source <- decode.field("source", source_decoder())
  use evidence_id <- decode.field("evidenceId", decode.optional(decode.string))
  use freshness <- decode.field("freshness", freshness_decoder())
  use entitlement <- decode.field("entitlement", entitlement_decoder())
  use quality <- decode.field("quality", quality_decoder())
  use unit <- decode.field("unit", decode.optional(unit_decoder()))
  use adjustment <- decode.field(
    "adjustment",
    decode.optional(adjustment_decoder()),
  )
  use session <- decode.field("session", decode.optional(session_decoder()))
  decode.success(observation.Observation(
    value: value,
    as_of: as_of,
    retrieved_at: retrieved_at,
    source: source,
    evidence_id: evidence_id,
    freshness: freshness,
    entitlement: entitlement,
    quality: quality,
    unit: unit,
    adjustment: adjustment,
    session: session,
  ))
}

fn version_decoder() -> decode.Decoder(Int) {
  decode.int
  |> decode.then(fn(version) {
    case version == schema_version {
      True -> decode.success(version)
      False -> decode.failure(schema_version, "finance observation schema v1")
    }
  })
}

fn instant_decoder() -> decode.Decoder(time.Instant) {
  let assert Ok(placeholder) = time.instant(0)
  decode.int
  |> decode.then(fn(milliseconds) {
    case time.instant(milliseconds) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder, "safe Unix milliseconds")
    }
  })
}

fn duration_decoder() -> decode.Decoder(time.Duration) {
  let assert Ok(placeholder) = time.duration(0)
  decode.int
  |> decode.then(fn(milliseconds) {
    case time.duration(milliseconds) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder, "non-negative duration")
    }
  })
}

fn source_json(value: source.SourceRef) -> Json {
  json.object([
    #("provider", json.string(source.provider(value))),
    #("reference", json.string(source.reference(value))),
    #("kind", source_kind_json(source.kind(value))),
  ])
}

fn source_decoder() -> decode.Decoder(source.SourceRef) {
  use provider <- decode.field("provider", decode.string)
  use reference <- decode.field("reference", decode.string)
  use kind <- decode.field("kind", source_kind_decoder())
  case source.new(provider: provider, reference: reference, kind: kind) {
    Ok(value) -> decode.success(value)
    Error(_) ->
      decode.failure(placeholder_source(), "valid safe source reference")
  }
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

fn freshness_json(value: observation.Freshness) -> Json {
  case value {
    observation.Fresh(maximum_age) ->
      tagged_duration("fresh", "maximumAgeMs", maximum_age)
    observation.Stale(age, maximum_age) ->
      json.object([
        #("tag", json.string("stale")),
        #("ageMs", json.int(time.duration_milliseconds(age))),
        #("maximumAgeMs", json.int(time.duration_milliseconds(maximum_age))),
      ])
    observation.UnknownFreshness -> tagged("unknown")
  }
}

fn freshness_decoder() -> decode.Decoder(observation.Freshness) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "fresh" -> {
      use maximum_age <- decode.field("maximumAgeMs", duration_decoder())
      decode.success(observation.Fresh(maximum_age))
    }
    "stale" -> {
      use age <- decode.field("ageMs", duration_decoder())
      use maximum_age <- decode.field("maximumAgeMs", duration_decoder())
      decode.success(observation.Stale(age, maximum_age))
    }
    "unknown" -> decode.success(observation.UnknownFreshness)
    _ -> decode.failure(observation.UnknownFreshness, "known freshness state")
  }
}

fn entitlement_json(value: observation.Entitlement) -> Json {
  case value {
    observation.RealTime -> tagged("real_time")
    observation.Delayed(delay) -> tagged_duration("delayed", "delayMs", delay)
    observation.EndOfDay -> tagged("end_of_day")
    observation.UnknownEntitlement -> tagged("unknown")
  }
}

fn entitlement_decoder() -> decode.Decoder(observation.Entitlement) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "real_time" -> decode.success(observation.RealTime)
    "delayed" -> {
      use delay <- decode.field("delayMs", duration_decoder())
      decode.success(observation.Delayed(delay))
    }
    "end_of_day" -> decode.success(observation.EndOfDay)
    "unknown" -> decode.success(observation.UnknownEntitlement)
    _ -> decode.failure(observation.UnknownEntitlement, "known entitlement")
  }
}

fn quality_json(value: observation.Quality) -> Json {
  case value {
    observation.Reported -> tagged("reported")
    observation.Estimated -> tagged("estimated")
    observation.Restated -> tagged("restated")
    observation.Revised -> tagged("revised")
    observation.Missing(reason) ->
      json.object([
        #("tag", json.string("missing")),
        #("reason", json.string(missing_reason_tag(reason))),
      ])
  }
}

fn quality_decoder() -> decode.Decoder(observation.Quality) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "reported" -> decode.success(observation.Reported)
    "estimated" -> decode.success(observation.Estimated)
    "restated" -> decode.success(observation.Restated)
    "revised" -> decode.success(observation.Revised)
    "missing" -> {
      use reason <- decode.field("reason", missing_reason_decoder())
      decode.success(observation.Missing(reason))
    }
    _ -> decode.failure(observation.Reported, "known quality state")
  }
}

fn missing_reason_tag(value: observation.MissingReason) -> String {
  case value {
    observation.NotReported -> "not_reported"
    observation.NotApplicable -> "not_applicable"
    observation.Unavailable -> "unavailable"
    observation.Suppressed -> "suppressed"
    observation.ParseFailure -> "parse_failure"
  }
}

fn missing_reason_decoder() -> decode.Decoder(observation.MissingReason) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "not_reported" -> decode.success(observation.NotReported)
      "not_applicable" -> decode.success(observation.NotApplicable)
      "unavailable" -> decode.success(observation.Unavailable)
      "suppressed" -> decode.success(observation.Suppressed)
      "parse_failure" -> decode.success(observation.ParseFailure)
      _ -> decode.failure(observation.Unavailable, "known missing reason")
    }
  })
}

fn unit_json(value: market.Unit) -> Json {
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

fn unit_decoder() -> decode.Decoder(market.Unit) {
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
    _ -> decode.failure(market.Scalar, "known unit")
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
    Error(_) -> decode.failure(market.Scalar, "valid ISO currency unit")
  }
}

fn adjustment_json(value: adjustment.Adjustment) -> Json {
  case value {
    adjustment.Raw -> tagged("raw")
    adjustment.SplitAdjusted -> tagged("split_adjusted")
    adjustment.DividendAdjusted -> tagged("dividend_adjusted")
    adjustment.TotalReturnAdjusted -> tagged("total_return_adjusted")
    adjustment.ProviderAdjusted(value) ->
      json.object([
        #("tag", json.string("provider_adjusted")),
        #("provider", json.string(adjustment.provider(value))),
        #("basis", json.string(adjustment.basis(value))),
      ])
  }
}

fn adjustment_decoder() -> decode.Decoder(adjustment.Adjustment) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "raw" -> decode.success(adjustment.Raw)
    "split_adjusted" -> decode.success(adjustment.SplitAdjusted)
    "dividend_adjusted" -> decode.success(adjustment.DividendAdjusted)
    "total_return_adjusted" -> decode.success(adjustment.TotalReturnAdjusted)
    "provider_adjusted" -> {
      use provider <- decode.field("provider", decode.string)
      use basis <- decode.field("basis", decode.string)
      case adjustment.provider_adjusted(provider: provider, basis: basis) {
        Ok(value) -> decode.success(value)
        Error(_) -> decode.failure(adjustment.Raw, "valid provider adjustment")
      }
    }
    _ -> decode.failure(adjustment.Raw, "known adjustment")
  }
}

fn session_json(value: market.Session) -> Json {
  case value {
    market.PreMarket -> tagged("pre_market")
    market.Regular -> tagged("regular")
    market.AfterHours -> tagged("after_hours")
    market.Auction -> tagged("auction")
    market.Closed -> tagged("closed")
    market.OtherSession(value) -> tagged_value("other", market.label(value))
  }
}

fn session_decoder() -> decode.Decoder(market.Session) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "pre_market" -> decode.success(market.PreMarket)
    "regular" -> decode.success(market.Regular)
    "after_hours" -> decode.success(market.AfterHours)
    "auction" -> decode.success(market.Auction)
    "closed" -> decode.success(market.Closed)
    "other" -> {
      use value <- decode.field("value", decode.string)
      case market.other_session(value) {
        Ok(value) -> decode.success(value)
        Error(_) -> decode.failure(market.Closed, "valid custom session")
      }
    }
    _ -> decode.failure(market.Closed, "known market session")
  }
}

fn tagged(tag: String) -> Json {
  json.object([#("tag", json.string(tag))])
}

fn tagged_value(tag: String, value: String) -> Json {
  json.object([
    #("tag", json.string(tag)),
    #("value", json.string(value)),
  ])
}

fn tagged_duration(tag: String, field: String, value: time.Duration) -> Json {
  json.object([
    #("tag", json.string(tag)),
    #(field, json.int(time.duration_milliseconds(value))),
  ])
}

fn placeholder_source() -> source.SourceRef {
  let assert Ok(value) =
    source.new(
      provider: "placeholder",
      reference: "placeholder",
      kind: source.Synthetic,
    )
  value
}
