import finance_cn_rules/official
import finance_core/decimal
import finance_core/identifier
import finance_core/source
import finance_core/time
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
import pi_sparkles_cn_market_rules/query

pub type Input {
  Input(
    venue: official.Venue,
    board: official.Board,
    regime: String,
    date: time.Date,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "cn_trading_rules",
    "CN effective trading rules",
    "Return a dated, exchange-sourced standard CNY A-share rule profile for one exact SSE/SZSE/BSE board; reject exceptional or unsupported regimes instead of applying a generic China rule",
    "Inspect tick, quantity, odd-lot exit, and standard daily price-limit rules for an established normal mainland equity",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case
        query.run(
          venue: input.venue,
          board: input.board,
          regime: input.regime,
          on: input.date,
        )
      {
        Error(query.InvalidProfile(official.InvalidVenueBoard)) ->
          tool.reject("CN venue and board do not form an approved exact pair")
        Error(query.InvalidProfile(official.OutsideReviewedInterval)) ->
          tool.reject(
            "CN effective-rule profile starts 2026-07-06; no historical fallback was used",
          )
        Error(query.InvalidRegime) ->
          tool.reject("Only established_normal_equity is source-reviewed")
        Error(_) -> tool.reject("CN effective-rule query was invalid")
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
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required(
      "board",
      schema.string_enum(["main", "star", "chinext", "beijing"]),
    ),
    schema.Required(
      "regime",
      schema.string_enum(["established_normal_equity"])
        |> schema.described(
          "Exceptional IPO, relisting, delisting, warning, and suspension regimes are intentionally unsupported",
        ),
    ),
    schema.Required(
      "date",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Gregorian date YYYY-MM-DD on or after 2026-07-06"),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use venue_text <- decode.field("venue", decode.string)
  use board_text <- decode.field("board", decode.string)
  use regime <- decode.field("regime", decode.string)
  use date_text <- decode.field("date", decode.string)
  let assert Ok(placeholder_date) = time.date(2026, 7, 6)
  let placeholder =
    Input(official.Sse, official.MainBoard, regime, placeholder_date)
  case
    query.venue_from_name(venue_text),
    query.board_from_name(board_text),
    parse_date(date_text)
  {
    Ok(venue), Ok(board), Ok(date) ->
      decode.success(Input(venue, board, regime, date))
    _, _, _ ->
      decode.failure(placeholder, "valid exact CN venue, board, and date")
  }
}

fn render(value: official.Profile, date: time.Date) -> String {
  "CN track | "
  <> string.uppercase(official.venue_name(official.venue(value)))
  <> " "
  <> official.board_name(official.board(value))
  <> " established normal CNY equity rules | "
  <> date_text(date)
  <> " | tick "
  <> decimal.to_string(official.tick_size(value))
  <> " | daily limit "
  <> decimal.to_string(official.daily_price_limit(value))
  <> " | source "
  <> source.reference(official.source(value))
}

fn result_json(value: official.Profile, input: Input) -> json.Json {
  let interval = official.effective(value)
  json.object(
    list.append(track_json.result_fields(context(value)), [
      #("date", json.string(date_text(input.date))),
      #("venue", json.string(official.venue_name(official.venue(value)))),
      #("board", json.string(official.board_name(official.board(value)))),
      #("regime", json.string(input.regime)),
      #("currency", json.string("CNY")),
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
            "tickSize",
            json.string(decimal.to_string(official.tick_size(value))),
          ),
          #(
            "minimumBuyQuantity",
            json.int(official.minimum_buy_quantity(value)),
          ),
          #(
            "buyQuantityIncrement",
            case official.buy_quantity_increment(value) {
              Some(increment) -> json.int(increment)
              None -> json.null()
            },
          ),
          #("oddLotExit", odd_lot_json(official.odd_lot_exit(value))),
          #(
            "dailyPriceLimitRatio",
            json.string(decimal.to_string(official.daily_price_limit(value))),
          ),
          #(
            "priceLimitCalculation",
            json.string(
              "previous_close_x_1_plus_or_minus_ratio_then_exchange_rounding",
            ),
          ),
        ]),
      ),
      #("source", source_json(official.source(value))),
      #("clauses", json.array(official.clauses(value), json.string)),
      #(
        "audit",
        json.object([
          #("profile", json.string("cn_established_normal_cny_equity_v1")),
          #("sourceReviewed", json.bool(True)),
          #("callerMustVerifyListingRegime", json.bool(True)),
          #("redistribution", json.string("unknown")),
        ]),
      ),
      #("limitations", json.array(official.limitations(value), json.string)),
    ]),
  )
}

fn odd_lot_json(value: official.OddLotExit) -> json.Json {
  let official.SellRemainderOnce(threshold) = value
  json.object([
    #("policy", json.string("sell_remainder_once")),
    #("thresholdShares", json.int(threshold)),
  ])
}

fn context(value: official.Profile) -> track_context.Context {
  let mic_name = case official.venue(value) {
    official.Sse -> "XSHG"
    official.Szse -> "XSHE"
    official.Bse -> "XBSE"
  }
  let assert Ok(mic) = identifier.mic(mic_name)
  let assert Ok(zone) = time.timezone("Asia/Shanghai")
  let assert Ok(result) =
    track_context.new(
      track: finance_track.Cn,
      market_scope: "cn_effective_rules",
      venue_mic: Some(mic),
      board: Some(official.board_name(official.board(value))),
      timezone: Some(zone),
      source_language: "zh-CN",
      providers: [source.provider(official.source(value))],
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
