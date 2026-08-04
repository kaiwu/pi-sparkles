import finance_table/render
import finance_table/table.{type Cell, type Row, type Table}
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub fn render(table: Table) -> String {
  let header =
    table.columns(table)
    |> list.map(fn(column) { escape(column.heading) })
    |> markdown_row
  let separator =
    table.columns(table)
    |> list.map(fn(column) {
      case column.alignment {
        table.Left -> ":---"
        table.Right -> "---:"
      }
    })
    |> markdown_row
  let rows = table.rows(table) |> list.map(render_row)
  let body = [header, separator, ..rows] |> string.join("\n")
  let with_caption = case table.caption(table) {
    Some(caption) -> "**" <> escape(caption) <> "**\n\n" <> body
    None -> body
  }
  case table.notes(table) {
    [] -> with_caption
    notes ->
      with_caption
      <> "\n\nNotes:\n"
      <> {
        notes
        |> list.map(fn(note) { "- " <> escape(note) })
        |> string.join("\n")
      }
  }
}

fn render_row(row: Row) -> String {
  row.cells
  |> list.map(render_cell)
  |> markdown_row
}

fn markdown_row(values: List(String)) -> String {
  "| " <> string.join(values, " | ") <> " |"
}

fn render_cell(cell: Cell) -> String {
  cell |> render.cell_text |> escape
}

fn escape(value: String) -> String {
  value
  |> string.replace("\\", "\\\\")
  |> string.replace("|", "\\|")
  |> string.replace("\n", "<br>")
  |> string.replace("\r", "")
}
