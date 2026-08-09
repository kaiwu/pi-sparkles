import finance_capco/pdf_text.{type Extraction, type TextItem}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Level {
  Level(code: String, label: String)
}

pub type Classification {
  Classification(
    listing_code: String,
    listing_name: String,
    section: Level,
    manufacturing_subclass: Option(Level),
    division: Level,
  )
}

pub type ParseError {
  InvalidListingCode
  ListingCodeNotFound
  DuplicateListingCode
  MalformedRow(field: String)
}

/// Find exactly one stock-code row in the positioned text extracted from the
/// pinned stock-code-sorted CAPCO PDF.
pub fn find(
  extraction: Extraction,
  listing_code: String,
) -> Result(Classification, ParseError) {
  case valid_listing_code(listing_code) {
    False -> Error(InvalidListingCode)
    True ->
      case matching_rows(extraction.items, listing_code, []) {
        [] -> Error(ListingCodeNotFound)
        [items] -> parse_row(listing_code, items)
        [_, _, ..] -> Error(DuplicateListingCode)
      }
  }
}

fn matching_rows(
  remaining: List(TextItem),
  requested: String,
  found: List(List(TextItem)),
) -> List(List(TextItem)) {
  case remaining {
    [] -> list.reverse(found)
    [item, ..rest] ->
      case row_start(item) {
        False -> matching_rows(rest, requested, found)
        True -> {
          let #(row, after_row) = take_row(rest, item.page, [])
          case string.trim(item.text) == requested {
            True -> matching_rows(after_row, requested, [row, ..found])
            False -> matching_rows(after_row, requested, found)
          }
        }
      }
  }
}

fn take_row(
  remaining: List(TextItem),
  page: Int,
  collected: List(TextItem),
) -> #(List(TextItem), List(TextItem)) {
  case remaining {
    [] -> #(list.reverse(collected), [])
    [item, ..rest] ->
      case item.page != page || row_start(item) {
        True -> #(list.reverse(collected), remaining)
        False -> take_row(rest, page, [item, ..collected])
      }
  }
}

fn parse_row(
  listing_code: String,
  items: List(TextItem),
) -> Result(Classification, ParseError) {
  let listing_name = column_text(items, 70.0, 117.0)
  let section_code = column_text(items, 117.0, 150.0)
  let section_label = column_text(items, 150.0, 259.0)
  let subclass_code = column_text(items, 259.0, 300.0)
  let subclass_label = column_text(items, 300.0, 410.0)
  let division_code = column_text(items, 410.0, 450.0)
  let division_label = column_text(items, 450.0, 1000.0)
  case
    listing_name != "",
    valid_section_code(section_code),
    section_label != "",
    valid_division_code(division_code),
    division_label != "",
    subclass(section_code, subclass_code, subclass_label)
  {
    False, _, _, _, _, _ -> Error(MalformedRow("listing_name"))
    _, False, _, _, _, _ -> Error(MalformedRow("section_code"))
    _, _, False, _, _, _ -> Error(MalformedRow("section_label"))
    _, _, _, False, _, _ -> Error(MalformedRow("division_code"))
    _, _, _, _, False, _ -> Error(MalformedRow("division_label"))
    _, _, _, _, _, Error(field) -> Error(MalformedRow(field))
    True, True, True, True, True, Ok(subclass_value) ->
      Ok(Classification(
        listing_code: listing_code,
        listing_name: listing_name,
        section: Level(section_code, section_label),
        manufacturing_subclass: subclass_value,
        division: Level(division_code, division_label),
      ))
  }
}

fn subclass(
  section_code: String,
  code: String,
  label: String,
) -> Result(Option(Level), String) {
  case section_code, code, label {
    "C", "", "" -> Error("manufacturing_subclass")
    "C", code, label ->
      case valid_subclass_code(code), label != "" {
        False, _ -> Error("manufacturing_subclass_code")
        _, False -> Error("manufacturing_subclass_label")
        True, True -> Ok(Some(Level(code, label)))
      }
    _, "", "" -> Ok(None)
    _, _, _ -> Error("unexpected_manufacturing_subclass")
  }
}

fn column_text(
  items: List(TextItem),
  minimum: Float,
  maximum: Float,
) -> String {
  items
  |> list.filter(fn(item) {
    let value = string.trim(item.text)
    item.x >=. minimum && item.x <. maximum && value != ""
  })
  |> list.map(fn(item) { string.trim(item.text) })
  |> string.join("")
}

fn row_start(item: TextItem) -> Bool {
  item.x >=. 35.0
  && item.x <. 70.0
  && valid_listing_code(string.trim(item.text))
}

fn valid_listing_code(value: String) -> Bool {
  string.length(value) == 6 && ascii_digits(value)
}

fn valid_section_code(value: String) -> Bool {
  string.length(value) == 1
  && string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", value)
}

fn valid_division_code(value: String) -> Bool {
  string.length(value) == 2 && ascii_digits(value)
}

fn valid_subclass_code(value: String) -> Bool {
  string.length(value) == 2
  && string.starts_with(value, "C")
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", character)
    })
  }
}

fn ascii_digits(value: String) -> Bool {
  value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}
