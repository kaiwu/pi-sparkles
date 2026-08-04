import finance_core/decimal
import finance_core/money
import finance_table/table.{type Cell}
import gleam/int

pub fn cell_text(cell: Cell) -> String {
  case cell {
    table.TextCell(value) -> value
    table.DecimalCell(value) -> decimal.to_string(value)
    table.MoneyCell(value) -> money.to_string(value)
    table.IntegerCell(value) -> int.to_string(value)
    table.BooleanCell(True) -> "true"
    table.BooleanCell(False) -> "false"
    table.MissingCell(table.Unavailable) -> "—"
    table.MissingCell(table.NotApplicable) -> "N/A"
    table.MissingCell(table.NotReported) -> "not reported"
    table.MissingCell(table.Suppressed) -> "suppressed"
  }
}
