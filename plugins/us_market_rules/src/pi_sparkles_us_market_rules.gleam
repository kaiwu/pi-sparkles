import finance_core/decimal
import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_listing/effective
import finance_listing/listing
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import finance_us_rules/official
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pi
import pi/schema
import pi/tool
import pi_sparkles_us_market_rules/query

pub type Input {
  Input(
    venue: official.Venue,
    instrument_id: String,
    symbol: String,
    date: time.Date,
    currency: String,
    security_class: String,
    market_status: String,
    regime: String,
    nominal_price: String,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "us_trading_rules",
    "US effective trading rules",
    "Return the effective NYSE or Nasdaq displayed-quotation increment for one exact caller-identified normal NMS-stock listing during the SEC Rule 612 relief interval",
    "Inspect a source-reviewed US displayed-quote price increment without inventing round-lot, LULD, order, or execution rules",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case
        query.run(
          venue: input.venue,
          instrument_id: input.instrument_id,
          symbol: input.symbol,
          currency: input.currency,
          security_class: input.security_class,
          market_status: input.market_status,
          regime: input.regime,
          on: input.date,
          nominal_price: input.nominal_price,
        )
      {
        Error(query.InvalidProfile(official.InvalidInstrumentId)) ->
          tool.reject(
            "A safe namespaced instrumentId such as figi:BBG... is required",
          )
        Error(query.InvalidProfile(official.InvalidSymbol)) ->
          tool.reject("An exact uppercase US symbol is required")
        Error(query.InvalidProfile(official.OutsideReviewedInterval)) ->
          tool.reject(
            "US rule profile covers 2026-06-11 through 2027-10-31; no historical or future fallback was used",
          )
        Error(query.InvalidProfile(official.NonPositivePrice)) ->
          tool.reject("A positive exact nominalPrice is required")
        Error(query.InvalidProfile(official.InvalidCurrency)) ->
          tool.reject("This reviewed US rule slice supports USD only")
        Error(query.InvalidProfile(official.InvalidSecurityClass)) ->
          tool.reject("Only caller-declared nms_stock is supported")
        Error(query.InvalidProfile(official.InvalidMarketStatus)) ->
          tool.reject("Only caller-declared normal market status is supported")
        Error(query.InvalidProfile(official.InvalidRegime)) ->
          tool.reject("Only regular_displayed_quote is source-reviewed")
        Error(_) -> tool.reject("US effective-rule query was invalid")
        Ok(value) ->
          tool.text_result(render(value, input.date), result_json(value, input))
          |> promise.resolve
      }
    },
  )
  promise.resolve(Nil)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("venue", schema.string_enum(["nyse", "nasdaq"])),
    schema.Required(
      "instrumentId",
      schema.string()
        |> schema.with_string_length(3, 200)
        |> schema.described(
          "Exact namespaced listing identity such as figi:BBG...",
        ),
    ),
    schema.Required(
      "symbol",
      schema.string()
        |> schema.with_string_length(1, 32)
        |> schema.described(
          "Exact uppercase US symbol; retained but not resolved",
        ),
    ),
    schema.Required(
      "date",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Gregorian date from 2026-06-11 through 2027-10-31"),
    ),
    schema.Required("currency", schema.string_enum(["USD"])),
    schema.Required("securityClass", schema.string_enum(["nms_stock"])),
    schema.Required("marketStatus", schema.string_enum(["normal"])),
    schema.Required(
      "regime",
      schema.string_enum(["regular_displayed_quote"])
        |> schema.described(
          "Excludes customer-order acceptance, auctions, extended hours, LULD, halts, and other regimes",
        ),
    ),
    schema.Required(
      "nominalPrice",
      schema.string()
        |> schema.with_string_length(1, 100)
        |> schema.described(
          "Positive exact USD decimal used to select the increment",
        ),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use venue_text <- decode.field("venue", decode.string)
  use instrument_id <- decode.field("instrumentId", decode.string)
  use symbol <- decode.field("symbol", decode.string)
  use date_text <- decode.field("date", decode.string)
  use currency <- decode.field("currency", decode.string)
  use security_class <- decode.field("securityClass", decode.string)
  use market_status <- decode.field("marketStatus", decode.string)
  use regime <- decode.field("regime", decode.string)
  use nominal_price <- decode.field("nominalPrice", decode.string)
  let assert Ok(placeholder_date) = time.date(2026, 6, 11)
  let placeholder =
    Input(
      official.Nyse,
      instrument_id,
      symbol,
      placeholder_date,
      currency,
      security_class,
      market_status,
      regime,
      nominal_price,
    )
  case query.venue_from_name(venue_text), parse_date(date_text) {
    Ok(venue), Ok(date) ->
      decode.success(Input(
        venue,
        instrument_id,
        symbol,
        date,
        currency,
        security_class,
        market_status,
        regime,
        nominal_price,
      ))
    _, _ -> decode.failure(placeholder, "valid exact US venue and date")
  }
}

fn render(value: official.Profile, date: time.Date) -> String {
  let key = official.listing(value)
  "US track | "
  <> string.uppercase(official.venue_name(official.venue(value)))
  <> " "
  <> identifier.symbol_value(listing.symbol(key))
  <> " regular displayed NMS quote | "
  <> date_text(date)
  <> " | nominal $"
  <> decimal.to_string(official.nominal_price(value))
  <> " | increment $"
  <> decimal.to_string(official.minimum_price_increment(value))
}

fn result_json(value: official.Profile, input: Input) -> json.Json {
  let interval = official.effective(value)
  let key = official.listing(value)
  json.object(
    list.append(track_json.result_fields(context(value)), [
      #("date", json.string(date_text(input.date))),
      #("venue", json.string(official.venue_name(official.venue(value)))),
      #(
        "listing",
        json.object([
          #(
            "instrumentId",
            json.string(
              key |> listing.instrument_id |> identifier.instrument_id_value,
            ),
          ),
          #(
            "symbol",
            json.string(key |> listing.symbol |> identifier.symbol_value),
          ),
          #("mic", json.string(key |> listing.mic |> identifier.mic_value)),
          #("identityEvidence", json.string("caller_supplied_unverified")),
        ]),
      ),
      #("currency", json.string(input.currency)),
      #("securityClass", json.string(input.security_class)),
      #("securityClassEvidence", json.string("caller_supplied_unverified")),
      #("marketStatus", json.string(input.market_status)),
      #("marketStatusEvidence", json.string("caller_supplied_unverified")),
      #("regime", json.string(input.regime)),
      #(
        "effective",
        json.object([
          #("start", json.string(date_text(effective.start(interval)))),
          #("end", case effective.end(interval) {
            Some(date) -> json.string(date_text(date))
            None -> json.null()
          }),
        ]),
      ),
      #(
        "rule",
        json.object([
          #(
            "nominalPrice",
            json.string(decimal.to_string(official.nominal_price(value))),
          ),
          #(
            "priceBand",
            json.string(
              official.price_band_name(official.selected_price_band(value)),
            ),
          ),
          #(
            "minimumPriceIncrement",
            json.string(
              decimal.to_string(official.minimum_price_increment(value)),
            ),
          ),
          #("appliesTo", json.string("regular_displayed_exchange_quotation")),
          #("roundLotShares", json.null()),
          #(
            "roundLotStatus",
            json.string("not_assessed_dynamic_exchange_publication"),
          ),
          #("staticDailyPriceLimitRatio", json.null()),
          #(
            "staticDailyPriceLimitStatus",
            json.string("not_claimed_luld_is_separate"),
          ),
          #("settlement", json.null()),
        ]),
      ),
      #("sources", json.array(official.sources(value), source_json)),
      #("clauses", json.array(official.clauses(value), json.string)),
      #(
        "audit",
        json.object([
          #("profile", json.string("us_regular_displayed_nms_quote_relief_v1")),
          #("sourceReviewed", json.bool(True)),
          #("callerMustVerifyListingClassAndStatus", json.bool(True)),
          #(
            "amendedHalfCentRegime",
            json.string("not_yet_required_under_sec_34_105656"),
          ),
          #("nextKnownComplianceBoundary", json.string("2027-11-01")),
          #("redistribution", json.string("unknown")),
        ]),
      ),
      #("limitations", json.array(official.limitations(value), json.string)),
    ]),
  )
}

fn context(value: official.Profile) -> track_context.Context {
  let key = official.listing(value)
  let assert Ok(zone) = time.timezone("America/New_York")
  let assert Ok(result) =
    track_context.new(
      track: finance_track.Us,
      market_scope: "us_effective_rules",
      venue_mic: Some(listing.mic(key)),
      board: Some(official.venue_name(official.venue(value))),
      timezone: Some(zone),
      source_language: "en-US",
      providers: [
        source.provider(official.exchange_source(value)),
        source.provider(official.sec_relief_source(value)),
      ],
      entitlement: "read_only_local_analysis",
      limitations: official.limitations(value),
    )
  result
}

fn source_json(value: source.SourceRef) -> json.Json {
  json.object([
    #("provider", json.string(source.provider(value))),
    #("reference", json.string(source.reference(value))),
    #("kind", json.string(source_kind_name(source.kind(value)))),
  ])
}

fn source_kind_name(value: source.SourceKind) -> String {
  case value {
    source.Exchange -> "exchange"
    source.Regulator -> "regulator"
    source.Official -> "official"
    source.LicensedVendor -> "licensed_vendor"
    source.UserSupplied -> "user_supplied"
    source.Synthetic -> "synthetic"
    source.Other(kind) -> kind
  }
}

fn parse_date(value: String) -> Result(time.Date, Nil) {
  case string.split(value, "-") {
    [year, month, day] -> {
      use year <- result.try(int.parse(year) |> result.map_error(fn(_) { Nil }))
      use month <- result.try(
        int.parse(month) |> result.map_error(fn(_) { Nil }),
      )
      use day <- result.try(int.parse(day) |> result.map_error(fn(_) { Nil }))
      time.date(year, month, day) |> result.map_error(fn(_) { Nil })
    }
    _ -> Error(Nil)
  }
}

fn date_text(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
