import finance_calendar/date
import finance_core/time
import finance_market_alpaca/query.{type DailyBarsQuery}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string

pub opaque type RawBar {
  RawBar(
    timestamp: String,
    at: time.Instant,
    session_date: time.Date,
    open: String,
    high: String,
    low: String,
    close: String,
    volume: String,
    trade_count: String,
    vwap: String,
  )
}

pub opaque type Page {
  Page(bars: List(RawBar), next_page_token: Option(String))
}

type Payload {
  Payload(bars: Dict(String, List(RawBar)), next_page_token: Option(String))
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  UnexpectedSymbols
  TooManyBars(limit: Int, received: Int)
  BarOutsideRange(index: Int)
  OutOfOrder(index: Int)
  InvalidPageToken
}

pub fn decode_page(
  body: String,
  for plan: DailyBarsQuery,
  page_limit page_limit: Int,
) -> Result(Page, DecodeError) {
  use payload <- result.try(
    body
    |> normalize_numbers
    |> json.parse(payload_decoder())
    |> result.map_error(InvalidJson),
  )
  use bars <- result.try(select_symbol(payload.bars, query.symbol(plan)))
  use _ <- result.try(case list.length(bars) <= page_limit {
    True -> Ok(Nil)
    False -> Error(TooManyBars(page_limit, list.length(bars)))
  })
  use _ <- result.try(validate_page_token(payload.next_page_token))
  use _ <- result.try(validate_bars(
    bars,
    query.start_date(plan),
    query.end_date(plan),
    None,
    0,
  ))
  Ok(Page(bars, payload.next_page_token))
}

pub fn bars(value: Page) -> List(RawBar) {
  value.bars
}

pub fn next_page_token(value: Page) -> Option(String) {
  value.next_page_token
}

pub fn timestamp(value: RawBar) -> String {
  value.timestamp
}

pub fn at(value: RawBar) -> time.Instant {
  value.at
}

pub fn session_date(value: RawBar) -> time.Date {
  value.session_date
}

pub fn open(value: RawBar) -> String {
  value.open
}

pub fn high(value: RawBar) -> String {
  value.high
}

pub fn low(value: RawBar) -> String {
  value.low
}

pub fn close(value: RawBar) -> String {
  value.close
}

pub fn volume(value: RawBar) -> String {
  value.volume
}

pub fn trade_count(value: RawBar) -> String {
  value.trade_count
}

pub fn vwap(value: RawBar) -> String {
  value.vwap
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use bars <- decode.field(
    "bars",
    decode.dict(decode.string, decode.list(of: raw_bar_decoder())),
  )
  use token <- decode.field("next_page_token", decode.optional(decode.string))
  decode.success(Payload(bars, token))
}

fn raw_bar_decoder() -> decode.Decoder(RawBar) {
  use timestamp <- decode.field("t", decode.string)
  use open <- decode.field("o", number_decoder())
  use high <- decode.field("h", number_decoder())
  use low <- decode.field("l", number_decoder())
  use close <- decode.field("c", number_decoder())
  use volume <- decode.field("v", number_decoder())
  use trade_count <- decode.field("n", number_decoder())
  use vwap <- decode.field("vw", number_decoder())
  let assert Ok(placeholder_date) = time.date(1970, 1, 1)
  let assert Ok(placeholder_at) = time.instant(0)
  case parse_timestamp(timestamp), int.parse(volume), int.parse(trade_count) {
    Ok(#(at, session_date)), Ok(_), Ok(_) ->
      decode.success(RawBar(
        timestamp,
        at,
        session_date,
        open,
        high,
        low,
        close,
        volume,
        trade_count,
        vwap,
      ))
    _, _, _ ->
      decode.failure(
        RawBar(
          "1970-01-01T00:00:00Z",
          placeholder_at,
          placeholder_date,
          open,
          high,
          low,
          close,
          volume,
          trade_count,
          vwap,
        ),
        "valid Alpaca UTC bar timestamp and integer volume/count",
      )
  }
}

fn number_decoder() -> decode.Decoder(String) {
  decode.at(["__finance_market_alpaca_number__"], decode.string)
}

fn select_symbol(
  values: Dict(String, List(RawBar)),
  expected: String,
) -> Result(List(RawBar), DecodeError) {
  case dict.to_list(values) {
    [] -> Ok([])
    [#(symbol, bars)] if symbol == expected -> Ok(bars)
    _ -> Error(UnexpectedSymbols)
  }
}

fn validate_bars(
  values: List(RawBar),
  start: time.Date,
  end: time.Date,
  previous: Option(time.Instant),
  index: Int,
) -> Result(Nil, DecodeError) {
  case values {
    [] -> Ok(Nil)
    [bar, ..rest] -> {
      case
        date.compare(bar.session_date, start),
        date.compare(bar.session_date, end)
      {
        Lt, _ | _, Gt -> Error(BarOutsideRange(index))
        _, _ ->
          case previous {
            Some(previous_at) ->
              case
                time.unix_milliseconds(bar.at)
                < time.unix_milliseconds(previous_at)
              {
                True -> Error(OutOfOrder(index))
                False ->
                  validate_bars(rest, start, end, Some(bar.at), index + 1)
              }
            None -> validate_bars(rest, start, end, Some(bar.at), index + 1)
          }
      }
    }
  }
}

fn validate_page_token(value: Option(String)) -> Result(Nil, DecodeError) {
  case value {
    None -> Ok(Nil)
    Some(token) ->
      case
        token != ""
        && string.trim(token) == token
        && string.length(token) <= 2048
        && !string.contains(token, "\r")
        && !string.contains(token, "\n")
      {
        True -> Ok(Nil)
        False -> Error(InvalidPageToken)
      }
  }
}

fn parse_timestamp(value: String) -> Result(#(time.Instant, time.Date), Nil) {
  case string.ends_with(value, "Z") {
    False -> Error(Nil)
    True -> {
      let core =
        string.slice(value, at_index: 0, length: string.length(value) - 1)
      case string.split(core, "T") {
        [date_value, clock_value] -> {
          use civil <- result.try(parse_date(date_value))
          use #(hour, minute, second, millisecond) <- result.try(parse_clock(
            clock_value,
          ))
          let assert Ok(epoch) = time.date(1970, 1, 1)
          let milliseconds =
            { date.ordinal(civil) - date.ordinal(epoch) }
            * 86_400_000
            + hour
            * 3_600_000
            + minute
            * 60_000
            + second
            * 1000
            + millisecond
          use instant <- result.try(
            time.instant(milliseconds) |> result.map_error(fn(_) { Nil }),
          )
          Ok(#(instant, civil))
        }
        _ -> Error(Nil)
      }
    }
  }
}

fn parse_date(value: String) -> Result(time.Date, Nil) {
  case string.length(value) == 10 {
    False -> Error(Nil)
    True ->
      case string.split(value, "-") {
        [year, month, day] ->
          case
            string.length(year) == 4
            && string.length(month) == 2
            && string.length(day) == 2
          {
            False -> Error(Nil)
            True -> {
              use year <- result.try(parse_int(year))
              use month <- result.try(parse_int(month))
              use day <- result.try(parse_int(day))
              time.date(year, month, day) |> result.map_error(fn(_) { Nil })
            }
          }
        _ -> Error(Nil)
      }
  }
}

fn parse_clock(value: String) -> Result(#(Int, Int, Int, Int), Nil) {
  let #(whole, fraction) = case string.split(value, ".") {
    [whole] -> #(whole, "")
    [whole, fraction] -> #(whole, fraction)
    _ -> #(value, "invalid")
  }
  case string.length(whole) == 8 {
    False -> Error(Nil)
    True ->
      case string.split(whole, ":") {
        [hour, minute, second] ->
          case
            string.length(hour) == 2
            && string.length(minute) == 2
            && string.length(second) == 2
          {
            False -> Error(Nil)
            True -> {
              use hour <- result.try(parse_int(hour))
              use minute <- result.try(parse_int(minute))
              use second <- result.try(parse_int(second))
              use millisecond <- result.try(parse_fraction(fraction))
              case
                hour >= 0 && hour <= 23,
                minute >= 0 && minute <= 59,
                second >= 0 && second <= 59
              {
                True, True, True -> Ok(#(hour, minute, second, millisecond))
                _, _, _ -> Error(Nil)
              }
            }
          }
        _ -> Error(Nil)
      }
  }
}

fn parse_fraction(value: String) -> Result(Int, Nil) {
  case value {
    "" -> Ok(0)
    _ -> {
      let graphemes = string.to_graphemes(value)
      case
        list.length(graphemes) >= 1
        && list.length(graphemes) <= 9
        && list.all(graphemes, fn(character) {
          string.contains("0123456789", character)
        })
      {
        False -> Error(Nil)
        True -> {
          let padded = value <> "00"
          parse_int(string.slice(padded, at_index: 0, length: 3))
        }
      }
    }
  }
}

fn parse_int(value: String) -> Result(Int, Nil) {
  int.parse(value) |> result.map_error(fn(_) { Nil })
}

@external(javascript, "./bars_ffi.mjs", "normalize_numbers")
fn normalize_numbers(source: String) -> String
