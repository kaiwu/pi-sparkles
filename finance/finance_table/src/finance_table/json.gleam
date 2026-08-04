import finance_core/currency
import finance_core/decimal
import finance_table/table.{type Cell, type Column, type Row, type Table}
import gleam/int
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

pub fn to_json(table: Table) -> Json {
  json.object([
    #("schema_version", json.int(1)),
    #("caption", optional_string(table.caption(table))),
    #("columns", json.array(table.columns(table), column_json)),
    #("rows", json.array(table.rows(table), row_json)),
    #("notes", json.array(table.notes(table), json.string)),
  ])
}

pub fn encode(table: Table) -> String {
  table |> to_json |> json.to_string
}

fn column_json(column: Column) -> Json {
  json.object([
    #("key", json.string(column.key)),
    #("heading", json.string(column.heading)),
    #("kind", json.string(column_kind_name(column.kind))),
    #("alignment", json.string(alignment_name(column.alignment))),
  ])
}

fn row_json(row: Row) -> Json {
  json.object([
    #("key", optional_string(row.key)),
    #("cells", json.array(row.cells, cell_json)),
  ])
}

fn cell_json(cell: Cell) -> Json {
  case cell {
    table.TextCell(value) -> typed_value("text", json.string(value))
    table.DecimalCell(value) ->
      typed_value("decimal", value |> decimal.to_string |> json.string)
    table.MoneyCell(value) ->
      json.object([
        #("kind", json.string("money")),
        #("amount", value.amount |> decimal.to_string |> json.string),
        #("currency", value.currency |> currency.code |> json.string),
      ])
    table.IntegerCell(value) ->
      typed_value("integer", value |> int.to_string |> json.string)
    table.BooleanCell(value) -> typed_value("boolean", json.bool(value))
    table.MissingCell(reason) ->
      json.object([
        #("kind", json.string("missing")),
        #("reason", json.string(missing_reason_name(reason))),
      ])
  }
}

fn typed_value(kind: String, value: Json) -> Json {
  json.object([#("kind", json.string(kind)), #("value", value)])
}

fn optional_string(value: Option(String)) -> Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn column_kind_name(kind: table.ColumnKind) -> String {
  case kind {
    table.TextColumn -> "text"
    table.DecimalColumn -> "decimal"
    table.MoneyColumn -> "money"
    table.IntegerColumn -> "integer"
    table.BooleanColumn -> "boolean"
  }
}

fn alignment_name(alignment: table.Alignment) -> String {
  case alignment {
    table.Left -> "left"
    table.Right -> "right"
  }
}

fn missing_reason_name(reason: table.MissingReason) -> String {
  case reason {
    table.Unavailable -> "unavailable"
    table.NotApplicable -> "not_applicable"
    table.NotReported -> "not_reported"
    table.Suppressed -> "suppressed"
  }
}
