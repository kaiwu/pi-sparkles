import finance_core/time.{type Date}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type Profile {
  Profile(
    code: String,
    name: String,
    category: String,
    subcategory: String,
    board_lot: String,
    isin: String,
    expiry_date: String,
    stamp_duty: String,
    short_sell: String,
    cas: String,
    vcm: String,
    ccass: String,
    debt_board_lot: String,
    debt_investor_type: String,
    pos: String,
    spread_table: String,
    trading_currency: String,
    rmb_counter: String,
  )
}

pub opaque type Lookup {
  Lookup(updated_as: Date, candidates: List(Profile))
}

pub type DecodeError {
  InvalidContentTypes
  InvalidWorkbook
  InvalidWorkbookRelationship
  InvalidSharedStrings
  InvalidWorksheet
  InvalidUpdatedAs
  HeaderMismatch(column: String)
  InvalidProfile(code: String)
  DuplicateCode(code: String)
}

pub fn decode(
  query_code: String,
  content_types: String,
  workbook: String,
  workbook_relationships: String,
  shared_strings: String,
  worksheet: String,
) -> Result(Lookup, DecodeError) {
  use Nil <- result.try(validate_envelope(
    content_types,
    workbook,
    workbook_relationships,
    shared_strings,
    worksheet,
  ))
  use updated_as <- result.try(decode_updated_as(worksheet))
  use Nil <- result.try(validate_headers(worksheet, shared_strings))
  use candidates <- result.try(find_profiles(worksheet, query_code))
  case candidates {
    [_, _, ..] -> Error(DuplicateCode(query_code))
    values -> Ok(Lookup(updated_as, values))
  }
}

pub fn updated_as(value: Lookup) -> Date {
  value.updated_as
}

pub fn candidates(value: Lookup) -> List(Profile) {
  value.candidates
}

pub fn resolution(value: Lookup) -> String {
  case value.candidates {
    [] -> "no_match"
    [_] -> "unique"
    [_, _, ..] -> "ambiguous"
  }
}

pub fn code(value: Profile) -> String {
  value.code
}

pub fn name(value: Profile) -> String {
  value.name
}

pub fn category(value: Profile) -> String {
  value.category
}

pub fn subcategory(value: Profile) -> String {
  value.subcategory
}

pub fn board(value: Profile) -> Option(String) {
  case value.subcategory {
    "Equity Securities (Main Board)" -> Some("main_board")
    "Equity Securities (GEM)" -> Some("gem")
    _ -> None
  }
}

pub fn board_lot(value: Profile) -> String {
  value.board_lot
}

pub fn isin(value: Profile) -> String {
  value.isin
}

pub fn expiry_date(value: Profile) -> String {
  value.expiry_date
}

pub fn stamp_duty(value: Profile) -> String {
  value.stamp_duty
}

pub fn short_sell(value: Profile) -> String {
  value.short_sell
}

pub fn cas(value: Profile) -> String {
  value.cas
}

pub fn vcm(value: Profile) -> String {
  value.vcm
}

pub fn ccass(value: Profile) -> String {
  value.ccass
}

pub fn debt_board_lot(value: Profile) -> String {
  value.debt_board_lot
}

pub fn debt_investor_type(value: Profile) -> String {
  value.debt_investor_type
}

pub fn pos(value: Profile) -> String {
  value.pos
}

pub fn spread_table(value: Profile) -> String {
  value.spread_table
}

pub fn trading_currency(value: Profile) -> String {
  value.trading_currency
}

pub fn rmb_counter(value: Profile) -> String {
  value.rmb_counter
}

fn validate_envelope(
  content_types: String,
  workbook: String,
  workbook_relationships: String,
  shared_strings: String,
  worksheet: String,
) -> Result(Nil, DecodeError) {
  case
    string.contains(
      content_types,
      "PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"",
    )
    && string.contains(
      content_types,
      "PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"",
    )
    && string.contains(
      content_types,
      "PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"",
    )
  {
    False -> Error(InvalidContentTypes)
    True ->
      case
        string.contains(
          workbook,
          "<x:sheet name=\"ListOfSecurities\" sheetId=\"1\" r:id=\"rId1\" />",
        )
      {
        False -> Error(InvalidWorkbook)
        True ->
          case
            string.contains(
              workbook_relationships,
              "Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"",
            )
          {
            False -> Error(InvalidWorkbookRelationship)
            True ->
              case string.contains(shared_strings, ">Spread Table</x:t>") {
                False -> Error(InvalidSharedStrings)
                True ->
                  case
                    string.contains(worksheet, "<x:sheetData>"),
                    string.contains(worksheet, "</x:sheetData>")
                  {
                    True, True -> Ok(Nil)
                    _, _ -> Error(InvalidWorksheet)
                  }
              }
          }
      }
  }
}

fn decode_updated_as(worksheet: String) -> Result(Date, DecodeError) {
  use row <- result.try(
    row_by_number(worksheet, 2) |> result.map_error(fn(_) { InvalidUpdatedAs }),
  )
  use raw <- result.try(
    cell_text(row, "A", 2) |> result.map_error(fn(_) { InvalidUpdatedAs }),
  )
  let prefix = "Updated as at "
  case string.starts_with(raw, prefix) {
    False -> Error(InvalidUpdatedAs)
    True -> {
      let date_text = string.drop_start(raw, up_to: string.length(prefix))
      case string.split(date_text, "/") {
        [day_text, month_text, year_text] ->
          case
            int.parse(day_text),
            int.parse(month_text),
            int.parse(year_text),
            string.length(day_text) == 2,
            string.length(month_text) == 2,
            string.length(year_text) == 4
          {
            Ok(day), Ok(month), Ok(year), True, True, True ->
              time.date(year, month, day)
              |> result.map_error(fn(_) { InvalidUpdatedAs })
            _, _, _, _, _, _ -> Error(InvalidUpdatedAs)
          }
        _ -> Error(InvalidUpdatedAs)
      }
    }
  }
}

fn validate_headers(
  worksheet: String,
  shared_strings: String,
) -> Result(Nil, DecodeError) {
  use row <- result.try(
    row_by_number(worksheet, 3) |> result.map_error(fn(_) { InvalidWorksheet }),
  )
  use Nil <- result.try(validate_header(row, "A", "Stock Code"))
  use Nil <- result.try(validate_header(row, "B", "Name of Securities"))
  use Nil <- result.try(validate_header(row, "C", "Category"))
  use Nil <- result.try(validate_header(row, "D", "Sub-Category"))
  use Nil <- result.try(validate_header(row, "E", "Board Lot"))
  use Nil <- result.try(validate_header(row, "F", "ISIN"))
  use Nil <- result.try(validate_header(row, "G", "Expiry Date"))
  use Nil <- result.try(validate_header(row, "H", "Subject to Stamp Duty"))
  use Nil <- result.try(validate_header(row, "I", "Shortsell Eligible"))
  use Nil <- result.try(validate_header(row, "J", "CAS Eligible"))
  use Nil <- result.try(validate_header(row, "K", "VCM Eligible"))
  use Nil <- result.try(validate_header(row, "L", "Admitted to CCASS"))
  use Nil <- result.try(validate_header(
    row,
    "M",
    "Debt Securities Board Lot (Nominal)",
  ))
  use Nil <- result.try(validate_header(
    row,
    "N",
    "Debt Securities Investor Type",
  ))
  use Nil <- result.try(validate_header(row, "O", "POS Eligible"))
  use Nil <- result.try(validate_header(row, "Q", "Trading Currency"))
  use Nil <- result.try(validate_header(row, "R", "RMB Counter"))
  case cell_text(row, "P", 3) {
    Ok("4") ->
      case string.contains(shared_strings, ">Spread Table</x:t>") {
        True -> Ok(Nil)
        False -> Error(HeaderMismatch("P"))
      }
    _ -> Error(HeaderMismatch("P"))
  }
}

fn validate_header(
  row: String,
  column: String,
  expected: String,
) -> Result(Nil, DecodeError) {
  case cell_text(row, column, 3) {
    Ok(value) if value == expected -> Ok(Nil)
    _ -> Error(HeaderMismatch(column))
  }
}

fn find_profiles(
  worksheet: String,
  query_code: String,
) -> Result(List(Profile), DecodeError) {
  worksheet
  |> string.split("<x:row ")
  |> find_in_rows(query_code, [])
}

fn find_in_rows(
  rows: List(String),
  query_code: String,
  found: List(Profile),
) -> Result(List(Profile), DecodeError) {
  case rows {
    [] -> Ok(list.reverse(found))
    [row, ..rest] ->
      case row_number(row), string.contains(row, "</x:row>") {
        Ok(number), True if number >= 4 ->
          case cell_text(row, "A", number) {
            Ok(code_value) if code_value == query_code -> {
              use profile <- result.try(decode_profile(row, number, query_code))
              find_in_rows(rest, query_code, [profile, ..found])
            }
            _ -> find_in_rows(rest, query_code, found)
          }
        _, _ -> find_in_rows(rest, query_code, found)
      }
  }
}

fn decode_profile(
  row: String,
  number: Int,
  expected_code: String,
) -> Result(Profile, DecodeError) {
  use code_value <- profile_cell(row, "A", number, expected_code)
  use name_value <- profile_cell(row, "B", number, expected_code)
  use category_value <- profile_cell(row, "C", number, expected_code)
  use subcategory_value <- profile_cell(row, "D", number, expected_code)
  use board_lot_value <- profile_cell(row, "E", number, expected_code)
  use isin_value <- profile_cell(row, "F", number, expected_code)
  use expiry_value <- profile_cell(row, "G", number, expected_code)
  use stamp_value <- profile_cell(row, "H", number, expected_code)
  use short_value <- profile_cell(row, "I", number, expected_code)
  use cas_value <- profile_cell(row, "J", number, expected_code)
  use vcm_value <- profile_cell(row, "K", number, expected_code)
  use ccass_value <- profile_cell(row, "L", number, expected_code)
  use debt_lot_value <- profile_cell(row, "M", number, expected_code)
  use investor_value <- profile_cell(row, "N", number, expected_code)
  use pos_value <- profile_cell(row, "O", number, expected_code)
  use spread_value <- profile_cell(row, "P", number, expected_code)
  use currency_value <- profile_cell(row, "Q", number, expected_code)
  use rmb_value <- profile_cell(row, "R", number, expected_code)
  let value =
    Profile(
      code_value,
      name_value,
      category_value,
      subcategory_value,
      board_lot_value,
      isin_value,
      expiry_value,
      stamp_value,
      short_value,
      cas_value,
      vcm_value,
      ccass_value,
      debt_lot_value,
      investor_value,
      pos_value,
      spread_value,
      currency_value,
      rmb_value,
    )
  case
    code_value == expected_code,
    valid_code(code_value),
    valid_required_text(name_value),
    valid_required_text(category_value),
    valid_cell_values(value)
  {
    True, True, True, True, True -> Ok(value)
    _, _, _, _, _ -> Error(InvalidProfile(expected_code))
  }
}

fn profile_cell(
  row: String,
  column: String,
  number: Int,
  code: String,
  next: fn(String) -> Result(value, DecodeError),
) -> Result(value, DecodeError) {
  case cell_text(row, column, number) {
    Ok(value) -> next(value)
    Error(_) -> Error(InvalidProfile(code))
  }
}

fn valid_cell_values(value: Profile) -> Bool {
  [
    value.code,
    value.name,
    value.category,
    value.subcategory,
    value.board_lot,
    value.isin,
    value.expiry_date,
    value.stamp_duty,
    value.short_sell,
    value.cas,
    value.vcm,
    value.ccass,
    value.debt_board_lot,
    value.debt_investor_type,
    value.pos,
    value.spread_table,
    value.trading_currency,
    value.rmb_counter,
  ]
  |> list.all(fn(value) {
    string.length(value) <= 400
    && !string.contains(value, "\r")
    && !string.contains(value, "\n")
  })
}

fn row_by_number(worksheet: String, number: Int) -> Result(String, Nil) {
  let marker = "r=\"" <> int.to_string(number) <> "\""
  worksheet
  |> string.split("<x:row ")
  |> list.find(fn(row) {
    string.starts_with(row, marker) && string.contains(row, "</x:row>")
  })
}

fn row_number(row: String) -> Result(Int, Nil) {
  use value <- result.try(between(row, "r=\"", "\""))
  int.parse(value) |> result.map_error(fn(_) { Nil })
}

fn cell_text(row: String, column: String, number: Int) -> Result(String, Nil) {
  let marker = "<x:c r=\"" <> column <> int.to_string(number) <> "\""
  use tail <- result.try(after(row, marker))
  use body <- result.try(between(tail, ">", "</x:c>"))
  use value <- result.try(between(body, "<x:v>", "</x:v>"))
  decode_xml_text(value)
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

fn decode_xml_text(value: String) -> Result(String, Nil) {
  case string.contains(value, "&#") {
    True -> Error(Nil)
    False ->
      value
      |> string.replace("&lt;", "<")
      |> string.replace("&gt;", ">")
      |> string.replace("&quot;", "\"")
      |> string.replace("&apos;", "'")
      |> string.replace("&amp;", "&")
      |> Ok
  }
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 5
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn valid_required_text(value: String) -> Bool {
  value != "" && string.trim(value) == value && string.length(value) <= 200
}
