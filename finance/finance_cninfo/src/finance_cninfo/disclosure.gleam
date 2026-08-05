import finance_cninfo.{type DocumentRef}
import finance_core/time.{type Date}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/result
import gleam/string

pub type Category {
  All
  AnnualReport
  HalfYearReport
  FirstQuarterReport
  ThirdQuarterReport
}

pub opaque type Query {
  Query(
    code: String,
    organization_id: String,
    start_date: Date,
    end_date: Date,
    category: Category,
    page: Int,
    page_size: Int,
  )
}

pub opaque type Announcement {
  Announcement(
    code: String,
    short_name: String,
    organization_id: String,
    announcement_id: String,
    title: String,
    provider_time_milliseconds: Int,
    document: DocumentRef,
    size_kilobytes: Int,
    type_codes: Option(String),
  )
}

pub opaque type Page {
  Page(
    total_announcements: Int,
    total_pages: Int,
    has_more: Bool,
    announcements: List(Announcement),
  )
}

pub type QueryError {
  InvalidCode
  InvalidOrganizationId
  InvalidDateRange
  InvalidPage
  InvalidPageSize
}

pub fn query(
  code code_value: String,
  organization_id organization_id_value: String,
  start_date start: Date,
  end_date end: Date,
  category category_value: Category,
  page page_value: Int,
  page_size page_size_value: Int,
) -> Result(Query, QueryError) {
  case
    valid_code(code_value),
    valid_organization_id(organization_id_value),
    string.compare(date_text(start), date_text(end)),
    page_value >= 1 && page_value <= 1000,
    page_size_value >= 1 && page_size_value <= 30
  {
    False, _, _, _, _ -> Error(InvalidCode)
    _, False, _, _, _ -> Error(InvalidOrganizationId)
    _, _, order.Gt, _, _ -> Error(InvalidDateRange)
    _, _, _, False, _ -> Error(InvalidPage)
    _, _, _, _, False -> Error(InvalidPageSize)
    True, True, _, True, True ->
      Ok(Query(
        code_value,
        organization_id_value,
        start,
        end,
        category_value,
        page_value,
        page_size_value,
      ))
  }
}

pub fn decode_page(body: String) -> Result(Page, json.DecodeError) {
  json.parse(body, page_decoder())
}

pub fn form_body(value: Query) -> String {
  [
    #("pageNum", int.to_string(value.page)),
    #("pageSize", int.to_string(value.page_size)),
    #("column", "szse"),
    #("tabName", "fulltext"),
    #("plate", ""),
    #("stock", value.code <> "%2C" <> value.organization_id),
    #("searchkey", ""),
    #("secid", ""),
    #("category", category_code(value.category)),
    #("trade", ""),
    #("seDate", date_text(value.start_date) <> "~" <> date_text(value.end_date)),
    #("sortName", "time"),
    #("sortType", "desc"),
    #("isHLtitle", "true"),
  ]
  |> list.map(fn(value) { value.0 <> "=" <> value.1 })
  |> string.join("&")
}

pub fn safe_variant(value: Query) -> String {
  value.code
  <> ":"
  <> value.organization_id
  <> ":"
  <> date_text(value.start_date)
  <> ":"
  <> date_text(value.end_date)
  <> ":"
  <> category_name(value.category)
  <> ":"
  <> int.to_string(value.page)
  <> ":"
  <> int.to_string(value.page_size)
}

pub fn category_from_name(value: String) -> Result(Category, Nil) {
  case value {
    "all" -> Ok(All)
    "annual" -> Ok(AnnualReport)
    "half_year" -> Ok(HalfYearReport)
    "first_quarter" -> Ok(FirstQuarterReport)
    "third_quarter" -> Ok(ThirdQuarterReport)
    _ -> Error(Nil)
  }
}

pub fn category_name(value: Category) -> String {
  case value {
    All -> "all"
    AnnualReport -> "annual"
    HalfYearReport -> "half_year"
    FirstQuarterReport -> "first_quarter"
    ThirdQuarterReport -> "third_quarter"
  }
}

pub fn total_announcements(value: Page) -> Int {
  value.total_announcements
}

pub fn total_pages(value: Page) -> Int {
  value.total_pages
}

pub fn has_more(value: Page) -> Bool {
  value.has_more
}

pub fn announcements(value: Page) -> List(Announcement) {
  value.announcements
}

pub fn announcement_code(value: Announcement) -> String {
  value.code
}

pub fn announcement_short_name(value: Announcement) -> String {
  value.short_name
}

pub fn announcement_organization_id(value: Announcement) -> String {
  value.organization_id
}

pub fn announcement_id(value: Announcement) -> String {
  value.announcement_id
}

pub fn announcement_title(value: Announcement) -> String {
  value.title
}

pub fn announcement_provider_time_milliseconds(value: Announcement) -> Int {
  value.provider_time_milliseconds
}

pub fn announcement_document(value: Announcement) -> DocumentRef {
  value.document
}

pub fn announcement_size_kilobytes(value: Announcement) -> Int {
  value.size_kilobytes
}

pub fn announcement_type_codes(value: Announcement) -> Option(String) {
  value.type_codes
}

fn page_decoder() -> decode.Decoder(Page) {
  use total <- decode.field("totalAnnouncement", decode.int)
  use total_pages <- decode.field("totalpages", decode.int)
  use has_more <- decode.field("hasMore", decode.bool)
  use announcements <- decode.field(
    "announcements",
    decode.list(of: announcement_decoder()),
  )
  let value = Page(total, total_pages, has_more, announcements)
  case total >= 0 && total_pages >= 0 {
    True -> decode.success(value)
    False -> decode.failure(value, "non-negative CNINFO page counts")
  }
}

fn announcement_decoder() -> decode.Decoder(Announcement) {
  use code <- decode.field("secCode", decode.string)
  use short_name <- decode.field("secName", decode.string)
  use organization_id <- decode.field("orgId", decode.string)
  use announcement_id <- decode.field("announcementId", decode.string)
  use title <- decode.field("announcementTitle", decode.string)
  use provider_time <- decode.field("announcementTime", decode.int)
  use adjunct_url <- decode.field("adjunctUrl", decode.string)
  use size <- decode.field("adjunctSize", decode.int)
  use type_codes <- decode.field(
    "announcementType",
    decode.optional(decode.string),
  )
  let placeholder =
    placeholder_announcement(
      code,
      short_name,
      organization_id,
      announcement_id,
      title,
      provider_time,
      size,
      type_codes,
    )
  case
    valid_code(code),
    valid_organization_id(organization_id),
    valid_text(short_name, 200),
    valid_text(title, 1000),
    provider_time >= 0,
    size >= 0,
    document_from_path(adjunct_url, announcement_id)
  {
    True, True, True, True, True, True, Ok(document) ->
      decode.success(Announcement(
        code,
        short_name,
        organization_id,
        announcement_id,
        title,
        provider_time,
        document,
        size,
        type_codes,
      ))
    _, _, _, _, _, _, _ ->
      decode.failure(placeholder, "valid exact CNINFO announcement identity")
  }
}

fn document_from_path(
  path: String,
  expected_identifier: String,
) -> Result(DocumentRef, Nil) {
  case string.split(path, "/") {
    ["finalpage", date, file] -> {
      use #(year, month, day) <- result.try(parse_date(date))
      case string.split(file, ".") {
        [identifier, extension] ->
          case
            identifier == expected_identifier,
            string.uppercase(extension) == "PDF",
            finance_cninfo.document(year, month, day, identifier)
          {
            True, True, Ok(document) -> Ok(document)
            _, _, _ -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn placeholder_announcement(
  code: String,
  short_name: String,
  organization_id: String,
  announcement_id: String,
  title: String,
  provider_time: Int,
  size: Int,
  type_codes: Option(String),
) -> Announcement {
  let assert Ok(document) = finance_cninfo.document(2000, 1, 1, "0000000000")
  Announcement(
    code,
    short_name,
    organization_id,
    announcement_id,
    title,
    provider_time,
    document,
    size,
    type_codes,
  )
}

fn parse_date(value: String) -> Result(#(Int, Int, Int), Nil) {
  case string.split(value, "-") {
    [year, month, day] -> {
      use parsed_year <- result.try(
        int.parse(year) |> result.map_error(fn(_) { Nil }),
      )
      use parsed_month <- result.try(
        int.parse(month) |> result.map_error(fn(_) { Nil }),
      )
      use parsed_day <- result.try(
        int.parse(day) |> result.map_error(fn(_) { Nil }),
      )
      Ok(#(parsed_year, parsed_month, parsed_day))
    }
    _ -> Error(Nil)
  }
}

fn category_code(value: Category) -> String {
  case value {
    All -> ""
    AnnualReport -> "category_ndbg_szsh"
    HalfYearReport -> "category_bndbg_szsh"
    FirstQuarterReport -> "category_yjdbg_szsh"
    ThirdQuarterReport -> "category_sjdbg_szsh"
  }
}

fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 6
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn valid_organization_id(value: String) -> Bool {
  valid_text(value, 100)
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-",
      character,
    )
  })
}

fn valid_text(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
