import finance_table/render
import finance_table/table.{type Row, type Table}
import gleam/list
import gleam/string

pub fn render(table: Table) -> String {
  render_with(table, fn(value) { value })
}

pub fn render_spreadsheet_safe(table: Table) -> String {
  render_with(table, spreadsheet_safe)
}

fn render_with(table: Table, protect: fn(String) -> String) -> String {
  let header =
    table.columns(table)
    |> list.map(fn(column) { column.heading |> protect |> escape })
    |> string.join(",")
  let rows = table.rows(table) |> list.map(render_row(_, protect))
  [header, ..rows] |> string.join("\n")
}

fn render_row(row: Row, protect: fn(String) -> String) -> String {
  row.cells
  |> list.map(fn(cell) { cell |> render.cell_text |> protect |> escape })
  |> string.join(",")
}

fn spreadsheet_safe(value: String) -> String {
  case
    string.starts_with(value, "=")
    || string.starts_with(value, "+")
    || string.starts_with(value, "-")
    || string.starts_with(value, "@")
    || string.starts_with(value, "\t")
    || string.starts_with(value, "\r")
  {
    True -> "'" <> value
    False -> value
  }
}

fn escape(value: String) -> String {
  case
    string.contains(value, ",")
    || string.contains(value, "\"")
    || string.contains(value, "\n")
    || string.contains(value, "\r")
  {
    True -> "\"" <> string.replace(value, "\"", "\"\"") <> "\""
    False -> value
  }
}
