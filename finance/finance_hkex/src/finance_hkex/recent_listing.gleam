import finance_core/time.{type Date}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

const scope_marker = "Newly Listed and/or Traded Securities in the Current&nbsp;Two Weeks"

pub opaque type Event {
  Event(
    event_date: Date,
    tentative: Bool,
    short_name: String,
    code: String,
    board_lot: String,
    ccass_marker: String,
    short_sell_marker: String,
    stamp_duty_marker: String,
    auction_marker: String,
    corporate_action: String,
    related_code: String,
  )
}

pub opaque type Page {
  Page(updated_as: Date, candidates: List(Event))
}

pub type DecodeError {
  InvalidQueryCode
  InvalidEnvelope
  HeaderMismatch
  InvalidUpdatedAs
  InvalidEventRow
  DuplicateCode(code: String)
}

/// Decode the exact-code rows from HKEX's rolling current-two-week page.
///
/// This decoder deliberately does not turn every row date into a listing
/// start. Only a non-tentative row whose exact corporate action is
/// `New Listing` carries that narrower claim.
pub fn decode(body: String, query_code: String) -> Result(Page, DecodeError) {
  case valid_code(query_code) {
    False -> Error(InvalidQueryCode)
    True -> {
      use table <- result.try(
        target_table(body) |> result.map_error(fn(_) { InvalidEnvelope }),
      )
      use Nil <- result.try(validate_headers(table))
      use updated_as <- result.try(decode_updated_as(body))
      use rows <- result.try(
        between(table, "<tbody>", "</tbody>")
        |> result.map_error(fn(_) { InvalidEnvelope }),
      )
      use events <- result.try(
        rows
        |> string.split("<tr>")
        |> list.filter(fn(row) { string.contains(row, "<td") })
        |> list.try_map(parse_row)
        |> result.map_error(fn(_) { InvalidEventRow }),
      )
      let candidates =
        events |> list.filter(fn(event) { event.code == query_code })
      case candidates {
        [_, _, ..] -> Error(DuplicateCode(query_code))
        values -> Ok(Page(updated_as, values))
      }
    }
  }
}

pub fn updated_as(value: Page) -> Date {
  value.updated_as
}

pub fn candidates(value: Page) -> List(Event) {
  value.candidates
}

pub fn resolution(value: Page) -> String {
  case value.candidates {
    [] -> "no_match"
    [_] -> "unique"
    [_, _, ..] -> "ambiguous"
  }
}

pub fn event_date(value: Event) -> Date {
  value.event_date
}

pub fn tentative(value: Event) -> Bool {
  value.tentative
}

pub fn short_name(value: Event) -> String {
  value.short_name
}

pub fn code(value: Event) -> String {
  value.code
}

pub fn board_lot(value: Event) -> String {
  value.board_lot
}

pub fn ccass_marker(value: Event) -> String {
  value.ccass_marker
}

pub fn short_sell_marker(value: Event) -> String {
  value.short_sell_marker
}

pub fn stamp_duty_marker(value: Event) -> String {
  value.stamp_duty_marker
}

pub fn auction_marker(value: Event) -> String {
  value.auction_marker
}

pub fn corporate_action(value: Event) -> String {
  value.corporate_action
}

pub fn related_code(value: Event) -> String {
  value.related_code
}

pub fn listing_effective_from(value: Event) -> Option(Date) {
  case value.tentative, value.corporate_action {
    False, "New Listing" -> Some(value.event_date)
    _, _ -> None
  }
}

fn target_table(body: String) -> Result(String, Nil) {
  case
    string.contains(body, "<h2>"),
    string.contains(body, "Newly Listed Securities"),
    string.contains(body, "* Being the tentative date of&nbsp;listing / traded")
  {
    True, True, True -> {
      use scoped <- result.try(after(body, scope_marker))
      use opened <- result.try(after(scoped, "<table class=\"table migrate\""))
      between(opened, ">", "</table>")
    }
    _, _, _ -> Error(Nil)
  }
}

fn validate_headers(table: String) -> Result(Nil, DecodeError) {
  let expected = [
    "Date of Listing / Traded",
    "Stock Short Name",
    "Stock Code",
    "Board Lot",
    "Remarks",
    "",
    "",
    "",
    "Corresponding Corporate Action",
    "Related Stock Code",
  ]
  case
    table
    |> string.split("<th ")
    |> list.drop(1)
    |> list.try_map(fn(fragment) {
      use content <- result.try(between(fragment, ">", "</th>"))
      html_text(content)
    })
  {
    Ok(headers) if headers == expected -> Ok(Nil)
    _ -> Error(HeaderMismatch)
  }
}

fn decode_updated_as(body: String) -> Result(Date, DecodeError) {
  use raw <- result.try(
    between(body, "<p class=\"loadMore__timetag\">Updated ", "</p>")
    |> result.map_error(fn(_) { InvalidUpdatedAs }),
  )
  case string.split(normalize_text(raw), " ") {
    [day_text, month_text, year_text] -> {
      use day <- result.try(
        int.parse(day_text) |> result.map_error(fn(_) { InvalidUpdatedAs }),
      )
      use month <- result.try(
        month_number(month_text)
        |> result.map_error(fn(_) { InvalidUpdatedAs }),
      )
      use year <- result.try(
        int.parse(year_text) |> result.map_error(fn(_) { InvalidUpdatedAs }),
      )
      case string.length(day_text), string.length(year_text) {
        2, 4 ->
          time.date(year, month, day)
          |> result.map_error(fn(_) { InvalidUpdatedAs })
        _, _ -> Error(InvalidUpdatedAs)
      }
    }
    _ -> Error(InvalidUpdatedAs)
  }
}

fn parse_row(row: String) -> Result(Event, Nil) {
  use cells <- result.try(
    row
    |> string.split("<td")
    |> list.drop(1)
    |> list.try_map(fn(fragment) {
      use content <- result.try(between(fragment, ">", "</td>"))
      html_text(content)
    }),
  )
  case cells {
    [
      raw_date,
      short_name,
      code,
      board_lot,
      ccass,
      short_sell,
      stamp_duty,
      auction,
      corporate_action,
      related_code,
    ] -> {
      use #(event_date, tentative) <- result.try(parse_event_date(raw_date))
      case
        valid_text(short_name, 200),
        valid_code(code),
        valid_board_lot(board_lot),
        valid_marker(ccass, "#"),
        valid_marker(short_sell, "H"),
        valid_marker(stamp_duty, "S"),
        valid_marker(auction, "%"),
        valid_text(corporate_action, 200),
        related_code == "" || valid_code(related_code)
      {
        True, True, True, True, True, True, True, True, True ->
          Ok(Event(
            event_date,
            tentative,
            short_name,
            code,
            board_lot,
            ccass,
            short_sell,
            stamp_duty,
            auction,
            corporate_action,
            related_code,
          ))
        _, _, _, _, _, _, _, _, _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn parse_event_date(value: String) -> Result(#(Date, Bool), Nil) {
  let tentative = string.ends_with(value, "*")
  let date_text = case tentative {
    True -> string.slice(value, at_index: 0, length: string.length(value) - 1)
    False -> value
  }
  case string.split(date_text, "/") {
    [day_text, month_text, year_text] ->
      case
        int.parse(day_text),
        int.parse(month_text),
        int.parse(year_text),
        string.length(day_text),
        string.length(month_text),
        string.length(year_text)
      {
        Ok(day), Ok(month), Ok(year), 2, 2, 4 ->
          time.date(year, month, day)
          |> result.map(fn(date) { #(date, tentative) })
          |> result.map_error(fn(_) { Nil })
        _, _, _, _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn html_text(value: String) -> Result(String, Nil) {
  case string.split(value, "<") {
    [] -> Ok("")
    [plain, ..tagged] -> {
      use tails <- result.try(
        list.try_map(tagged, fn(fragment) {
          case string.split_once(fragment, on: ">") {
            Ok(#(_, text)) -> Ok(text)
            Error(_) -> Error(Nil)
          }
        }),
      )
      [plain, ..tails]
      |> string.join("")
      |> decode_entities
      |> normalize_text
      |> Ok
    }
  }
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

fn valid_code(value: String) -> Bool {
  string.length(value) == 5
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn valid_board_lot(value: String) -> Bool {
  let digits = string.replace(value, ",", "")
  value != ""
  && string.trim(value) == value
  && !string.starts_with(value, ",")
  && !string.ends_with(value, ",")
  && !string.contains(value, ",,")
  && digits != ""
  && digits
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn valid_marker(value: String, expected: String) -> Bool {
  value == "" || value == expected
}

fn valid_text(value: String, maximum: Int) -> Bool {
  value != "" && string.trim(value) == value && string.length(value) <= maximum
}

fn month_number(value: String) -> Result(Int, Nil) {
  case value {
    "Jan" -> Ok(1)
    "Feb" -> Ok(2)
    "Mar" -> Ok(3)
    "Apr" -> Ok(4)
    "May" -> Ok(5)
    "Jun" -> Ok(6)
    "Jul" -> Ok(7)
    "Aug" -> Ok(8)
    "Sep" -> Ok(9)
    "Oct" -> Ok(10)
    "Nov" -> Ok(11)
    "Dec" -> Ok(12)
    _ -> Error(Nil)
  }
}

fn after(value: String, marker: String) -> Result(String, Nil) {
  case string.split_once(value, on: marker) {
    Ok(#(_, rest)) -> Ok(rest)
    Error(_) -> Error(Nil)
  }
}

fn between(
  value: String,
  start: String,
  finish: String,
) -> Result(String, Nil) {
  use rest <- result.try(after(value, start))
  case string.split_once(rest, on: finish) {
    Ok(#(found, _)) -> Ok(found)
    Error(_) -> Error(Nil)
  }
}
