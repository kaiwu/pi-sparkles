import finance_calendar/date
import finance_core/decimal
import finance_core/time
import finance_tushare/query.{type DailyQuery}
import finance_tushare/request
import finance_tushare/response.{type Cell}
import gleam/int
import gleam/list
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string

pub opaque type Bar {
  Bar(
    date: time.Date,
    open: String,
    high: String,
    low: String,
    close: String,
    previous_close: String,
    change: String,
    change_percent: String,
    volume_lots: String,
    amount_thousand_cny: String,
  )
}

pub opaque type Daily {
  Daily(ts_code: String, bars: List(Bar))
}

pub type DecodeError {
  InvalidPayload(response.DecodeError)
  UnexpectedFields
  TooManyRows(limit: Int, received: Int)
  InvalidRow(index: Int)
  CodeMismatch(expected: String, received: String)
  BarOutsideRange(index: Int)
  OutOfOrder(index: Int)
}

pub fn decode(
  body: String,
  for plan: DailyQuery,
) -> Result(Daily, DecodeError) {
  use payload <- result.try(
    response.decode(body) |> result.map_error(InvalidPayload),
  )
  use _ <- result.try(case response.fields(payload) == request.daily_fields {
    True -> Ok(Nil)
    False -> Error(UnexpectedFields)
  })
  let rows = response.rows(payload)
  use _ <- result.try(case list.length(rows) <= query.daily_limit(plan) {
    True -> Ok(Nil)
    False -> Error(TooManyRows(query.daily_limit(plan), list.length(rows)))
  })
  let expected =
    query.ts_code(query.daily_exchange(plan), query.daily_code(plan))
  use bars <- result.try(
    decode_rows(
      rows,
      expected,
      query.daily_start(plan),
      query.daily_end(plan),
      0,
      [],
    ),
  )
  Ok(Daily(expected, bars))
}

pub fn ts_code(value: Daily) -> String {
  value.ts_code
}

pub fn bars(value: Daily) -> List(Bar) {
  value.bars
}

pub fn date(value: Bar) -> time.Date {
  value.date
}

pub fn open(value: Bar) -> String {
  value.open
}

pub fn high(value: Bar) -> String {
  value.high
}

pub fn low(value: Bar) -> String {
  value.low
}

pub fn close(value: Bar) -> String {
  value.close
}

pub fn previous_close(value: Bar) -> String {
  value.previous_close
}

pub fn change(value: Bar) -> String {
  value.change
}

pub fn change_percent(value: Bar) -> String {
  value.change_percent
}

pub fn volume_lots(value: Bar) -> String {
  value.volume_lots
}

pub fn amount_thousand_cny(value: Bar) -> String {
  value.amount_thousand_cny
}

pub fn error_message(value: DecodeError) -> String {
  case value {
    InvalidPayload(error) -> response.error_message(error)
    UnexpectedFields ->
      "Tushare daily fields did not match the requested documented schema"
    TooManyRows(limit, received) ->
      "Tushare daily row count "
      <> int.to_string(received)
      <> " exceeded the caller budget "
      <> int.to_string(limit)
    InvalidRow(index) ->
      "Tushare daily row was invalid at index " <> int.to_string(index)
    CodeMismatch(_, _) ->
      "Tushare daily row identity did not match the exact requested listing"
    BarOutsideRange(index) ->
      "Tushare daily row was outside the requested range at index "
      <> int.to_string(index)
    OutOfOrder(index) ->
      "Tushare daily rows were duplicate or out of descending date order at index "
      <> int.to_string(index)
  }
}

fn decode_rows(
  rows: List(List(Cell)),
  expected: String,
  start: time.Date,
  end: time.Date,
  index: Int,
  decoded: List(Bar),
) -> Result(List(Bar), DecodeError) {
  case rows {
    [] -> Ok(list.reverse(decoded))
    [row, ..rest] -> {
      use #(received, bar) <- result.try(
        decode_row(row) |> result.map_error(fn(_) { InvalidRow(index) }),
      )
      use _ <- result.try(case received == expected {
        True -> Ok(Nil)
        False -> Error(CodeMismatch(expected, received))
      })
      use _ <- result.try(
        case date.compare(bar.date, start), date.compare(bar.date, end) {
          Lt, _ | _, Gt -> Error(BarOutsideRange(index))
          _, _ -> Ok(Nil)
        },
      )
      use _ <- result.try(case decoded {
        [previous, ..] ->
          case date.compare(bar.date, previous.date) {
            Lt -> Ok(Nil)
            _ -> Error(OutOfOrder(index))
          }
        [] -> Ok(Nil)
      })
      decode_rows(rest, expected, start, end, index + 1, [bar, ..decoded])
    }
  }
}

fn decode_row(row: List(Cell)) -> Result(#(String, Bar), Nil) {
  case row {
    [
      code,
      trade_date,
      open,
      high,
      low,
      close,
      previous,
      change,
      percent,
      volume,
      amount,
    ] -> {
      use code <- result.try(response.text(code))
      use trade_date <- result.try(response.text(trade_date))
      use civil <- result.try(parse_date(trade_date))
      use values <- result.try(
        sequence_scalars([
          open, high, low, close, previous, change, percent, volume, amount,
        ]),
      )
      let assert [
        open,
        high,
        low,
        close,
        previous,
        change,
        percent,
        volume,
        amount,
      ] = values
      use _ <- result.try(case list.all(values, valid_decimal) {
        True -> Ok(Nil)
        False -> Error(Nil)
      })
      Ok(#(
        code,
        Bar(
          civil,
          open,
          high,
          low,
          close,
          previous,
          change,
          percent,
          volume,
          amount,
        ),
      ))
    }
    _ -> Error(Nil)
  }
}

fn sequence_scalars(values: List(Cell)) -> Result(List(String), Nil) {
  values |> list.try_map(response.scalar)
}

fn valid_decimal(value: String) -> Bool {
  case decimal.parse(value) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn parse_date(value: String) -> Result(time.Date, Nil) {
  case string.length(value) == 8 {
    False -> Error(Nil)
    True -> {
      use year <- result.try(parse_part(value, 0, 4))
      use month <- result.try(parse_part(value, 4, 2))
      use day <- result.try(parse_part(value, 6, 2))
      time.date(year, month, day) |> result.map_error(fn(_) { Nil })
    }
  }
}

fn parse_part(value: String, at: Int, length: Int) -> Result(Int, Nil) {
  value
  |> string.slice(at_index: at, length: length)
  |> int.parse
  |> result.map_error(fn(_) { Nil })
}
