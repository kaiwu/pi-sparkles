import finance_tushare/query.{type StockBasicQuery}
import finance_tushare/request
import finance_tushare/response.{type Cell}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

pub opaque type Security {
  Security(
    ts_code: String,
    symbol: String,
    name: String,
    full_name: Option(String),
    pinyin: Option(String),
    market: String,
    exchange: String,
    currency: Option(String),
    list_status: String,
    list_date: String,
    delist_date: Option(String),
  )
}

pub type DecodeError {
  InvalidPayload(response.DecodeError)
  UnexpectedFields
  TooManyRows(limit: Int, received: Int)
  InvalidRow(index: Int)
  UnexpectedSecurity(expected: String, received: String)
  UnexpectedExchange(expected: String, received: String)
  UnexpectedStatus(expected: String, received: String)
}

pub fn decode(
  body: String,
  for plan: StockBasicQuery,
) -> Result(List(Security), DecodeError) {
  use payload <- result.try(
    response.decode(body) |> result.map_error(InvalidPayload),
  )
  use _ <- result.try(
    case response.fields(payload) == request.stock_basic_fields {
      True -> Ok(Nil)
      False -> Error(UnexpectedFields)
    },
  )
  let rows = response.rows(payload)
  use _ <- result.try(case list.length(rows) <= query.stock_basic_limit(plan) {
    True -> Ok(Nil)
    False ->
      Error(TooManyRows(query.stock_basic_limit(plan), list.length(rows)))
  })
  decode_rows(rows, plan, 0, [])
}

pub fn ts_code(value: Security) -> String {
  value.ts_code
}

pub fn symbol(value: Security) -> String {
  value.symbol
}

pub fn name(value: Security) -> String {
  value.name
}

pub fn full_name(value: Security) -> Option(String) {
  value.full_name
}

pub fn pinyin(value: Security) -> Option(String) {
  value.pinyin
}

pub fn market(value: Security) -> String {
  value.market
}

pub fn exchange(value: Security) -> String {
  value.exchange
}

pub fn currency(value: Security) -> Option(String) {
  value.currency
}

pub fn list_status(value: Security) -> String {
  value.list_status
}

pub fn list_date(value: Security) -> String {
  value.list_date
}

pub fn delist_date(value: Security) -> Option(String) {
  value.delist_date
}

fn decode_rows(
  rows: List(List(Cell)),
  plan: StockBasicQuery,
  index: Int,
  decoded: List(Security),
) -> Result(List(Security), DecodeError) {
  case rows {
    [] -> Ok(list.reverse(decoded))
    [row, ..rest] -> {
      use security <- result.try(
        decode_row(row) |> result.map_error(fn(_) { InvalidRow(index) }),
      )
      use _ <- result.try(validate_security(security, plan))
      decode_rows(rest, plan, index + 1, [security, ..decoded])
    }
  }
}

fn decode_row(row: List(Cell)) -> Result(Security, Nil) {
  case row {
    [
      ts_code,
      symbol,
      name,
      full_name,
      pinyin,
      market,
      exchange,
      currency,
      status,
      list_date,
      delist_date,
    ] -> {
      use ts_code <- result.try(response.text(ts_code))
      use symbol <- result.try(response.text(symbol))
      use name <- result.try(response.text(name))
      use full_name <- result.try(response.optional_text(full_name))
      use pinyin <- result.try(response.optional_text(pinyin))
      use market <- result.try(response.text(market))
      use exchange <- result.try(response.text(exchange))
      use currency <- result.try(response.optional_text(currency))
      use status <- result.try(response.text(status))
      use list_date <- result.try(response.text(list_date))
      use delist_date <- result.try(response.optional_text(delist_date))
      Ok(Security(
        ts_code,
        symbol,
        name,
        full_name,
        pinyin,
        market,
        exchange,
        currency,
        status,
        list_date,
        delist_date,
      ))
    }
    _ -> Error(Nil)
  }
}

fn validate_security(
  value: Security,
  plan: StockBasicQuery,
) -> Result(Nil, DecodeError) {
  let expected_status = query.list_status_name(query.stock_basic_status(plan))
  use _ <- result.try(case value.list_status == expected_status {
    True -> Ok(Nil)
    False -> Error(UnexpectedStatus(expected_status, value.list_status))
  })
  use _ <- result.try(case query.stock_basic_exchange(plan) {
    option.None -> Ok(Nil)
    option.Some(exchange) -> {
      let expected = query.exchange_name(exchange)
      case value.exchange == expected {
        True -> Ok(Nil)
        False -> Error(UnexpectedExchange(expected, value.exchange))
      }
    }
  })
  use _ <- result.try(case query.stock_basic_name_query(plan) {
    option.None -> Ok(Nil)
    option.Some(name) ->
      case
        string.contains(value.name, name)
        || value.full_name == option.Some(name)
      {
        True -> Ok(Nil)
        False -> Error(UnexpectedSecurity(name, value.name))
      }
  })
  case query.stock_basic_exchange(plan), query.stock_basic_code(plan) {
    option.Some(exchange), option.Some(code) -> {
      let expected = query.ts_code(exchange, code)
      case value.ts_code == expected {
        True -> Ok(Nil)
        False -> Error(UnexpectedSecurity(expected, value.ts_code))
      }
    }
    _, _ -> Ok(Nil)
  }
}
