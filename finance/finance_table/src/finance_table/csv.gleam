import finance_table/render
import finance_table/table.{type Row, type Table}
import gleam/list
import gleam/string

pub fn render(table: Table) -> String {
  let header =
    table.columns(table)
    |> list.map(fn(column) { escape(column.heading) })
    |> string.join(",")
  let rows = table.rows(table) |> list.map(render_row)
  [header, ..rows] |> string.join("\n")
}

fn render_row(row: Row) -> String {
  row.cells
  |> list.map(fn(cell) { cell |> render.cell_text |> escape })
  |> string.join(",")
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
