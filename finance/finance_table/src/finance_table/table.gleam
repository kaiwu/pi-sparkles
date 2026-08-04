import finance_core/currency
import finance_core/decimal.{type Decimal}
import finance_core/market.{type Unit}
import finance_core/money.{type Money}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

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
  AnnotatedCell(value: Cell, annotations: List(Annotation))
}

pub type Annotation {
  Annotation(label: String, evidence_id: Option(String))
}

pub type Column {
  Column(
    key: String,
    heading: String,
    kind: ColumnKind,
    alignment: Alignment,
    unit: Option(Unit),
  )
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

pub type Budget {
  Budget(
    maximum_rows: Int,
    maximum_columns: Int,
    maximum_cells: Int,
    maximum_text_characters: Int,
  )
}

pub type OmissionSummary {
  OmissionSummary(rows: Int, columns: Int, cells: Int, text_characters: Int)
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
  InvalidBudget
  IncompatibleColumnUnit(column: String)
  CurrencyUnitMismatch(row: Int, column: String)
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

pub fn apply_budget(
  table: Table,
  budget: Budget,
) -> Result(#(Table, OmissionSummary), TableError) {
  let Budget(maximum_rows, maximum_columns, maximum_cells, maximum_text) =
    budget
  case
    maximum_rows >= 0
    && maximum_columns > 0
    && maximum_cells >= 0
    && maximum_text >= 0
  {
    False -> Error(InvalidBudget)
    True -> {
      let Table(caption, columns, rows, notes) = table
      let kept_columns = list.take(columns, maximum_columns)
      let column_count = list.length(kept_columns)
      let cell_limited_rows = case column_count == 0 {
        True -> 0
        False -> maximum_cells / column_count
      }
      let row_limit = int.min(maximum_rows, cell_limited_rows)
      let kept_rows =
        rows
        |> list.take(row_limit)
        |> list.map(fn(row) {
          Row(
            ..row,
            cells: row.cells
              |> list.take(column_count)
              |> list.map(fn(cell) { truncate_text(cell, maximum_text).0 }),
          )
        })
      let omitted_characters =
        rows
        |> list.take(row_limit)
        |> list.flat_map(fn(row) { list.take(row.cells, column_count) })
        |> list.fold(0, fn(total, cell) {
          total + truncate_text(cell, maximum_text).1
        })
      let omitted_rows = int.max(list.length(rows) - row_limit, 0)
      let omitted_columns = int.max(list.length(columns) - column_count, 0)
      let original_cells = list.length(rows) * list.length(columns)
      let retained_cells = list.length(kept_rows) * column_count
      Ok(#(
        Table(caption, kept_columns, kept_rows, notes),
        OmissionSummary(
          omitted_rows,
          omitted_columns,
          original_cells - retained_cells,
          omitted_characters,
        ),
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
    AnnotatedCell(value, _) -> cell_kind(value)
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
    [Column(key: key, kind: kind, unit: unit, ..), ..rest] ->
      case list.contains(seen, key) {
        True -> Error(DuplicateColumnKey(key))
        False ->
          case compatible_unit(kind, unit) {
            False -> Error(IncompatibleColumnUnit(key))
            True -> validate_column_keys(rest, [key, ..seen])
          }
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
      let unsafe_integer = unsafe_integer(cell)
      case unsafe_integer, cell_kind(cell) {
        True, _ -> Error(UnsafeInteger(row, column.key))
        False, None -> validate_cells(rest_cells, rest_columns, row)
        False, Some(kind) if kind == column.kind ->
          case compatible_cell_unit(cell, column.unit) {
            True -> validate_cells(rest_cells, rest_columns, row)
            False -> Error(CurrencyUnitMismatch(row, column.key))
          }
        False, Some(kind) ->
          Error(CellKindMismatch(row, column.key, column.kind, kind))
      }
    }
    _, _ -> Ok(Nil)
  }
}

fn compatible_unit(kind: ColumnKind, unit: Option(Unit)) -> Bool {
  case kind, unit {
    TextColumn, Some(_) | BooleanColumn, Some(_) -> False
    MoneyColumn, Some(market.Currency(_))
    | MoneyColumn, Some(market.CurrencyPerShare(_))
    | MoneyColumn, None
    -> True
    MoneyColumn, Some(_) -> False
    _, _ -> True
  }
}

fn compatible_cell_unit(cell: Cell, unit: Option(Unit)) -> Bool {
  case cell, unit {
    AnnotatedCell(value, _), unit -> compatible_cell_unit(value, unit)
    MoneyCell(value), Some(market.Currency(expected))
    | MoneyCell(value), Some(market.CurrencyPerShare(expected))
    -> currency.code(value.currency) == currency.code(expected)
    _, _ -> True
  }
}

fn unsafe_integer(cell: Cell) -> Bool {
  case cell {
    IntegerCell(value) ->
      value < -9_007_199_254_740_991 || value > 9_007_199_254_740_991
    AnnotatedCell(value, _) -> unsafe_integer(value)
    _ -> False
  }
}

fn truncate_text(cell: Cell, maximum: Int) -> #(Cell, Int) {
  case cell {
    TextCell(value) -> {
      let characters = value |> string.to_graphemes |> list.length
      case characters > maximum {
        True -> #(
          TextCell(
            value |> string.to_graphemes |> list.take(maximum) |> string.concat,
          ),
          characters - maximum,
        )
        False -> #(cell, 0)
      }
    }
    AnnotatedCell(value, annotations) -> {
      let #(truncated, omitted) = truncate_text(value, maximum)
      #(AnnotatedCell(truncated, annotations), omitted)
    }
    _ -> #(cell, 0)
  }
}
