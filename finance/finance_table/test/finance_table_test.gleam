import finance_core/currency
import finance_core/decimal
import finance_core/money
import finance_table
import finance_table/markdown
import finance_table/table
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_implementing_test() {
  finance_table.status()
  |> should.equal(finance_table.Implementing)
}

pub fn validated_table_renders_deterministically_test() {
  let assert Ok(price) = decimal.parse("123.4500")
  let assert Ok(usd) = currency.from_code("USD")
  let assert Ok(table) =
    table.new(
      caption: Some("Quote | snapshot"),
      columns: [
        table.Column("symbol", "Symbol", table.TextColumn, table.Left),
        table.Column("price", "Price", table.MoneyColumn, table.Right),
        table.Column("volume", "Volume", table.IntegerColumn, table.Right),
      ],
      rows: [
        table.Row(None, [
          table.TextCell("AAPL"),
          table.MoneyCell(money.new(price, usd)),
          table.IntegerCell(42),
        ]),
      ],
      notes: ["Synthetic\nfixture"],
    )

  let rendered = markdown.render(table)

  rendered
  |> should.equal(
    "**Quote \\| snapshot**\n\n| Symbol | Price | Volume |\n| :--- | ---: | ---: |\n| AAPL | USD 123.45 | 42 |\n\nNotes:\n- Synthetic<br>fixture",
  )
  markdown.render(table)
  |> should.equal(rendered)
}

pub fn row_width_is_validated_test() {
  table.new(
    caption: None,
    columns: [table.Column("symbol", "Symbol", table.TextColumn, table.Left)],
    rows: [table.Row(None, [])],
    notes: [],
  )
  |> should.equal(Error(table.RowWidth(0, 1, 0)))
}

pub fn cell_kind_mismatch_is_not_stringified_test() {
  table.new(
    caption: None,
    columns: [table.Column("price", "Price", table.DecimalColumn, table.Right)],
    rows: [table.Row(None, [table.TextCell("12.3")])],
    notes: [],
  )
  |> should.equal(
    Error(table.CellKindMismatch(
      0,
      "price",
      table.DecimalColumn,
      table.TextColumn,
    )),
  )
}

pub fn missing_cell_is_valid_for_any_column_test() {
  let assert Ok(table) =
    table.new(
      caption: None,
      columns: [
        table.Column("price", "Price", table.DecimalColumn, table.Right),
      ],
      rows: [table.Row(None, [table.MissingCell(table.NotReported)])],
      notes: [],
    )

  markdown.render(table)
  |> should.equal("| Price |\n| ---: |\n| not reported |")
}
