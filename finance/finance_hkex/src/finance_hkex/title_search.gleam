import finance_core/time
import finance_hkex.{type DocumentRef}
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub opaque type Plan {
  Plan(stock_id: Int, code: String, limit: Int)
}

pub opaque type Document {
  Document(
    release_time: String,
    codes: List(String),
    names: List(String),
    headline_html: String,
    title: String,
    reference: DocumentRef,
    file_size: String,
  )
}

pub opaque type Page {
  Page(
    stock_id: Int,
    requested_code: String,
    requested_name: String,
    total_records: Int,
    documents: List(Document),
    truncated: Bool,
  )
}

pub type PlanError {
  InvalidStockId
  InvalidCode
  InvalidLimit
}

pub type DecodeError {
  InvalidSearchIdentity
  InvalidTotalRecords
  InvalidDocumentRow
}

pub fn plan(
  stock_id stock_id_value: Int,
  code code_value: String,
  limit limit_value: Int,
) -> Result(Plan, PlanError) {
  case
    stock_id_value > 0,
    valid_code(code_value),
    limit_value >= 1 && limit_value <= 100
  {
    False, _, _ -> Error(InvalidStockId)
    _, False, _ -> Error(InvalidCode)
    _, _, False -> Error(InvalidLimit)
    True, True, True -> Ok(Plan(stock_id_value, code_value, limit_value))
  }
}

pub fn decode(body: String, plan: Plan) -> Result(Page, DecodeError) {
  use stock_id_text <- result.try(
    between(body, "<input id=\"stockId\" type=\"hidden\" value=\"", "\" />")
    |> result.map_error(fn(_) { InvalidSearchIdentity }),
  )
  use stock_id <- result.try(
    int.parse(stock_id_text)
    |> result.map_error(fn(_) { InvalidSearchIdentity }),
  )
  use stock_label <- result.try(
    between(body, "<input id=\"stockCode\" type=\"hidden\" value=\"", "\" />")
    |> result.map_error(fn(_) { InvalidSearchIdentity }),
  )
  use total_text <- result.try(
    between(
      body,
      "<div class=\"total-records\">Total records found: ",
      " </div>",
    )
    |> result.map_error(fn(_) { InvalidTotalRecords }),
  )
  use total <- result.try(
    total_text
    |> string.trim
    |> int.parse
    |> result.map_error(fn(_) { InvalidTotalRecords }),
  )
  let rows =
    body
    |> string.split("<tr>")
    |> list.filter(fn(row) { string.contains(row, "<div class=\"doc-link\">") })
  use decoded <- result.try(
    list.try_map(rows, parse_row)
    |> result.map_error(fn(_) { InvalidDocumentRow }),
  )
  let requested_name =
    stock_label
    |> string.drop_start(up_to: string.length(plan.code))
    |> string.trim
    |> decode_entities
  case
    stock_id == plan.stock_id,
    string.starts_with(stock_label, plan.code <> " "),
    total >= list.length(decoded)
  {
    True, True, True ->
      Ok(Page(
        stock_id,
        plan.code,
        requested_name,
        total,
        list.take(decoded, plan.limit),
        total > plan.limit || list.length(decoded) > plan.limit,
      ))
    False, _, _ | _, False, _ -> Error(InvalidSearchIdentity)
    _, _, False -> Error(InvalidTotalRecords)
  }
}

pub fn stock_id_text(value: Plan) -> String {
  int.to_string(value.stock_id)
}

pub fn stock_id(value: Page) -> Int {
  value.stock_id
}

pub fn requested_code(value: Page) -> String {
  value.requested_code
}

pub fn requested_name(value: Page) -> String {
  value.requested_name
}

pub fn total_records(value: Page) -> Int {
  value.total_records
}

pub fn documents(value: Page) -> List(Document) {
  value.documents
}

pub fn truncated(value: Page) -> Bool {
  value.truncated
}

pub fn release_time(value: Document) -> String {
  value.release_time
}

pub fn codes(value: Document) -> List(String) {
  value.codes
}

pub fn names(value: Document) -> List(String) {
  value.names
}

pub fn headline_html(value: Document) -> String {
  value.headline_html
}

pub fn title(value: Document) -> String {
  value.title
}

pub fn reference(value: Document) -> DocumentRef {
  value.reference
}

pub fn file_size(value: Document) -> String {
  value.file_size
}

fn parse_row(value: String) -> Result(Document, Nil) {
  use release_time <- result.try(
    between(value, "Release Time: </span>", "</td>")
    |> result.map(normalize_text),
  )
  use codes_text <- result.try(between(value, "Stock Code: </span>", "</td>"))
  use names_text <- result.try(between(
    value,
    "Stock Short Name: </span>",
    "</td>",
  ))
  use headline <- result.try(
    between(value, "<div class=\"headline\">", "<br/>")
    |> result.map(normalize_text),
  )
  use path <- result.try(between(value, "<a href=\"", "\""))
  use title <- result.try(
    between(value, "target=\"_blank\">", "</a>")
    |> result.map(normalize_text)
    |> result.map(decode_entities),
  )
  use file_size <- result.try(
    between(value, "<span class=\"attachment_filesize\">", "</span>")
    |> result.map(normalize_text),
  )
  use reference <- result.try(document_from_path(path))
  let code_values = split_breaks(codes_text)
  let name_values = split_breaks(names_text) |> list.map(decode_entities)
  case
    valid_release_time(release_time),
    code_values != [] && list.all(code_values, valid_code),
    name_values != []
    && list.all(name_values, fn(item) { valid_text(item, 200) }),
    valid_text(title, 1000),
    valid_text(file_size, 40)
  {
    True, True, True, True, True ->
      Ok(Document(
        release_time,
        code_values,
        name_values,
        headline,
        title,
        reference,
        file_size,
      ))
    _, _, _, _, _ -> Error(Nil)
  }
}

fn document_from_path(value: String) -> Result(DocumentRef, Nil) {
  case string.split(value, "/") {
    ["", "listedco", "listconews", "sehk", year, month_day, file] -> {
      use year_value <- result.try(
        int.parse(year) |> result.map_error(fn(_) { Nil }),
      )
      use #(month, day) <- result.try(parse_month_day(month_day))
      case string.split(file, ".") {
        [identifier, extension] ->
          case
            string.lowercase(extension) == "pdf",
            finance_hkex.document(year_value, month, day, identifier)
          {
            True, Ok(reference) -> Ok(reference)
            _, _ -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn parse_month_day(value: String) -> Result(#(Int, Int), Nil) {
  case string.length(value) == 4 {
    False -> Error(Nil)
    True -> {
      use month <- result.try(
        value
        |> string.slice(at_index: 0, length: 2)
        |> int.parse
        |> result.map_error(fn(_) { Nil }),
      )
      use day <- result.try(
        value
        |> string.slice(at_index: 2, length: 2)
        |> int.parse
        |> result.map_error(fn(_) { Nil }),
      )
      Ok(#(month, day))
    }
  }
}

fn valid_release_time(value: String) -> Bool {
  case string.split(value, " ") {
    [date, clock] ->
      case string.split(date, "/"), string.split(clock, ":") {
        [day, month, year], [hour, minute] ->
          case
            int.parse(year),
            int.parse(month),
            int.parse(day),
            int.parse(hour),
            int.parse(minute)
          {
            Ok(year), Ok(month), Ok(day), Ok(hour), Ok(minute) ->
              case time.date(year, month, day), time.time_of_day(hour, minute) {
                Ok(_), Ok(_) -> True
                _, _ -> False
              }
            _, _, _, _, _ -> False
          }
        _, _ -> False
      }
    _ -> False
  }
}

fn between(
  value: String,
  start: String,
  finish: String,
) -> Result(String, Nil) {
  case string.split_once(value, on: start) {
    Error(_) -> Error(Nil)
    Ok(#(_, rest)) ->
      case string.split_once(rest, on: finish) {
        Error(_) -> Error(Nil)
        Ok(#(found, _)) -> Ok(found)
      }
  }
}

fn split_breaks(value: String) -> List(String) {
  value
  |> string.split("<br/>")
  |> list.map(normalize_text)
  |> list.filter(fn(item) { item != "" })
}

fn normalize_text(value: String) -> String {
  value
  |> string.replace("\r", " ")
  |> string.replace("\n", " ")
  |> string.replace("\t", " ")
  |> string.split(" ")
  |> list.filter(fn(item) { item != "" })
  |> string.join(" ")
  |> string.trim
}

fn decode_entities(value: String) -> String {
  value
  |> string.replace("&amp;", "&")
  |> string.replace("&quot;", "\"")
  |> string.replace("&#x27;", "'")
  |> string.replace("&#x2f;", "/")
  |> string.replace("&#x2F;", "/")
  |> string.replace("&lt;", "<")
  |> string.replace("&gt;", ">")
  |> string.replace("&nbsp;", " ")
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 5
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn valid_text(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
