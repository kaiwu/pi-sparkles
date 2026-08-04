import finance_core/decimal.{type Decimal}
import finance_core/money.{type Money}
import gleam/int
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

pub type Omission {
  Omission(rows: Int)
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
  UnsafeInteger(row: Int, column: String)
  InvalidRowLimit
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

pub fn truncate_rows(
  table: Table,
  maximum_rows: Int,
) -> Result(#(Table, Omission), TableError) {
  case maximum_rows < 0 {
    True -> Error(InvalidRowLimit)
    False -> {
      let Table(caption, columns, rows, notes) = table
      let omitted = int.max(list.length(rows) - maximum_rows, 0)
      Ok(#(
        Table(caption, columns, list.take(rows, maximum_rows), notes),
        Omission(omitted),
      ))
    }
  }
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
    [cell, ..rest_cells], [column, ..rest_columns] -> {
      let unsafe_integer = case cell {
        IntegerCell(value) ->
          value < -9_007_199_254_740_991 || value > 9_007_199_254_740_991
        _ -> False
      }
      case unsafe_integer, cell_kind(cell) {
        True, _ -> Error(UnsafeInteger(row, column.key))
        False, None -> validate_cells(rest_cells, rest_columns, row)
        False, Some(kind) if kind == column.kind ->
          validate_cells(rest_cells, rest_columns, row)
        False, Some(kind) ->
          Error(CellKindMismatch(row, column.key, column.kind, kind))
      }
    }
    _, _ -> Ok(Nil)
  }
}
