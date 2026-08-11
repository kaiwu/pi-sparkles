import finance_cn_rules/official
import finance_core/decimal
import finance_core/source
import finance_core/time
import finance_listing/effective
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pi
import pi/schema
import pi/tool
import pi_sparkles_cn_stock_rules/query

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "cn_stock_rules",
    "CN stock rules",
    "Project the reviewed effective rule profile for one exact mainland A-share listing context; exceptional or incomplete contexts fail closed",
    "Use after identity resolution to inspect dated tick, order-quantity, odd-lot, and ordinary price-limit rules",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, plan, _signal, _updates, _ctx) {
      case query.run(plan) {
        Error(error) -> tool.reject(error_message(error))
        Ok(profile) ->
          tool.text_result(render(plan, profile), details(plan, profile))
          |> promise.resolve
      }
    },
  )
  promise.resolve(Nil)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required(
      "board",
      schema.string_enum(["main", "star", "chinext", "beijing"]),
    ),
    schema.Required("shareClass", schema.string_enum(["a_share"])),
    schema.Required("securityType", schema.string_enum(["common_stock"])),
    schema.Required("status", schema.string_enum(["listed_normal"])),
    schema.Required("regime", schema.string_enum(["established_normal_equity"])),
    schema.Required(
      "identityEvidenceId",
      schema.string()
        |> schema.with_string_length(1, 256)
        |> schema.described(
          "Upstream exact-listing evidence reference; this tool retains but does not authenticate it",
        ),
    ),
    schema.Required(
      "date",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Gregorian effective date YYYY-MM-DD"),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(query.Plan) {
  use track <- decode.field("track", decode.string)
  use code <- decode.field("code", decode.string)
  use venue <- decode.field("venue", decode.string)
  use board <- decode.field("board", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  use security_type <- decode.field("securityType", decode.string)
  use status <- decode.field("status", decode.string)
  use regime <- decode.field("regime", decode.string)
  use evidence <- decode.field("identityEvidenceId", decode.string)
  use date_text <- decode.field("date", decode.string)
  let assert Ok(placeholder_date) = time.date(2026, 7, 6)
  let assert Ok(placeholder) =
    query.plan(
      "cn",
      "600000",
      "sse",
      "main",
      "a_share",
      "common_stock",
      "listed_normal",
      "established_normal_equity",
      "placeholder",
      placeholder_date,
    )
  case parse_date(date_text) {
    Error(_) -> decode.failure(placeholder, "valid Gregorian date")
    Ok(date) ->
      case
        query.plan(
          track,
          code,
          venue,
          board,
          share_class,
          security_type,
          status,
          regime,
          evidence,
          date,
        )
      {
        Ok(value) -> decode.success(value)
        Error(error) -> decode.failure(placeholder, error_message(error))
      }
  }
}

fn render(plan: query.Plan, value: official.Profile) -> String {
  "CN "
  <> query.code(plan)
  <> " | "
  <> string.uppercase(official.venue_name(official.venue(value)))
  <> " "
  <> official.board_name(official.board(value))
  <> " | "
  <> date_text(query.on(plan))
  <> " | tick CNY "
  <> decimal.to_string(official.tick_size(value))
  <> " | ordinary daily limit "
  <> decimal.to_string(official.daily_price_limit(value))
}

fn details(plan: query.Plan, value: official.Profile) -> json.Json {
  let interval = official.effective(value)
  json.object([
    #("schema", json.string("pi-sparkles/cn-stock-rules-result")),
    #("schemaVersion", json.int(1)),
    #("track", json.string("cn")),
    #("code", json.string(query.code(plan))),
    #("venue", json.string(official.venue_name(official.venue(value)))),
    #("board", json.string(official.board_name(official.board(value)))),
    #("shareClass", json.string("a_share")),
    #("securityType", json.string("common_stock")),
    #("status", json.string("listed_normal")),
    #("regime", json.string("established_normal_equity")),
    #("date", json.string(date_text(query.on(plan)))),
    #(
      "identityEvidence",
      json.object([
        #("evidenceId", json.string(query.identity_evidence_id(plan))),
        #("authentication", json.string("not_authenticated_by_this_tool")),
        #(
          "requiredScope",
          json.string("exact_listing_venue_board_share_class_status_on_date"),
        ),
      ]),
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
      "rules",
      json.object([
        #("currency", json.string("CNY")),
        #("tickSize", json.string(decimal.to_string(official.tick_size(value)))),
        #(
          "minimumBuyQuantityShares",
          json.int(official.minimum_buy_quantity(value)),
        ),
        #(
          "buyQuantityIncrementShares",
          case official.buy_quantity_increment(value) {
            Some(count) -> json.int(count)
            None -> json.null()
          },
        ),
        #("oddLotExit", odd_lot_json(official.odd_lot_exit(value))),
        #(
          "ordinaryDailyPriceLimitRatio",
          json.string(decimal.to_string(official.daily_price_limit(value))),
        ),
      ]),
    ),
    #(
      "source",
      json.object([
        #("provider", json.string(source.provider(official.source(value)))),
        #("reference", json.string(source.reference(official.source(value)))),
        #("clauses", json.array(official.clauses(value), json.string)),
      ]),
    ),
    #("limitations", json.array(official.limitations(value), json.string)),
  ])
}

fn odd_lot_json(value: official.OddLotExit) -> json.Json {
  let official.SellRemainderOnce(threshold) = value
  json.object([
    #("policy", json.string("sell_remainder_once")),
    #("thresholdShares", json.int(threshold)),
  ])
}

fn error_message(value: query.QueryError) -> String {
  case value {
    query.WrongTrack -> "track must be cn"
    query.InvalidCode -> "code must be exactly six digits"
    query.InvalidVenue -> "venue must be sse, szse, or bse"
    query.InvalidBoard -> "board is unsupported"
    query.UnsupportedShareClass -> "only a_share is reviewed"
    query.UnsupportedSecurityType -> "only common_stock is reviewed"
    query.UnsupportedStatus ->
      "exceptional or unproven listing status is unsupported"
    query.UnsupportedRegime ->
      "exceptional or unproven trading regime is unsupported"
    query.InvalidIdentityEvidenceId -> "identityEvidenceId is invalid"
    query.InvalidProfile(official.InvalidVenueBoard) ->
      "venue and board do not form a reviewed exact pair"
    query.InvalidProfile(official.OutsideReviewedInterval) ->
      "date is outside the reviewed rule interval beginning 2026-07-06"
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
