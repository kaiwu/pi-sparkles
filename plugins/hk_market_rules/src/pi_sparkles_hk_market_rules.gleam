import finance_core/decimal
import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_hk_rules/official
import finance_listing/effective
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
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
import pi_sparkles_hk_market_rules/query

pub type Input {
  Input(
    date: time.Date,
    currency: String,
    product_class: String,
    nominal_price: String,
    board_lot: Int,
    board_lot_source: String,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "hk_trading_rules",
    "HK effective trading rules",
    "Return the dated HKEX minimum spread for a narrowly scoped applicable HKD equity while preserving the caller-supplied issuer-specific board lot and its evidence reference",
    "Inspect the current HKEX tick and board-lot-market context without inventing a universal Hong Kong lot size",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case
        query.run(
          currency: input.currency,
          product_class: input.product_class,
          on: input.date,
          nominal_price: input.nominal_price,
          board_lot: input.board_lot,
          board_lot_source: input.board_lot_source,
        )
      {
        Error(query.InvalidCurrency) ->
          tool.reject("This reviewed HK rules slice supports HKD counters only")
        Error(query.InvalidProductClass) ->
          tool.reject("Only caller-proven applicable_equity is supported")
        Error(query.InvalidProfile(official.OutsideReviewedInterval)) ->
          tool.reject(
            "HK rules profile starts with spread Phase 2 on 2026-08-03; no historical fallback was used",
          )
        Error(query.InvalidProfile(official.UnsupportedPriceBand)) ->
          tool.reject(
            "Reviewed HK minimum-spread coverage is 0.50 inclusive to 50.00 exclusive",
          )
        Error(query.InvalidProfile(official.InvalidBoardLot)) ->
          tool.reject("A positive issuer-specific board lot is required")
        Error(query.InvalidProfile(official.InvalidBoardLotSource)) ->
          tool.reject(
            "An auditable issuer-specific board-lot evidence reference is required",
          )
        Error(_) -> tool.reject("HK effective-rule query was invalid")
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
    schema.Required(
      "date",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Gregorian date YYYY-MM-DD on or after 2026-08-03"),
    ),
    schema.Required("currency", schema.string_enum(["HKD"])),
    schema.Required(
      "productClass",
      schema.string_enum(["applicable_equity"])
        |> schema.described(
          "Caller-proven HKEX applicable equity; not inferred from code",
        ),
    ),
    schema.Required(
      "nominalPrice",
      schema.string()
        |> schema.with_string_length(1, 100)
        |> schema.described(
          "Exact decimal source string from 0.50 inclusive to 50.00 exclusive",
        ),
    ),
    schema.Required(
      "boardLot",
      schema.integer()
        |> schema.with_number_range(1.0, 1_000_000.0)
        |> schema.described(
          "Issuer-specific board lot from independent evidence",
        ),
    ),
    schema.Required(
      "boardLotSource",
      schema.string()
        |> schema.with_string_length(1, 500)
        |> schema.described(
          "Auditable HKEX/issuer evidence reference; retained but not fetched or verified",
        ),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use date_text <- decode.field("date", decode.string)
  use currency <- decode.field("currency", decode.string)
  use product_class <- decode.field("productClass", decode.string)
  use nominal_price <- decode.field("nominalPrice", decode.string)
  use board_lot <- decode.field("boardLot", decode.int)
  use board_lot_source <- decode.field("boardLotSource", decode.string)
  let assert Ok(placeholder_date) = time.date(2026, 8, 3)
  let placeholder =
    Input(
      placeholder_date,
      currency,
      product_class,
      nominal_price,
      board_lot,
      board_lot_source,
    )
  case parse_date(date_text) {
    Ok(date) ->
      decode.success(Input(
        date,
        currency,
        product_class,
        nominal_price,
        board_lot,
        board_lot_source,
      ))
    Error(_) -> decode.failure(placeholder, "valid Gregorian date")
  }
}

fn render(value: official.Profile, date: time.Date) -> String {
  "HK track | HKEX applicable HKD equity rules | "
  <> date_text(date)
  <> " | nominal "
  <> decimal.to_string(official.nominal_price(value))
  <> " | tick "
  <> decimal.to_string(official.tick_size(value))
  <> " | issuer board lot "
  <> int.to_string(official.board_lot(value))
}

fn result_json(value: official.Profile, input: Input) -> json.Json {
  let interval = official.effective(value)
  json.object(
    list.append(track_json.result_fields(context(value)), [
      #("date", json.string(date_text(input.date))),
      #("venue", json.string("hkex")),
      #("currency", json.string(input.currency)),
      #("currencyEvidence", json.string("caller_declared_hkd")),
      #("productClass", json.string(input.product_class)),
      #(
        "productClassEvidence",
        json.string("caller_declared_not_provider_verified"),
      ),
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
            "tickSize",
            json.string(decimal.to_string(official.tick_size(value))),
          ),
          #("boardLot", json.int(official.board_lot(value))),
          #("boardLotEvidence", json.string(official.board_lot_source(value))),
          #("boardLotEvidenceStatus", json.string("caller_supplied_unverified")),
          #("oddLotMarket", json.string("separate_non_auto_matching_market")),
        ]),
      ),
      #(
        "sources",
        json.array(
          [
            official.spread_source(value),
            official.board_lot_rule_source(value),
          ],
          source_json,
        ),
      ),
      #("clauses", json.array(official.clauses(value), json.string)),
      #(
        "audit",
        json.object([
          #("profile", json.string("hk_applicable_hkd_equity_phase2_v1")),
          #("sourceReviewed", json.bool(True)),
          #("callerMustAuditBoardLotEvidence", json.bool(True)),
          #("redistribution", json.string("unknown")),
        ]),
      ),
      #("limitations", json.array(official.limitations(value), json.string)),
    ]),
  )
}

fn context(value: official.Profile) -> track_context.Context {
  let assert Ok(mic) = identifier.mic("XHKG")
  let assert Ok(zone) = time.timezone("Asia/Hong_Kong")
  let assert Ok(result) =
    track_context.new(
      track: finance_track.Hk,
      market_scope: "hk_effective_rules",
      venue_mic: Some(mic),
      board: Some("issuer_specific"),
      timezone: Some(zone),
      source_language: "en-HK",
      providers: ["Hong Kong Exchanges and Clearing"],
      entitlement: "read_only_local_analysis",
      limitations: official.limitations(value),
    )
  result
}

fn source_json(value: source.SourceRef) -> json.Json {
  json.object([
    #("provider", json.string(source.provider(value))),
    #("reference", json.string(source.reference(value))),
    #("kind", json.string("exchange")),
  ])
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
