import finance_calendar/date
import finance_core/adjustment
import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/market
import finance_core/observation
import finance_core/source
import finance_core/time
import finance_ohlcv
import finance_provenance/evidence
import finance_provenance/hash
import finance_provenance/identity
import finance_provenance/redact
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_stock_history/decode

const maximum_safe_integer = 9_007_199_254_740_991

const maximum_input_bars = 2000

const maximum_output_rows = 200

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
  "Invalid exact stock-history field " <> field <> ": " <> reason
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
  use range_start <- result.try(parse_date(
    "range.startDate",
    input.range.start_date,
  ))
  use range_end <- result.try(parse_date("range.endDate", input.range.end_date))
  use _ <- result.try(validate_range(range_start, range_end))
  use _ <- result.try(count_bound("bars", input.bars, maximum_input_bars))
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
  use retrieved_at <- result.try(instant(
    "batch.retrievedAtUnixMilliseconds",
    input.batch.retrieved_at_unix_ms,
  ))
  use batch_currency <- result.try(parse_currency(input.batch.currency))
  use volume_unit <- result.try(volume_unit(input.batch.volume_unit))
  use adjustment <- result.try(adjustment(input.batch.adjustment, provider))
  use session <- result.try(session(input.batch.session))
  use pagination <- result.try(pagination(input.batch.pagination))
  use calendar <- result.try(calendar(
    input.batch.calendar,
    range_start,
    range_end,
  ))
  use bars <- result.try(parse_bars(input.bars, range_start, range_end, 0, []))
  use _ <- result.try(validate_gap_bar_separation(calendar, bars))
  use page <- result.try(page(input.page))
  let timezone = market_timezone(track)
  let receipt_text = identity.sha256_value(receipt)
  use batch <- result.try(
    finance_ohlcv.batch_with_metadata(
      bars,
      retrieved_at: retrieved_at,
      timezone: timezone,
      currency: batch_currency,
      volume_unit: volume_unit,
      adjustment: adjustment,
      session: session,
      source: safe_source.value,
      expected_provider: provider,
      pagination: pagination,
      calendar: calendar,
      evidence_id: Some(receipt_text),
      entitlement: entitlement,
    )
    |> result.map_error(fn(error) {
      InvalidField("batch", string.inspect(error))
    }),
  )
  let observations = finance_ohlcv.observations(batch)
  use _ <- result.try(validate_session_date_order(observations))
  let total = list.length(observations)
  let selected = observations |> list.drop(page.offset) |> list.take(page.limit)
  let returned = list.length(selected)
  let next_offset = case page.offset + returned < total {
    True -> Some(page.offset + returned)
    False -> None
  }
  let limitations = limitations()
  use context <- result.try(
    track_context.new(
      track: track,
      market_scope: finance_track.name(track) <> "_stock_history",
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
      <> " daily bars | "
      <> symbol
      <> " @ "
      <> identifier.mic_value(mic)
      <> " | "
      <> int.to_string(total)
      <> " observations",
    json.object(
      list.append(track_json.result_fields(context), [
        #("schemaVersion", json.int(1)),
        #("operation", json.string("stock_bars")),
        #(
          "listing",
          json.object([
            #("listingId", json.string(listing_id)),
            #("mic", json.string(identifier.mic_value(mic))),
            #("symbol", json.string(symbol)),
            #("identityStatus", json.string("caller_supplied_unverified")),
          ]),
        ),
        #(
          "range",
          json.object([
            #("startDate", json.string(date_text(range_start))),
            #("endDate", json.string(date_text(range_end))),
            #("bounds", json.string("inclusive")),
          ]),
        ),
        #("batch", batch_json(batch, list.length(input.bars), total)),
        #(
          "page",
          json.object([
            #("offset", json.int(page.offset)),
            #("limit", json.int(page.limit)),
            #("returned", json.int(returned)),
            #("total", json.int(total)),
            #("nextOffset", json.nullable(next_offset, json.int)),
          ]),
        ),
        #("bars", json.array(selected, observation_json)),
        #("source", source_json(safe_source, kind, feed, receipt_text)),
        #("licence", licence_json(licence)),
        #(
          "unknownFacts",
          json.array(
            [
              "freshness",
              "listing_identity_authority",
              "source_receipt_origin_authentication",
              "calendar_and_gap_authority",
              "corporate_action_completeness",
              "provider_adjustment_formula_unless_explicitly_supplied",
              "intraday_completeness",
            ],
            json.string,
          ),
        ),
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
      InvalidField("batch.currency", "expected a three-letter currency code")
    }),
  )
  case currency.code(parsed) == value {
    True -> Ok(parsed)
    False ->
      Error(InvalidField(
        "batch.currency",
        "currency must already use its exact uppercase representation",
      ))
  }
}

fn volume_unit(value: String) -> Result(finance_ohlcv.VolumeUnit, DomainError) {
  case value {
    "shares" -> Ok(finance_ohlcv.Shares)
    "unknown" -> Ok(finance_ohlcv.UnknownVolumeUnit)
    _ -> Error(InvalidField("batch.volumeUnit", "expected shares or unknown"))
  }
}

fn adjustment(
  value: decode.AdjustmentInput,
  source_provider: String,
) -> Result(adjustment.Adjustment, DomainError) {
  case value.kind, value.provider, value.basis {
    "raw", None, None -> Ok(adjustment.Raw)
    "split_adjusted", None, None -> Ok(adjustment.SplitAdjusted)
    "dividend_adjusted", None, None -> Ok(adjustment.DividendAdjusted)
    "total_return_adjusted", None, None -> Ok(adjustment.TotalReturnAdjusted)
    "provider_adjusted", Some(provider), Some(basis) -> {
      use exact_provider <- result.try(bounded_text(
        "batch.adjustment.provider",
        provider,
        200,
      ))
      use exact_basis <- result.try(bounded_text(
        "batch.adjustment.basis",
        basis,
        500,
      ))
      use _ <- result.try(case exact_provider == source_provider {
        True -> Ok(Nil)
        False ->
          Error(InvalidField(
            "batch.adjustment.provider",
            "must exactly match source.provider",
          ))
      })
      adjustment.provider_adjusted(provider: exact_provider, basis: exact_basis)
      |> result.map_error(fn(error) {
        InvalidField("batch.adjustment", string.inspect(error))
      })
    }
    "provider_adjusted", _, _ ->
      Error(InvalidField(
        "batch.adjustment",
        "provider_adjusted requires provider and basis",
      ))
    _, Some(_), _ | _, _, Some(_) ->
      Error(InvalidField(
        "batch.adjustment",
        "provider and basis are only allowed together for provider_adjusted",
      ))
    _, None, None ->
      Error(InvalidField("batch.adjustment.kind", "unsupported adjustment kind"))
  }
}

fn session(value: decode.SessionInput) -> Result(market.Session, DomainError) {
  case value.state, value.other_label {
    "pre_market", None -> Ok(market.PreMarket)
    "regular", None -> Ok(market.Regular)
    "after_hours", None -> Ok(market.AfterHours)
    "auction", None -> Ok(market.Auction)
    "closed", None -> Ok(market.Closed)
    "other", Some(label) -> {
      use exact <- result.try(bounded_text(
        "batch.session.otherLabel",
        label,
        200,
      ))
      market.other_session(exact)
      |> result.map_error(fn(_) {
        InvalidField("batch.session.otherLabel", "invalid exact session label")
      })
    }
    "other", None ->
      Error(InvalidField(
        "batch.session.otherLabel",
        "other session requires otherLabel",
      ))
    _, Some(_) ->
      Error(InvalidField(
        "batch.session.otherLabel",
        "otherLabel is only allowed when session state is other",
      ))
    _, None ->
      Error(InvalidField("batch.session.state", "unsupported session state"))
  }
}

fn pagination(
  value: decode.PaginationInput,
) -> Result(finance_ohlcv.Pagination, DomainError) {
  case value.state, value.maximum {
    "complete", None -> Ok(finance_ohlcv.AllPages)
    "truncated_by_page_budget", Some(maximum) -> {
      use _ <- result.try(integer_range(
        "batch.pagination.maximum",
        maximum,
        1,
        10,
      ))
      Ok(finance_ohlcv.TruncatedByPageBudget(maximum))
    }
    "truncated_by_bar_budget", Some(maximum) -> {
      use _ <- result.try(integer_range(
        "batch.pagination.maximum",
        maximum,
        1,
        maximum_input_bars,
      ))
      Ok(finance_ohlcv.TruncatedByBarBudget(maximum))
    }
    "complete", Some(_) ->
      Error(InvalidField(
        "batch.pagination.maximum",
        "complete pagination forbids maximum",
      ))
    "truncated_by_page_budget", None | "truncated_by_bar_budget", None ->
      Error(InvalidField(
        "batch.pagination.maximum",
        "truncated pagination requires its positive maximum",
      ))
    _, _ ->
      Error(InvalidField(
        "batch.pagination.state",
        "unsupported pagination state",
      ))
  }
}

fn calendar(
  value: decode.CalendarInput,
  range_start: time.Date,
  range_end: time.Date,
) -> Result(finance_ohlcv.CalendarAssessment, DomainError) {
  use _ <- result.try(count_bound(
    "batch.calendar.gaps",
    value.gaps,
    maximum_input_bars,
  ))
  case value.state, value.reason, value.gaps {
    "not_assessed", Some(reason), [] -> {
      use exact <- result.try(identifier_text("batch.calendar.reason", reason))
      Ok(finance_ohlcv.CalendarNotAssessed(exact))
    }
    "not_assessed", _, _ ->
      Error(InvalidField(
        "batch.calendar",
        "not_assessed requires a lower-snake-case reason and no gaps",
      ))
    "assessed", None, gaps -> {
      use parsed <- result.try(parse_gaps(gaps, range_start, range_end, 0, []))
      Ok(finance_ohlcv.CalendarAssessed(parsed))
    }
    "assessed", Some(_), _ ->
      Error(InvalidField(
        "batch.calendar.reason",
        "assessed calendar forbids reason",
      ))
    _, _, _ ->
      Error(InvalidField("batch.calendar.state", "unsupported calendar state"))
  }
}

fn parse_gaps(
  remaining: List(decode.GapInput),
  range_start: time.Date,
  range_end: time.Date,
  index: Int,
  reversed: List(finance_ohlcv.Gap),
) -> Result(List(finance_ohlcv.Gap), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      let field = "batch.calendar.gaps[" <> int.to_string(index) <> "]"
      use session_date <- result.try(parse_date(
        field <> ".sessionDate",
        value.session_date,
      ))
      use _ <- result.try(date_in_range(
        field <> ".sessionDate",
        session_date,
        range_start,
        range_end,
      ))
      use state <- result.try(gap_state(field <> ".state", value.state))
      use reference <- result.try(safe_optional_reference(
        field <> ".evidenceReference",
        value.evidence_reference,
      ))
      parse_gaps(rest, range_start, range_end, index + 1, [
        finance_ohlcv.Gap(session_date, state, reference),
        ..reversed
      ])
    }
  }
}

fn gap_state(
  field: String,
  value: String,
) -> Result(finance_ohlcv.GapState, DomainError) {
  case value {
    "market_closure" -> Ok(finance_ohlcv.MarketClosure)
    "suspension" -> Ok(finance_ohlcv.Suspension)
    "provider_omission" -> Ok(finance_ohlcv.ProviderOmission)
    "unavailable_history" -> Ok(finance_ohlcv.UnavailableHistory)
    _ -> Error(InvalidField(field, "unsupported exact gap state"))
  }
}

fn parse_bars(
  remaining: List(decode.BarInput),
  range_start: time.Date,
  range_end: time.Date,
  index: Int,
  reversed: List(finance_ohlcv.Bar),
) -> Result(List(finance_ohlcv.Bar), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use parsed <- result.try(parse_bar(value, range_start, range_end, index))
      parse_bars(rest, range_start, range_end, index + 1, [parsed, ..reversed])
    }
  }
}

fn parse_bar(
  value: decode.BarInput,
  range_start: time.Date,
  range_end: time.Date,
  index: Int,
) -> Result(finance_ohlcv.Bar, DomainError) {
  let field = "bars[" <> int.to_string(index) <> "]"
  use session_date <- result.try(parse_date(
    field <> ".sessionDate",
    value.session_date,
  ))
  use _ <- result.try(date_in_range(
    field <> ".sessionDate",
    session_date,
    range_start,
    range_end,
  ))
  use source_timestamp <- result.try(bounded_text(
    field <> ".sourceTimestamp",
    value.source_timestamp,
    100,
  ))
  use open <- result.try(exact(field <> ".rawOpen", value.raw_open))
  use high <- result.try(exact(field <> ".rawHigh", value.raw_high))
  use low <- result.try(exact(field <> ".rawLow", value.raw_low))
  use close <- result.try(exact(field <> ".rawClose", value.raw_close))
  use volume <- result.try(exact(field <> ".rawVolume", value.raw_volume))
  use trade_count <- result.try(optional_count(
    field <> ".rawTradeCount",
    value.raw_trade_count,
  ))
  use vwap <- result.try(optional_exact(field <> ".rawVwap", value.raw_vwap))
  case value.time_basis, value.at_unix_ms {
    "source_instant", Some(milliseconds) -> {
      use at <- result.try(instant(field <> ".atUnixMilliseconds", milliseconds))
      finance_ohlcv.bar(
        source_timestamp,
        at,
        session_date,
        open,
        high,
        low,
        close,
        volume,
        trade_count,
        vwap,
      )
      |> result.map_error(fn(error) {
        InvalidField(field, string.inspect(error))
      })
    }
    "session_date_anchor", None -> {
      use _ <- result.try(case source_timestamp == value.session_date {
        True -> Ok(Nil)
        False ->
          Error(InvalidField(
            field <> ".sourceTimestamp",
            "session_date_anchor requires sourceTimestamp to equal sessionDate",
          ))
      })
      finance_ohlcv.date_bar(
        source_timestamp,
        session_date,
        open,
        high,
        low,
        close,
        volume,
        trade_count,
        vwap,
      )
      |> result.map_error(fn(error) {
        InvalidField(field, string.inspect(error))
      })
    }
    "source_instant", None ->
      Error(InvalidField(
        field <> ".atUnixMilliseconds",
        "source_instant requires atUnixMilliseconds",
      ))
    "session_date_anchor", Some(_) ->
      Error(InvalidField(
        field <> ".atUnixMilliseconds",
        "session_date_anchor forbids atUnixMilliseconds",
      ))
    _, _ -> Error(InvalidField(field <> ".timeBasis", "unsupported time basis"))
  }
}

fn exact(
  field: String,
  value: String,
) -> Result(finance_ohlcv.ExactValue, DomainError) {
  use raw <- result.try(bounded_text(field, value, 500))
  finance_ohlcv.exact(raw)
  |> result.map_error(fn(_) {
    InvalidField(field, "expected an exact decimal lexeme")
  })
}

fn optional_exact(
  field: String,
  value: Option(String),
) -> Result(Option(finance_ohlcv.ExactValue), DomainError) {
  case value {
    None -> Ok(None)
    Some(value) -> {
      use parsed <- result.try(exact(field, value))
      Ok(Some(parsed))
    }
  }
}

fn optional_count(
  field: String,
  value: Option(String),
) -> Result(Option(finance_ohlcv.ExactCount), DomainError) {
  case value {
    None -> Ok(None)
    Some(value) -> {
      use raw <- result.try(bounded_text(field, value, 500))
      use parsed <- result.try(
        finance_ohlcv.exact_count(raw)
        |> result.map_error(fn(_) {
          InvalidField(field, "expected an exact integer lexeme")
        }),
      )
      Ok(Some(parsed))
    }
  }
}

fn validate_gap_bar_separation(
  calendar: finance_ohlcv.CalendarAssessment,
  bars: List(finance_ohlcv.Bar),
) -> Result(Nil, DomainError) {
  case calendar {
    finance_ohlcv.CalendarNotAssessed(_) -> Ok(Nil)
    finance_ohlcv.CalendarAssessed(gaps) ->
      case
        list.any(gaps, fn(gap) {
          let finance_ohlcv.Gap(gap_date, _, _) = gap
          list.any(bars, fn(bar) { finance_ohlcv.session_date(bar) == gap_date })
        })
      {
        True ->
          Error(InvalidField(
            "batch.calendar.gaps",
            "a session date cannot be both a returned daily bar and a gap",
          ))
        False -> Ok(Nil)
      }
  }
}

fn validate_session_date_order(
  values: List(observation.Observation(finance_ohlcv.Bar)),
) -> Result(Nil, DomainError) {
  case values {
    [] | [_] -> Ok(Nil)
    [previous, current, ..rest] ->
      case
        date.compare(
          finance_ohlcv.session_date(previous.value),
          finance_ohlcv.session_date(current.value),
        )
      {
        Lt -> validate_session_date_order([current, ..rest])
        Eq | Gt ->
          Error(InvalidField(
            "bars",
            "canonical daily observations require strictly increasing unique sessionDate values",
          ))
      }
  }
}

fn page(value: decode.PageInput) -> Result(decode.PageInput, DomainError) {
  use _ <- result.try(integer_range("page.offset", value.offset, 0, 2000))
  use _ <- result.try(integer_range(
    "page.limit",
    value.limit,
    1,
    maximum_output_rows,
  ))
  Ok(value)
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

fn safe_optional_reference(
  field: String,
  value: Option(String),
) -> Result(Option(String), DomainError) {
  case value {
    None -> Ok(None)
    Some(raw) -> {
      use _ <- result.try(bounded_text(field, raw, 8000))
      let projected = redact.url(raw, [])
      case string.length(projected) <= 500 {
        True -> Ok(Some(projected))
        False -> {
          use digest <- result.try(
            hash.text(raw)
            |> result.map_error(fn(_) {
              InvalidField(field, "safe evidence-reference hashing failed")
            }),
          )
          Ok(Some("redacted-reference:sha256:" <> identity.sha256_value(digest)))
        }
      }
    }
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

fn batch_json(batch: finance_ohlcv.Batch, input_rows: Int, total: Int) -> Json {
  json.object([
    #("interval", json.string("1_day")),
    #(
      "timezone",
      json.string(time.timezone_name(finance_ohlcv.timezone(batch))),
    ),
    #("currency", json.string(currency.code(finance_ohlcv.currency(batch)))),
    #(
      "volumeUnit",
      json.string(volume_unit_name(finance_ohlcv.volume_unit(batch))),
    ),
    #("adjustment", adjustment_json(finance_ohlcv.adjustment(batch))),
    #("session", session_json(finance_ohlcv.session(batch))),
    #("pagination", pagination_json(finance_ohlcv.pagination(batch))),
    #("calendar", calendar_json(finance_ohlcv.calendar_assessment(batch))),
    #(
      "availability",
      json.string(availability_name(finance_ohlcv.availability(batch))),
    ),
    #("inputRowCount", json.int(input_rows)),
    #("observationCount", json.int(total)),
    #(
      "duplicatesCollapsed",
      json.int(finance_ohlcv.duplicates_collapsed(batch)),
    ),
  ])
}

fn observation_json(
  observed: observation.Observation(finance_ohlcv.Bar),
) -> Json {
  let bar = observed.value
  json.object([
    #("sessionDate", json.string(date_text(finance_ohlcv.session_date(bar)))),
    #("sourceTimestamp", json.string(finance_ohlcv.source_timestamp(bar))),
    #("timeBasis", json.string(time_basis_name(finance_ohlcv.time_basis(bar)))),
    #(
      "atUnixMilliseconds",
      json.int(time.unix_milliseconds(finance_ohlcv.at(bar))),
    ),
    #(
      "atStatus",
      json.string(case finance_ohlcv.time_basis(bar) {
        finance_ohlcv.SourceInstant -> "provider_or_adapter_declared"
        finance_ohlcv.SessionDateAnchor -> "ordering_anchor_not_provider_time"
      }),
    ),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(observed.retrieved_at)),
    ),
    #(
      "raw",
      json.object([
        #("open", json.string(finance_ohlcv.raw(finance_ohlcv.open(bar)))),
        #("high", json.string(finance_ohlcv.raw(finance_ohlcv.high(bar)))),
        #("low", json.string(finance_ohlcv.raw(finance_ohlcv.low(bar)))),
        #("close", json.string(finance_ohlcv.raw(finance_ohlcv.close(bar)))),
        #("volume", json.string(finance_ohlcv.raw(finance_ohlcv.volume(bar)))),
        #(
          "tradeCount",
          json.nullable(finance_ohlcv.trade_count(bar), fn(value) {
            json.string(finance_ohlcv.count_raw(value))
          }),
        ),
        #(
          "vwap",
          json.nullable(finance_ohlcv.vwap(bar), fn(value) {
            json.string(finance_ohlcv.raw(value))
          }),
        ),
      ]),
    ),
    #(
      "normalized",
      json.object([
        #("open", decimal_json(finance_ohlcv.open(bar))),
        #("high", decimal_json(finance_ohlcv.high(bar))),
        #("low", decimal_json(finance_ohlcv.low(bar))),
        #("close", decimal_json(finance_ohlcv.close(bar))),
        #("volume", decimal_json(finance_ohlcv.volume(bar))),
        #(
          "tradeCount",
          json.nullable(finance_ohlcv.trade_count(bar), fn(value) {
            json.int(finance_ohlcv.count_normalized(value))
          }),
        ),
        #("vwap", json.nullable(finance_ohlcv.vwap(bar), decimal_json)),
      ]),
    ),
    #("evidenceId", json.nullable(observed.evidence_id, json.string)),
    #("freshness", json.object([#("state", json.string("unknown"))])),
    #("entitlement", entitlement_json(observed.entitlement)),
    #("quality", json.string("reported")),
  ])
}

fn adjustment_json(value: adjustment.Adjustment) -> Json {
  let #(kind, provider, basis) = case value {
    adjustment.Raw -> #("raw", None, None)
    adjustment.SplitAdjusted -> #("split_adjusted", None, None)
    adjustment.DividendAdjusted -> #("dividend_adjusted", None, None)
    adjustment.TotalReturnAdjusted -> #("total_return_adjusted", None, None)
    adjustment.ProviderAdjusted(value) -> #(
      "provider_adjusted",
      Some(adjustment.provider(value)),
      Some(adjustment.basis(value)),
    )
  }
  json.object([
    #("kind", json.string(kind)),
    #("provider", json.nullable(provider, json.string)),
    #("basis", json.nullable(basis, json.string)),
    #("status", json.string("caller_or_provider_adapter_declared_unverified")),
  ])
}

fn session_json(value: market.Session) -> Json {
  let #(state, other_label) = case value {
    market.PreMarket -> #("pre_market", None)
    market.Regular -> #("regular", None)
    market.AfterHours -> #("after_hours", None)
    market.Auction -> #("auction", None)
    market.Closed -> #("closed", None)
    market.OtherSession(label) -> #("other", Some(market.label(label)))
  }
  json.object([
    #("state", json.string(state)),
    #("otherLabel", json.nullable(other_label, json.string)),
  ])
}

fn pagination_json(value: finance_ohlcv.Pagination) -> Json {
  let #(state, maximum) = case value {
    finance_ohlcv.AllPages -> #("complete", None)
    finance_ohlcv.TruncatedByPageBudget(value) -> #(
      "truncated_by_page_budget",
      Some(value),
    )
    finance_ohlcv.TruncatedByBarBudget(value) -> #(
      "truncated_by_bar_budget",
      Some(value),
    )
  }
  json.object([
    #("state", json.string(state)),
    #("maximum", json.nullable(maximum, json.int)),
    #("continuationTokenAvailable", json.bool(False)),
  ])
}

fn calendar_json(value: finance_ohlcv.CalendarAssessment) -> Json {
  case value {
    finance_ohlcv.CalendarNotAssessed(reason) ->
      json.object([
        #("state", json.string("not_assessed")),
        #("reason", json.string(reason)),
        #("gaps", json.array([], fn(value: Json) { value })),
        #(
          "status",
          json.string("caller_or_provider_adapter_declared_unverified"),
        ),
      ])
    finance_ohlcv.CalendarAssessed(gaps) ->
      json.object([
        #("state", json.string("assessed")),
        #("reason", json.null()),
        #("gaps", json.array(gaps, gap_json)),
        #(
          "status",
          json.string("caller_or_provider_adapter_declared_unverified"),
        ),
      ])
  }
}

fn gap_json(value: finance_ohlcv.Gap) -> Json {
  let finance_ohlcv.Gap(session_date, state, evidence_reference) = value
  json.object([
    #("sessionDate", json.string(date_text(session_date))),
    #("state", json.string(gap_name(state))),
    #("evidenceReference", json.nullable(evidence_reference, json.string)),
  ])
}

fn gap_name(value: finance_ohlcv.GapState) -> String {
  case value {
    finance_ohlcv.MarketClosure -> "market_closure"
    finance_ohlcv.Suspension -> "suspension"
    finance_ohlcv.ProviderOmission -> "provider_omission"
    finance_ohlcv.UnavailableHistory -> "unavailable_history"
  }
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

fn availability_name(value: finance_ohlcv.Availability) -> String {
  case value {
    finance_ohlcv.BarsReturned -> "bars_returned"
    finance_ohlcv.NoBarsReturned -> "no_bars_returned_unclassified"
  }
}

fn time_basis_name(value: finance_ohlcv.TimeBasis) -> String {
  case value {
    finance_ohlcv.SourceInstant -> "source_instant"
    finance_ohlcv.SessionDateAnchor -> "session_date_anchor"
  }
}

fn volume_unit_name(value: finance_ohlcv.VolumeUnit) -> String {
  case value {
    finance_ohlcv.Shares -> "shares"
    finance_ohlcv.UnknownVolumeUnit -> "unknown"
  }
}

fn decimal_json(value: finance_ohlcv.ExactValue) -> Json {
  value |> finance_ohlcv.normalized |> decimal.to_string |> json.string
}

fn context_entitlement(value: observation.Entitlement) -> String {
  case value {
    observation.RealTime -> "declared_real_time"
    observation.Delayed(_) -> "declared_delayed"
    observation.EndOfDay -> "declared_end_of_day"
    observation.UnknownEntitlement -> "unknown"
  }
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

fn limitations() -> List(String) {
  [
    "caller_supplied_listing_identity_not_verified",
    "source_receipt_hash_not_origin_authentication",
    "licence_entitlement_adjustment_and_calendar_are_caller_or_adapter_declarations",
    "calendar_gaps_are_not_exchange_proof",
    "session_date_anchor_is_not_provider_time",
    "no_gap_repair_interpolation_or_corporate_action_inference",
    "no_network_provider_selection_fallback_returns_signals_or_trading_decision",
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

fn parse_date(field: String, value: String) -> Result(time.Date, DomainError) {
  case string.split(value, "-") {
    [year, month, day] ->
      case int.parse(year), int.parse(month), int.parse(day) {
        Ok(year), Ok(month), Ok(day) ->
          case time.date(year, month, day) {
            Ok(parsed) ->
              case date_text(parsed) == value {
                True -> Ok(parsed)
                False -> Error(InvalidField(field, "non-canonical date"))
              }
            Error(_) -> Error(InvalidField(field, "invalid Gregorian date"))
          }
        _, _, _ -> Error(InvalidField(field, "invalid Gregorian date"))
      }
    _ -> Error(InvalidField(field, "invalid Gregorian date"))
  }
}

fn date_text(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> pad_two(month) <> "-" <> pad_two(day)
}

fn pad_two(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn validate_range(
  start: time.Date,
  end: time.Date,
) -> Result(Nil, DomainError) {
  case date.compare(start, end) {
    Lt | Eq -> Ok(Nil)
    Gt -> Error(InvalidField("range", "startDate must not follow endDate"))
  }
}

fn date_in_range(
  field: String,
  value: time.Date,
  start: time.Date,
  end: time.Date,
) -> Result(Nil, DomainError) {
  case date.compare(value, start), date.compare(value, end) {
    Lt, _ | _, Gt ->
      Error(InvalidField(field, "date is outside the declared inclusive range"))
    _, _ -> Ok(Nil)
  }
}

fn instant(field: String, value: Int) -> Result(time.Instant, DomainError) {
  use _ <- result.try(integer_range(field, value, 0, maximum_safe_integer))
  time.instant(value)
  |> result.map_error(fn(_) { InvalidField(field, "instant is out of range") })
}

fn identifier_text(
  field: String,
  value: String,
) -> Result(String, DomainError) {
  use exact <- result.try(bounded_text(field, value, 200))
  case
    exact
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  {
    True -> Ok(exact)
    False ->
      Error(InvalidField(field, "expected a lowercase snake-case identifier"))
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
