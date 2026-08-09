import finance_calendar/date
import finance_core/decimal
import finance_core/time.{type Date}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string

pub type ActionType {
  CashDividendType
  StockDividendType
  ForwardSplitType
  ReverseSplitType
  NameChangeType
}

pub type DataQuality {
  Complete
  All
}

pub type Query {
  Query(
    symbol: String,
    cusip: String,
    start_date: Date,
    end_date: Date,
    types: List(ActionType),
    data_quality: DataQuality,
    page_size: Int,
    maximum_pages: Int,
    maximum_actions: Int,
  )
}

pub type CashDividend {
  CashDividend(
    id: String,
    symbol: Option(String),
    cusip: Option(String),
    isin: Option(String),
    rate: Option(String),
    special: Option(Bool),
    foreign: Option(Bool),
    process_date: Option(String),
    ex_date: Option(String),
    record_date: Option(String),
    payable_date: Option(String),
    due_bill_on_date: Option(String),
    due_bill_off_date: Option(String),
    currency: Option(String),
    sub_type: Option(String),
  )
}

pub type StockDividend {
  StockDividend(
    id: String,
    symbol: Option(String),
    cusip: Option(String),
    isin: Option(String),
    rate: Option(String),
    process_date: Option(String),
    ex_date: Option(String),
    record_date: Option(String),
    payable_date: Option(String),
    currency: Option(String),
  )
}

pub type ForwardSplit {
  ForwardSplit(
    id: String,
    symbol: Option(String),
    cusip: Option(String),
    isin: Option(String),
    old_rate: Option(String),
    new_rate: Option(String),
    process_date: Option(String),
    ex_date: Option(String),
    record_date: Option(String),
    payable_date: Option(String),
    due_bill_redemption_date: Option(String),
    currency: Option(String),
  )
}

pub type ReverseSplit {
  ReverseSplit(
    id: String,
    symbol: Option(String),
    new_symbol: Option(String),
    old_cusip: Option(String),
    new_cusip: Option(String),
    old_isin: Option(String),
    new_isin: Option(String),
    old_rate: Option(String),
    new_rate: Option(String),
    process_date: Option(String),
    ex_date: Option(String),
    record_date: Option(String),
    payable_date: Option(String),
    currency: Option(String),
  )
}

pub type NameChange {
  NameChange(
    id: String,
    old_symbol: Option(String),
    new_symbol: Option(String),
    old_cusip: Option(String),
    new_cusip: Option(String),
    old_isin: Option(String),
    new_isin: Option(String),
    process_date: Option(String),
    currency: Option(String),
  )
}

pub type Page {
  Page(
    cash_dividends: List(CashDividend),
    stock_dividends: List(StockDividend),
    forward_splits: List(ForwardSplit),
    reverse_splits: List(ReverseSplit),
    name_changes: List(NameChange),
    next_page_token: Option(String),
  )
}

pub type QueryError {
  InvalidSymbol
  InvalidCusip
  InvalidDateRange
  EmptyTypes
  DuplicateType(ActionType)
  InvalidPageSize
  InvalidMaximumPages
  InvalidMaximumActions
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  TooManyActions(maximum: Int, received: Int)
  UnexpectedActionType(ActionType)
  InvalidField
  ProcessDateOutsideRange
  OutOfOrder
  InvalidPageToken
}

pub fn query(
  symbol: String,
  cusip: String,
  start_date: Date,
  end_date: Date,
  types: List(ActionType),
  data_quality: DataQuality,
  page_size: Int,
  maximum_pages: Int,
  maximum_actions: Int,
) -> Result(Query, QueryError) {
  case
    valid_symbol(symbol),
    valid_cusip(cusip),
    date.compare(start_date, end_date),
    types,
    duplicate_type(types),
    page_size >= 1 && page_size <= 1000,
    maximum_pages >= 1 && maximum_pages <= 10,
    maximum_actions >= 1 && maximum_actions <= 5000
  {
    False, _, _, _, _, _, _, _ -> Error(InvalidSymbol)
    _, False, _, _, _, _, _, _ -> Error(InvalidCusip)
    _, _, Gt, _, _, _, _, _ -> Error(InvalidDateRange)
    _, _, _, [], _, _, _, _ -> Error(EmptyTypes)
    _, _, _, _, Some(value), _, _, _ -> Error(DuplicateType(value))
    _, _, _, _, _, False, _, _ -> Error(InvalidPageSize)
    _, _, _, _, _, _, False, _ -> Error(InvalidMaximumPages)
    _, _, _, _, _, _, _, False -> Error(InvalidMaximumActions)
    True, True, _, [_, ..], None, True, True, True ->
      Ok(Query(
        symbol,
        cusip,
        start_date,
        end_date,
        types,
        data_quality,
        page_size,
        maximum_pages,
        maximum_actions,
      ))
  }
}

pub fn decode_page(
  body: String,
  query: Query,
  page_limit: Int,
) -> Result(Page, DecodeError) {
  use page <- result.try(
    body
    |> normalize_numbers
    |> json.parse(page_decoder())
    |> result.map_error(InvalidJson),
  )
  let received =
    list.length(page.cash_dividends)
    + list.length(page.stock_dividends)
    + list.length(page.forward_splits)
    + list.length(page.reverse_splits)
    + list.length(page.name_changes)
  use Nil <- result.try(case received <= page_limit {
    True -> Ok(Nil)
    False -> Error(TooManyActions(page_limit, received))
  })
  use Nil <- result.try(validate_requested_types(page, query.types))
  use Nil <- result.try(validate_page_token(page.next_page_token))
  use Nil <- result.try(validate_page(page, query))
  Ok(page)
}

pub fn action_type_name(value: ActionType) -> String {
  case value {
    CashDividendType -> "cash_dividend"
    StockDividendType -> "stock_dividend"
    ForwardSplitType -> "forward_split"
    ReverseSplitType -> "reverse_split"
    NameChangeType -> "name_change"
  }
}

pub fn data_quality_name(value: DataQuality) -> String {
  case value {
    Complete -> "complete"
    All -> "all"
  }
}

pub fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> pad(month) <> "-" <> pad(day)
}

fn page_decoder() -> decode.Decoder(Page) {
  use fields <- decode.then(decode.dict(decode.string, any_value_decoder()))
  use next_page_token <- decode.field(
    "next_page_token",
    decode.optional(decode.string),
  )
  use page <- decode.field(
    "corporate_actions",
    actions_decoder(next_page_token),
  )
  case
    fields
    |> dict.keys
    |> list.all(fn(name) {
      list.contains(["corporate_actions", "next_page_token"], name)
    })
  {
    True -> decode.success(page)
    False -> decode.failure(page, "exact corporate actions response fields")
  }
}

fn actions_decoder(next_page_token: Option(String)) -> decode.Decoder(Page) {
  use fields <- decode.then(decode.dict(decode.string, any_value_decoder()))
  use cash_dividends <- decode.optional_field(
    "cash_dividends",
    [],
    decode.list(of: cash_dividend_decoder()),
  )
  use stock_dividends <- decode.optional_field(
    "stock_dividends",
    [],
    decode.list(of: stock_dividend_decoder()),
  )
  use forward_splits <- decode.optional_field(
    "forward_splits",
    [],
    decode.list(of: forward_split_decoder()),
  )
  use reverse_splits <- decode.optional_field(
    "reverse_splits",
    [],
    decode.list(of: reverse_split_decoder()),
  )
  use name_changes <- decode.optional_field(
    "name_changes",
    [],
    decode.list(of: name_change_decoder()),
  )
  let page =
    Page(
      cash_dividends,
      stock_dividends,
      forward_splits,
      reverse_splits,
      name_changes,
      next_page_token,
    )
  case
    fields
    |> dict.keys
    |> list.all(fn(name) {
      list.contains(
        [
          "cash_dividends",
          "stock_dividends",
          "forward_splits",
          "reverse_splits",
          "name_changes",
        ],
        name,
      )
    })
  {
    True -> decode.success(page)
    False -> decode.failure(page, "only requested corporate action groups")
  }
}

fn any_value_decoder() -> decode.Decoder(Nil) {
  decode.new_primitive_decoder("JSON value", accept_any_value)
}

fn accept_any_value(_value: Dynamic) -> Result(Nil, Nil) {
  Ok(Nil)
}

fn cash_dividend_decoder() -> decode.Decoder(CashDividend) {
  use id <- decode.field("id", decode.string)
  use symbol <- optional_string("symbol")
  use cusip <- optional_string("cusip")
  use isin <- optional_string("isin")
  use rate <- optional_number("rate")
  use special <- optional_bool("special")
  use foreign <- optional_bool("foreign")
  use process_date <- optional_date("process_date")
  use ex_date <- optional_date("ex_date")
  use record_date <- optional_date("record_date")
  use payable_date <- optional_date("payable_date")
  use due_bill_on_date <- optional_date("due_bill_on_date")
  use due_bill_off_date <- optional_date("due_bill_off_date")
  use currency <- optional_string("currency")
  use sub_type <- optional_string("sub_type")
  case
    valid_id(id),
    valid_optional_decimal(rate),
    valid_date_values([
      process_date,
      ex_date,
      record_date,
      payable_date,
      due_bill_on_date,
      due_bill_off_date,
    ])
  {
    True, True, True ->
      decode.success(CashDividend(
        id,
        symbol,
        cusip,
        isin,
        rate,
        special,
        foreign,
        process_date,
        ex_date,
        record_date,
        payable_date,
        due_bill_on_date,
        due_bill_off_date,
        currency,
        sub_type,
      ))
    _, _, _ -> decode.failure(empty_cash_dividend(), "valid cash dividend")
  }
}

fn stock_dividend_decoder() -> decode.Decoder(StockDividend) {
  use id <- decode.field("id", decode.string)
  use symbol <- optional_string("symbol")
  use cusip <- optional_string("cusip")
  use isin <- optional_string("isin")
  use rate <- optional_number("rate")
  use process_date <- optional_date("process_date")
  use ex_date <- optional_date("ex_date")
  use record_date <- optional_date("record_date")
  use payable_date <- optional_date("payable_date")
  use currency <- optional_string("currency")
  case
    valid_id(id),
    valid_optional_decimal(rate),
    valid_date_values([process_date, ex_date, record_date, payable_date])
  {
    True, True, True ->
      decode.success(StockDividend(
        id,
        symbol,
        cusip,
        isin,
        rate,
        process_date,
        ex_date,
        record_date,
        payable_date,
        currency,
      ))
    _, _, _ -> decode.failure(empty_stock_dividend(), "valid stock dividend")
  }
}

fn forward_split_decoder() -> decode.Decoder(ForwardSplit) {
  use id <- decode.field("id", decode.string)
  use symbol <- optional_string("symbol")
  use cusip <- optional_string("cusip")
  use isin <- optional_string("isin")
  use old_rate <- optional_number("old_rate")
  use new_rate <- optional_number("new_rate")
  use process_date <- optional_date("process_date")
  use ex_date <- optional_date("ex_date")
  use record_date <- optional_date("record_date")
  use payable_date <- optional_date("payable_date")
  use due_bill_redemption_date <- optional_date("due_bill_redemption_date")
  use currency <- optional_string("currency")
  case
    valid_id(id),
    valid_optional_decimal(old_rate),
    valid_optional_decimal(new_rate),
    valid_date_values([
      process_date,
      ex_date,
      record_date,
      payable_date,
      due_bill_redemption_date,
    ])
  {
    True, True, True, True ->
      decode.success(ForwardSplit(
        id,
        symbol,
        cusip,
        isin,
        old_rate,
        new_rate,
        process_date,
        ex_date,
        record_date,
        payable_date,
        due_bill_redemption_date,
        currency,
      ))
    _, _, _, _ -> decode.failure(empty_forward_split(), "valid forward split")
  }
}

fn reverse_split_decoder() -> decode.Decoder(ReverseSplit) {
  use id <- decode.field("id", decode.string)
  use symbol <- optional_string("symbol")
  use new_symbol <- optional_string("new_symbol")
  use old_cusip <- optional_string("old_cusip")
  use new_cusip <- optional_string("new_cusip")
  use old_isin <- optional_string("old_isin")
  use new_isin <- optional_string("new_isin")
  use old_rate <- optional_number("old_rate")
  use new_rate <- optional_number("new_rate")
  use process_date <- optional_date("process_date")
  use ex_date <- optional_date("ex_date")
  use record_date <- optional_date("record_date")
  use payable_date <- optional_date("payable_date")
  use currency <- optional_string("currency")
  case
    valid_id(id),
    valid_optional_decimal(old_rate),
    valid_optional_decimal(new_rate),
    valid_date_values([process_date, ex_date, record_date, payable_date])
  {
    True, True, True, True ->
      decode.success(ReverseSplit(
        id,
        symbol,
        new_symbol,
        old_cusip,
        new_cusip,
        old_isin,
        new_isin,
        old_rate,
        new_rate,
        process_date,
        ex_date,
        record_date,
        payable_date,
        currency,
      ))
    _, _, _, _ -> decode.failure(empty_reverse_split(), "valid reverse split")
  }
}

fn name_change_decoder() -> decode.Decoder(NameChange) {
  use id <- decode.field("id", decode.string)
  use old_symbol <- optional_string("old_symbol")
  use new_symbol <- optional_string("new_symbol")
  use old_cusip <- optional_string("old_cusip")
  use new_cusip <- optional_string("new_cusip")
  use old_isin <- optional_string("old_isin")
  use new_isin <- optional_string("new_isin")
  use process_date <- optional_date("process_date")
  use currency <- optional_string("currency")
  case valid_id(id), valid_date_values([process_date]) {
    True, True ->
      decode.success(NameChange(
        id,
        old_symbol,
        new_symbol,
        old_cusip,
        new_cusip,
        old_isin,
        new_isin,
        process_date,
        currency,
      ))
    _, _ -> decode.failure(empty_name_change(), "valid name change")
  }
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn optional_bool(
  name: String,
  next: fn(Option(Bool)) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  decode.optional_field(name, None, decode.optional(decode.bool), next)
}

fn optional_number(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  decode.optional_field(name, None, decode.optional(number_decoder()), next)
}

fn optional_date(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(a),
) -> decode.Decoder(a) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn number_decoder() -> decode.Decoder(String) {
  decode.at(["__finance_market_alpaca_number__"], decode.string)
}

fn validate_requested_types(
  page: Page,
  types: List(ActionType),
) -> Result(Nil, DecodeError) {
  case
    page.cash_dividends != [] && !list.contains(types, CashDividendType),
    page.stock_dividends != [] && !list.contains(types, StockDividendType),
    page.forward_splits != [] && !list.contains(types, ForwardSplitType),
    page.reverse_splits != [] && !list.contains(types, ReverseSplitType),
    page.name_changes != [] && !list.contains(types, NameChangeType)
  {
    True, _, _, _, _ -> Error(UnexpectedActionType(CashDividendType))
    _, True, _, _, _ -> Error(UnexpectedActionType(StockDividendType))
    _, _, True, _, _ -> Error(UnexpectedActionType(ForwardSplitType))
    _, _, _, True, _ -> Error(UnexpectedActionType(ReverseSplitType))
    _, _, _, _, True -> Error(UnexpectedActionType(NameChangeType))
    False, False, False, False, False -> Ok(Nil)
  }
}

fn validate_page(page: Page, query: Query) -> Result(Nil, DecodeError) {
  use Nil <- result.try(validate_dates(
    page.cash_dividends |> list.map(fn(value) { value.process_date }),
    query,
  ))
  use Nil <- result.try(validate_dates(
    page.stock_dividends |> list.map(fn(value) { value.process_date }),
    query,
  ))
  use Nil <- result.try(validate_dates(
    page.forward_splits |> list.map(fn(value) { value.process_date }),
    query,
  ))
  use Nil <- result.try(validate_dates(
    page.reverse_splits |> list.map(fn(value) { value.process_date }),
    query,
  ))
  validate_dates(
    page.name_changes |> list.map(fn(value) { value.process_date }),
    query,
  )
}

fn validate_dates(
  values: List(Option(String)),
  query: Query,
) -> Result(Nil, DecodeError) {
  validate_dates_loop(values, query, None)
}

fn validate_dates_loop(
  values: List(Option(String)),
  query: Query,
  previous: Option(Date),
) -> Result(Nil, DecodeError) {
  case values {
    [] -> Ok(Nil)
    [None, ..rest] -> validate_dates_loop(rest, query, previous)
    [Some(raw), ..rest] -> {
      let assert Ok(value) = parse_date(raw)
      case
        date.compare(value, query.start_date),
        date.compare(value, query.end_date)
      {
        Lt, _ | _, Gt -> Error(ProcessDateOutsideRange)
        _, _ ->
          case previous {
            Some(prior) ->
              case date.compare(value, prior) {
                Lt -> Error(OutOfOrder)
                _ -> validate_dates_loop(rest, query, Some(value))
              }
            None -> validate_dates_loop(rest, query, Some(value))
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

fn valid_optional_decimal(value: Option(String)) -> Bool {
  case value {
    None -> True
    Some(raw) -> decimal.parse(raw) |> result.is_ok
  }
}

fn valid_date_values(values: List(Option(String))) -> Bool {
  values
  |> list.all(fn(value) {
    case value {
      None -> True
      Some(raw) -> parse_date(raw) |> result.is_ok
    }
  })
}

fn parse_date(value: String) -> Result(Date, Nil) {
  case string.split(value, "-") {
    [year, month, day] ->
      case
        int.parse(year),
        int.parse(month),
        int.parse(day),
        string.length(year),
        string.length(month),
        string.length(day)
      {
        Ok(year), Ok(month), Ok(day), 4, 2, 2 ->
          time.date(year, month, day) |> result.map_error(fn(_) { Nil })
        _, _, _, _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn valid_symbol(value: String) -> Bool {
  value != ""
  && value == string.uppercase(value)
  && string.length(value) <= 20
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-", character)
  })
}

fn valid_cusip(value: String) -> Bool {
  string.length(value) == 9
  && value == string.uppercase(value)
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*@#", character)
  })
}

fn valid_id(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn duplicate_type(values: List(ActionType)) -> Option(ActionType) {
  case values {
    [] -> None
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> Some(first)
        False -> duplicate_type(rest)
      }
  }
}

fn empty_cash_dividend() -> CashDividend {
  CashDividend(
    "invalid",
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
  )
}

fn empty_stock_dividend() -> StockDividend {
  StockDividend("invalid", None, None, None, None, None, None, None, None, None)
}

fn empty_forward_split() -> ForwardSplit {
  ForwardSplit(
    "invalid",
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
  )
}

fn empty_reverse_split() -> ReverseSplit {
  ReverseSplit(
    "invalid",
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
  )
}

fn empty_name_change() -> NameChange {
  NameChange("invalid", None, None, None, None, None, None, None, None)
}

fn pad(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

@external(javascript, "./corporate_actions_ffi.mjs", "normalize_numbers")
fn normalize_numbers(source: String) -> String
