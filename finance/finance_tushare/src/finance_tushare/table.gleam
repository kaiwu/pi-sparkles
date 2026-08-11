import finance_tushare/response.{type Cell}
import gleam/list

pub opaque type Table {
  Table(fields: List(String), rows: List(List(Cell)))
}

pub type DecodeError {
  InvalidPayload(response.DecodeError)
  UnexpectedFields
  TooManyRows(limit: Int, received: Int)
  InvalidRowWidth(index: Int, expected: Int, received: Int)
}

pub fn decode(
  body: String,
  expected_fields: List(String),
  limit: Int,
) -> Result(Table, DecodeError) {
  case response.decode(body) {
    Error(error) -> Error(InvalidPayload(error))
    Ok(payload) -> {
      let rows = response.rows(payload)
      case
        response.fields(payload) == expected_fields,
        list.length(rows) <= limit
      {
        False, _ -> Error(UnexpectedFields)
        _, False -> Error(TooManyRows(limit, list.length(rows)))
        True, True ->
          validate_widths(
            rows,
            list.length(expected_fields),
            0,
            Table(expected_fields, rows),
          )
      }
    }
  }
}

pub fn fields(value: Table) -> List(String) {
  value.fields
}

pub fn rows(value: Table) -> List(List(Cell)) {
  value.rows
}

fn validate_widths(
  rows: List(List(Cell)),
  expected: Int,
  index: Int,
  table: Table,
) -> Result(Table, DecodeError) {
  case rows {
    [] -> Ok(table)
    [row, ..rest] ->
      case list.length(row) == expected {
        True -> validate_widths(rest, expected, index + 1, table)
        False -> Error(InvalidRowWidth(index, expected, list.length(row)))
      }
  }
}
