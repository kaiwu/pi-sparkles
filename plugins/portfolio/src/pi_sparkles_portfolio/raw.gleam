import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Format {
  Csv
  Json
}

pub type Delimiter {
  Comma
  Tab
  Semicolon
}

pub type DecimalConvention {
  PlainDot
  CommaGroupedDot
  SpaceGroupedComma
}

pub type Budgets {
  Budgets(
    maximum_rows: Int,
    maximum_columns: Int,
    maximum_field_bytes: Int,
    maximum_json_depth: Int,
    maximum_json_elements: Int,
  )
}

pub type Value {
  Absent
  Redacted
  Null
  Text(String)
  Boolean(Bool)
  Integer(Int)
  Floating(Float)
  Array(List(Value))
  Object(Dict(String, Value))
}

pub type RawRow {
  RawRow(source_index: Int, fields: Dict(String, Value))
}

pub type Truncation {
  NotTruncated
  TruncatedByRows(maximum: Int, total: Int, next_source_index: Int)
  TruncatedByBytes(retained: Int, total: Int, next_source_index: Int)
}

pub type Document {
  Document(
    snapshot: Dict(String, Value),
    rows: List(RawRow),
    total_rows: Int,
    truncation: Truncation,
    top_level_extras: Dict(String, Value),
  )
}

pub type Error {
  InvalidCsv
  InvalidJson(json.DecodeError)
  InvalidJsonShape
  JsonByteTruncation
  MissingHeader
  DuplicateHeader(String)
  EmptyHeader
  TooManyColumns(maximum: Int, received: Int)
  FieldTooLarge(maximum: Int, received: Int)
  ControlCharacter
  JsonTooDeep(maximum: Int, received: Int)
  TooManyJsonElements(maximum: Int, received: Int)
  MissingSnapshotField(String)
  ConflictingSnapshotField(String)
}

type CsvScan {
  CsvScan(
    rows_reversed: List(List(String)),
    row_reversed: List(String),
    field_reversed: List(String),
    in_quotes: Bool,
    closed_quote: Bool,
  )
}

pub fn decode_csv(
  source: String,
  delimiter: Delimiter,
  budgets: Budgets,
  byte_truncation: Option(#(Int, Int)),
) -> Result(Document, Error) {
  use rows <- result.try(scan_csv(
    string.to_graphemes(source),
    delimiter_character(delimiter),
    CsvScan([], [], [], False, False),
    byte_truncation != None,
  ))
  use header_and_rows <- result.try(case rows {
    [] -> Error(MissingHeader)
    [header, ..rows] -> Ok(#(header, rows))
  })
  let #(header, data_rows) = header_and_rows
  use header <- result.try(validate_header(header, budgets))
  use Nil <- result.try(validate_csv_rows(data_rows, header, budgets))
  let all_rows =
    data_rows
    |> list.index_map(fn(values, index) {
      RawRow(index + 2, row_dict(header, values))
    })
  use snapshot <- result.try(csv_snapshot(all_rows))
  let total = list.length(all_rows)
  let retained = list.take(all_rows, budgets.maximum_rows)
  let row_truncated = total > budgets.maximum_rows
  let truncation = case byte_truncation, row_truncated {
    Some(#(retained_bytes, total_bytes)), _ ->
      TruncatedByBytes(retained_bytes, total_bytes, list.length(retained) + 2)
    None, True ->
      TruncatedByRows(budgets.maximum_rows, total, budgets.maximum_rows + 2)
    None, False -> NotTruncated
  }
  Ok(Document(snapshot, retained, total, truncation, dict.new()))
}

pub fn decode_json(
  source: String,
  budgets: Budgets,
  byte_truncated: Bool,
) -> Result(Document, Error) {
  use Nil <- result.try(case byte_truncated {
    True -> Error(JsonByteTruncation)
    False -> Ok(Nil)
  })
  use root <- result.try(
    source
    |> json.parse(value_decoder())
    |> result.map_error(InvalidJson),
  )
  use Nil <- result.try(validate_json_budgets(root, budgets))
  use root_fields <- result.try(case root {
    Object(fields) -> Ok(fields)
    _ -> Error(InvalidJsonShape)
  })
  use snapshot <- result.try(case dict.get(root_fields, "snapshot") {
    Ok(Object(fields)) -> Ok(fields)
    _ -> Error(InvalidJsonShape)
  })
  use positions <- result.try(case dict.get(root_fields, "positions") {
    Ok(Array(values)) ->
      values
      |> list.index_map(fn(value, index) {
        case value {
          Object(fields) -> Ok(RawRow(index + 1, fields))
          _ -> Error(InvalidJsonShape)
        }
      })
      |> result.all
    _ -> Error(InvalidJsonShape)
  })
  use Nil <- result.try(validate_required_snapshot(snapshot))
  let total = list.length(positions)
  let retained = list.take(positions, budgets.maximum_rows)
  let truncation = case total > budgets.maximum_rows {
    True ->
      TruncatedByRows(budgets.maximum_rows, total, budgets.maximum_rows + 1)
    False -> NotTruncated
  }
  let extras =
    root_fields
    |> dict.delete("snapshot")
    |> dict.delete("positions")
  Ok(Document(snapshot, retained, total, truncation, extras))
}

pub fn value_json(value: Value) -> json.Json {
  case value {
    Absent -> json.object([#("state", json.string("absent_column"))])
    Redacted -> json.object([#("state", json.string("redacted"))])
    Null -> json.null()
    Text(value) -> json.string(value)
    Boolean(value) -> json.bool(value)
    Integer(value) -> json.int(value)
    Floating(value) -> json.float(value)
    Array(values) -> json.array(values, value_json)
    Object(values) ->
      values
      |> dict.to_list
      |> list.map(fn(entry) { #(entry.0, value_json(entry.1)) })
      |> json.object
  }
}

pub fn format_name(value: Format) -> String {
  case value {
    Csv -> "csv"
    Json -> "json"
  }
}

fn scan_csv(
  characters: List(String),
  delimiter: String,
  state: CsvScan,
  truncated: Bool,
) -> Result(List(List(String)), Error) {
  let CsvScan(rows, row, field, in_quotes, closed_quote) = state
  case characters {
    [] if in_quotes && !truncated -> Error(InvalidCsv)
    [] if truncated -> Ok(list.reverse(rows))
    [] -> {
      let has_pending = row != [] || field != [] || closed_quote
      case has_pending {
        False -> Ok(list.reverse(rows))
        True ->
          Ok(
            list.reverse([
              list.reverse([string.concat(list.reverse(field)), ..row]),
              ..rows
            ]),
          )
      }
    }
    ["\"", "\"", ..rest] if in_quotes ->
      scan_csv(
        rest,
        delimiter,
        CsvScan(rows, row, ["\"", ..field], True, False),
        truncated,
      )
    ["\"", ..rest] if in_quotes ->
      scan_csv(
        rest,
        delimiter,
        CsvScan(rows, row, field, False, True),
        truncated,
      )
    [character, ..rest] if in_quotes ->
      case
        invalid_control(character, delimiter)
        && character != "\r"
        && character != "\n"
      {
        True -> Error(ControlCharacter)
        False ->
          scan_csv(
            rest,
            delimiter,
            CsvScan(rows, row, [character, ..field], True, False),
            truncated,
          )
      }
    [character, ..rest] if closed_quote && character == delimiter ->
      scan_csv(
        rest,
        delimiter,
        CsvScan(
          rows,
          [string.concat(list.reverse(field)), ..row],
          [],
          False,
          False,
        ),
        truncated,
      )
    ["\r", "\n", ..rest] if closed_quote ->
      finish_csv_record(rest, delimiter, rows, row, field, truncated)
    ["\n", ..rest] if closed_quote ->
      finish_csv_record(rest, delimiter, rows, row, field, truncated)
    [_, ..] if closed_quote -> Error(InvalidCsv)
    [character, ..rest] if character == delimiter ->
      scan_csv(
        rest,
        delimiter,
        CsvScan(
          rows,
          [string.concat(list.reverse(field)), ..row],
          [],
          False,
          False,
        ),
        truncated,
      )
    ["\r", "\n", ..rest] ->
      finish_csv_record(rest, delimiter, rows, row, field, truncated)
    ["\n", ..rest] ->
      finish_csv_record(rest, delimiter, rows, row, field, truncated)
    ["\"", ..rest] if field == [] ->
      scan_csv(rest, delimiter, CsvScan(rows, row, [], True, False), truncated)
    ["\"", ..] -> Error(InvalidCsv)
    [character, ..rest] ->
      case invalid_control(character, delimiter) {
        True -> Error(ControlCharacter)
        False ->
          scan_csv(
            rest,
            delimiter,
            CsvScan(rows, row, [character, ..field], False, False),
            truncated,
          )
      }
  }
}

fn finish_csv_record(
  rest: List(String),
  delimiter: String,
  rows: List(List(String)),
  row: List(String),
  field: List(String),
  truncated: Bool,
) -> Result(List(List(String)), Error) {
  let complete = list.reverse([string.concat(list.reverse(field)), ..row])
  scan_csv(
    rest,
    delimiter,
    CsvScan([complete, ..rows], [], [], False, False),
    truncated,
  )
}

fn validate_header(
  header: List(String),
  budgets: Budgets,
) -> Result(List(String), Error) {
  use Nil <- result.try(case header {
    [] -> Error(MissingHeader)
    _ -> Ok(Nil)
  })
  use Nil <- result.try(case list.length(header) <= budgets.maximum_columns {
    True -> Ok(Nil)
    False -> Error(TooManyColumns(budgets.maximum_columns, list.length(header)))
  })
  use Nil <- result.try(validate_field_sizes(
    header,
    budgets.maximum_field_bytes,
  ))
  use Nil <- result.try(case list.any(header, fn(value) { value == "" }) {
    True -> Error(EmptyHeader)
    False -> Ok(Nil)
  })
  use Nil <- result.try(find_duplicate_header(header, dict.new()))
  use Nil <- result.try(
    required_snapshot_fields()
    |> list.try_each(fn(name) {
      case list.contains(header, name) {
        True -> Ok(Nil)
        False -> Error(MissingSnapshotField(name))
      }
    }),
  )
  Ok(header)
}

fn validate_csv_rows(
  rows: List(List(String)),
  header: List(String),
  budgets: Budgets,
) -> Result(Nil, Error) {
  rows
  |> list.try_each(fn(row) {
    use Nil <- result.try(case list.length(row) <= list.length(header) {
      True -> Ok(Nil)
      False -> Error(TooManyColumns(list.length(header), list.length(row)))
    })
    validate_field_sizes(row, budgets.maximum_field_bytes)
  })
}

fn validate_field_sizes(
  fields: List(String),
  maximum: Int,
) -> Result(Nil, Error) {
  fields
  |> list.try_each(fn(value) {
    let bytes = bit_array.byte_size(<<value:utf8>>)
    case bytes <= maximum {
      True -> Ok(Nil)
      False -> Error(FieldTooLarge(maximum, bytes))
    }
  })
}

fn find_duplicate_header(
  values: List(String),
  seen: Dict(String, Nil),
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case dict.has_key(seen, value) {
        True -> Error(DuplicateHeader(value))
        False -> find_duplicate_header(rest, dict.insert(seen, value, Nil))
      }
  }
}

fn row_dict(header: List(String), values: List(String)) -> Dict(String, Value) {
  header
  |> list.index_map(fn(name, index) {
    let value = case list.drop(values, index) {
      [value, ..] -> Text(value)
      [] -> Absent
    }
    #(name, value)
  })
  |> dict.from_list
}

fn csv_snapshot(rows: List(RawRow)) -> Result(Dict(String, Value), Error) {
  use first <- result.try(case rows {
    [RawRow(_, fields), ..] -> Ok(fields)
    [] -> Error(InvalidCsv)
  })
  let snapshot =
    snapshot_fields()
    |> list.filter_map(fn(name) {
      case dict.get(first, name) {
        Ok(value) -> Ok(#(name, value))
        Error(_) -> Error(Nil)
      }
    })
    |> dict.from_list
  use Nil <- result.try(validate_required_snapshot(snapshot))
  use Nil <- result.try(
    rows
    |> list.try_each(fn(row) {
      let RawRow(_, fields) = row
      snapshot
      |> dict.to_list
      |> list.try_each(fn(entry) {
        case dict.get(fields, entry.0) {
          Ok(value) if value == entry.1 -> Ok(Nil)
          _ -> Error(ConflictingSnapshotField(entry.0))
        }
      })
    }),
  )
  Ok(snapshot)
}

fn validate_required_snapshot(
  snapshot: Dict(String, Value),
) -> Result(Nil, Error) {
  required_snapshot_fields()
  |> list.try_each(fn(name) {
    case dict.get(snapshot, name) {
      Ok(Text(value)) if value != "" -> Ok(Nil)
      _ -> Error(MissingSnapshotField(name))
    }
  })
}

fn required_snapshot_fields() -> List(String) {
  [
    "snapshot_id",
    "source_kind",
    "base_currency",
    "source_as_of",
    "entitlement",
  ]
}

pub fn snapshot_fields() -> List(String) {
  [
    "snapshot_id",
    "source_kind",
    "account_id",
    "account_type",
    "custodian",
    "base_currency",
    "source_as_of",
    "retrieval_time",
    "statement_period",
    "entitlement",
    "environment",
    "supersedes",
    "source_declared_total",
    "source_total_currency",
  ]
}

fn value_decoder() -> decode.Decoder(Value) {
  use <- decode.recursive
  decode.optional(decode.string)
  |> decode.map(fn(value) {
    case value {
      Some(value) -> Text(value)
      None -> Null
    }
  })
  |> decode.one_of(or: [
    decode.bool |> decode.map(Boolean),
    decode.int |> decode.map(Integer),
    decode.float |> decode.map(Floating),
    decode.list(value_decoder()) |> decode.map(Array),
    decode.dict(decode.string, value_decoder()) |> decode.map(Object),
  ])
}

fn validate_json_budgets(value: Value, budgets: Budgets) -> Result(Nil, Error) {
  let #(depth, elements, columns, largest_field) = json_size(value)
  case
    depth <= budgets.maximum_json_depth,
    elements <= budgets.maximum_json_elements,
    columns <= budgets.maximum_columns,
    largest_field <= budgets.maximum_field_bytes
  {
    False, _, _, _ -> Error(JsonTooDeep(budgets.maximum_json_depth, depth))
    _, False, _, _ ->
      Error(TooManyJsonElements(budgets.maximum_json_elements, elements))
    _, _, False, _ -> Error(TooManyColumns(budgets.maximum_columns, columns))
    _, _, _, False ->
      Error(FieldTooLarge(budgets.maximum_field_bytes, largest_field))
    True, True, True, True -> Ok(Nil)
  }
}

fn json_size(value: Value) -> #(Int, Int, Int, Int) {
  case value {
    Absent | Redacted | Null | Boolean(_) | Integer(_) | Floating(_) -> #(
      1,
      0,
      0,
      0,
    )
    Text(value) -> #(1, 0, 0, bit_array.byte_size(<<value:utf8>>))
    Array(values) ->
      values
      |> list.fold(#(1, list.length(values), 0, 0), fn(total, value) {
        let current = json_size(value)
        #(
          int.max(total.0, current.0 + 1),
          total.1 + current.1,
          int.max(total.2, current.2),
          int.max(total.3, current.3),
        )
      })
    Object(values) ->
      values
      |> dict.to_list
      |> list.fold(#(1, 0, dict.size(values), 0), fn(total, entry) {
        let current = json_size(entry.1)
        #(
          int.max(total.0, current.0 + 1),
          total.1 + current.1,
          int.max(total.2, current.2),
          int.max(
            total.3,
            int.max(bit_array.byte_size(<<entry.0:utf8>>), current.3),
          ),
        )
      })
  }
}

fn invalid_control(character: String, delimiter: String) -> Bool {
  character
  |> string.to_utf_codepoints
  |> list.any(fn(codepoint) {
    let value = string.utf_codepoint_to_int(codepoint)
    value < 32 && character != delimiter
  })
}

fn delimiter_character(value: Delimiter) -> String {
  case value {
    Comma -> ","
    Tab -> "\t"
    Semicolon -> ";"
  }
}
