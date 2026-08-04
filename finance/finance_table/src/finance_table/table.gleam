import finance_core/decimal.{type Decimal}
import finance_core/money.{type Money}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type ColumnKind {
  TextColumn
  DecimalColumn
  MoneyColumn
  IntegerColumn
  BooleanColumn
}

pub type Alignment {
  Left
  Right
}

pub type MissingReason {
  Unavailable
  NotApplicable
  NotReported
  Suppressed
}

pub type Cell {
  TextCell(String)
  DecimalCell(Decimal)
  MoneyCell(Money)
  IntegerCell(Int)
  BooleanCell(Bool)
  MissingCell(MissingReason)
}

pub type Column {
  Column(key: String, heading: String, kind: ColumnKind, alignment: Alignment)
}

pub type Row {
  Row(key: Option(String), cells: List(Cell))
}

pub opaque type Table {
  Table(
    caption: Option(String),
    columns: List(Column),
    rows: List(Row),
    notes: List(String),
  )
}

pub type TableError {
  NoColumns
  EmptyColumnKey
  DuplicateColumnKey(key: String)
  RowWidth(row: Int, expected: Int, actual: Int)
  CellKindMismatch(
    row: Int,
    column: String,
    expected: ColumnKind,
    actual: ColumnKind,
  )
}

pub fn new(
  caption caption: Option(String),
  columns columns: List(Column),
  rows rows: List(Row),
  notes notes: List(String),
) -> Result(Table, TableError) {
  case validate_columns(columns) {
    Error(error) -> Error(error)
    Ok(Nil) ->
      case validate_rows(rows, columns, 0) {
        Error(error) -> Error(error)
        Ok(Nil) -> Ok(Table(caption, columns, rows, notes))
      }
  }
}

pub fn caption(table: Table) -> Option(String) {
  let Table(caption, _, _, _) = table
  caption
}

pub fn columns(table: Table) -> List(Column) {
  let Table(_, columns, _, _) = table
  columns
}

pub fn rows(table: Table) -> List(Row) {
  let Table(_, _, rows, _) = table
  rows
}

pub fn notes(table: Table) -> List(String) {
  let Table(_, _, _, notes) = table
  notes
}

pub fn cell_kind(cell: Cell) -> Option(ColumnKind) {
  case cell {
    TextCell(_) -> Some(TextColumn)
    DecimalCell(_) -> Some(DecimalColumn)
    MoneyCell(_) -> Some(MoneyColumn)
    IntegerCell(_) -> Some(IntegerColumn)
    BooleanCell(_) -> Some(BooleanColumn)
    MissingCell(_) -> None
  }
}

fn validate_columns(columns: List(Column)) -> Result(Nil, TableError) {
  case columns {
    [] -> Error(NoColumns)
    _ -> validate_column_keys(columns, [])
  }
}

fn validate_column_keys(
  columns: List(Column),
  seen: List(String),
) -> Result(Nil, TableError) {
  case columns {
    [] -> Ok(Nil)
    [Column(key: "", ..), ..] -> Error(EmptyColumnKey)
    [Column(key: key, ..), ..rest] ->
      case list.contains(seen, key) {
        True -> Error(DuplicateColumnKey(key))
        False -> validate_column_keys(rest, [key, ..seen])
      }
  }
}

fn validate_rows(
  rows: List(Row),
  columns: List(Column),
  index: Int,
) -> Result(Nil, TableError) {
  case rows {
    [] -> Ok(Nil)
    [Row(cells: cells, ..), ..rest] -> {
      let expected = list.length(columns)
      let actual = list.length(cells)
      case expected == actual {
        False -> Error(RowWidth(index, expected, actual))
        True ->
          case validate_cells(cells, columns, index) {
            Error(error) -> Error(error)
            Ok(Nil) -> validate_rows(rest, columns, index + 1)
          }
      }
    }
  }
}

fn validate_cells(
  cells: List(Cell),
  columns: List(Column),
  row: Int,
) -> Result(Nil, TableError) {
  case cells, columns {
    [], [] -> Ok(Nil)
    [cell, ..rest_cells], [column, ..rest_columns] ->
      case cell_kind(cell) {
        None -> validate_cells(rest_cells, rest_columns, row)
        Some(kind) if kind == column.kind ->
          validate_cells(rest_cells, rest_columns, row)
        Some(kind) ->
          Error(CellKindMismatch(row, column.key, column.kind, kind))
      }
    _, _ -> Ok(Nil)
  }
}
