import finance_calendar/date
import finance_core/decimal
import finance_core/time
import finance_eastmoney/query.{type HistoryQuery}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string

pub opaque type Bar {
  Bar(
    date: time.Date,
    open: String,
    close: String,
    high: String,
    low: String,
    volume: String,
    amount: String,
    amplitude_percent: String,
    change_percent: String,
    change: String,
    turnover_percent: String,
  )
}

pub opaque type History {
  History(code: String, name: String, bars: List(Bar))
}

type Payload {
  Payload(code: String, name: String, klines: List(String))
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  CodeMismatch(expected: String, received: String)
  TooManyBars(limit: Int, received: Int)
  InvalidBar(index: Int)
  BarOutsideRange(index: Int)
}

pub fn decode(
  body: String,
  for plan: HistoryQuery,
) -> Result(History, DecodeError) {
  use payload <- result.try(
    json.parse(body, payload_decoder()) |> result.map_error(InvalidJson),
  )
  let expected = query.history_code(plan)
  case
    payload.code == expected,
    list.length(payload.klines) <= query.history_limit(plan)
  {
    False, _ -> Error(CodeMismatch(expected, payload.code))
    _, False ->
      Error(TooManyBars(query.history_limit(plan), list.length(payload.klines)))
    True, True -> {
      use bars <- result.try(
        decode_bars(
          payload.klines,
          query.history_start(plan),
          query.history_end(plan),
          0,
          [],
        ),
      )
      Ok(History(payload.code, payload.name, bars))
    }
  }
}

pub fn code(value: History) -> String {
  value.code
}

pub fn name(value: History) -> String {
  value.name
}

pub fn bars(value: History) -> List(Bar) {
  value.bars
}

pub fn date(value: Bar) -> time.Date {
  value.date
}

pub fn open(value: Bar) -> String {
  value.open
}

pub fn close(value: Bar) -> String {
  value.close
}

pub fn high(value: Bar) -> String {
  value.high
}

pub fn low(value: Bar) -> String {
  value.low
}

pub fn volume(value: Bar) -> String {
  value.volume
}

pub fn amount(value: Bar) -> String {
  value.amount
}

pub fn amplitude_percent(value: Bar) -> String {
  value.amplitude_percent
}

pub fn change_percent(value: Bar) -> String {
  value.change_percent
}

pub fn change(value: Bar) -> String {
  value.change
}

pub fn turnover_percent(value: Bar) -> String {
  value.turnover_percent
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use rc <- decode.field("rc", decode.int)
  use value <- decode.field("data", payload_data_decoder())
  case rc == 0 {
    True -> decode.success(value)
    False -> decode.failure(value, "successful Eastmoney history response")
  }
}

fn payload_data_decoder() -> decode.Decoder(Payload) {
  use code <- decode.field("code", decode.string)
  use name <- decode.field("name", decode.string)
  use klines <- decode.field("klines", decode.list(of: decode.string))
  let value = Payload(code, name, klines)
  case code != "", name != "" && string.trim(name) == name {
    True, True -> decode.success(value)
    _, _ -> decode.failure(value, "valid Eastmoney history identity")
  }
}

fn decode_bars(
  values: List(String),
  start: time.Date,
  end: time.Date,
  index: Int,
  decoded: List(Bar),
) -> Result(List(Bar), DecodeError) {
  case values {
    [] -> Ok(list.reverse(decoded))
    [value, ..rest] ->
      case decode_bar(value) {
        Error(_) -> Error(InvalidBar(index))
        Ok(bar) ->
          case date.compare(bar.date, start), date.compare(bar.date, end) {
            Lt, _ | _, Gt -> Error(BarOutsideRange(index))
            _, _ -> decode_bars(rest, start, end, index + 1, [bar, ..decoded])
          }
      }
  }
}

fn decode_bar(value: String) -> Result(Bar, Nil) {
  case string.split(value, ",") {
    [
      date_text,
      open,
      close,
      high,
      low,
      volume,
      amount,
      amplitude,
      change_percent,
      change,
      turnover,
    ] -> {
      use date <- result.try(parse_date(date_text))
      case
        list.all(
          [
            open,
            close,
            high,
            low,
            volume,
            amount,
            amplitude,
            change_percent,
            change,
            turnover,
          ],
          valid_numeric_lexeme,
        )
      {
        False -> Error(Nil)
        True ->
          Ok(Bar(
            date,
            open,
            close,
            high,
            low,
            volume,
            amount,
            amplitude,
            change_percent,
            change,
            turnover,
          ))
      }
    }
    _ -> Error(Nil)
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

fn valid_numeric_lexeme(value: String) -> Bool {
  case decimal.parse(value) {
    Ok(_) -> True
    Error(_) -> False
  }
}
