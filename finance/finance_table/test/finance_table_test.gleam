import finance_core/currency
import finance_core/decimal
import finance_core/money
import finance_table
import finance_table/csv
import finance_table/json as table_json
import finance_table/markdown
import finance_table/table
import gleam/list
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

pub fn csv_quotes_delimiters_quotes_and_newlines_test() {
  let assert Ok(table) =
    table.new(
      caption: None,
      columns: [
        table.Column("note", "Research,note", table.TextColumn, table.Left),
      ],
      rows: [
        table.Row(None, [table.TextCell("said \"hello\"\nnext")]),
      ],
      notes: [],
    )

  csv.render(table)
  |> should.equal("\"Research,note\"\n\"said \"\"hello\"\"\nnext\"")
}

pub fn json_preserves_exact_semantic_values_test() {
  let value = parsed_decimal("9007199254740993.01")
  let assert Ok(table) =
    table.new(
      caption: None,
      columns: [
        table.Column("value", "Value", table.DecimalColumn, table.Right),
        table.Column("count", "Count", table.IntegerColumn, table.Right),
      ],
      rows: [
        table.Row(Some("row-1"), [
          table.DecimalCell(value),
          table.IntegerCell(9_007_199_254_740_991),
        ]),
      ],
      notes: [],
    )

  table_json.encode(table)
  |> should.equal(
    "{\"schema_version\":1,\"caption\":null,\"columns\":[{\"key\":\"value\",\"heading\":\"Value\",\"kind\":\"decimal\",\"alignment\":\"right\"},{\"key\":\"count\",\"heading\":\"Count\",\"kind\":\"integer\",\"alignment\":\"right\"}],\"rows\":[{\"key\":\"row-1\",\"cells\":[{\"kind\":\"decimal\",\"value\":\"9007199254740993.01\"},{\"kind\":\"integer\",\"value\":\"9007199254740991\"}]}],\"notes\":[]}",
  )
}

pub fn unsafe_javascript_integer_is_rejected_test() {
  let unsafe = increment(9_007_199_254_740_991)
  table.new(
    caption: None,
    columns: [
      table.Column("count", "Count", table.IntegerColumn, table.Right),
    ],
    rows: [table.Row(None, [table.IntegerCell(unsafe)])],
    notes: [],
  )
  |> should.equal(Error(table.UnsafeInteger(0, "count")))
}

pub fn row_truncation_is_pure_and_disclosed_test() {
  let assert Ok(table) =
    table.new(
      caption: None,
      columns: [table.Column("n", "N", table.IntegerColumn, table.Right)],
      rows: [
        table.Row(None, [table.IntegerCell(1)]),
        table.Row(None, [table.IntegerCell(2)]),
        table.Row(None, [table.IntegerCell(3)]),
      ],
      notes: [],
    )
  let assert Ok(#(truncated, omission)) = table.truncate_rows(table, 2)

  omission
  |> should.equal(table.Omission(1))
  truncated
  |> table.rows
  |> list.length
  |> should.equal(2)
  table
  |> table.rows
  |> list.length
  |> should.equal(3)
  table.truncate_rows(table, -1)
  |> should.equal(Error(table.InvalidRowLimit))
}

fn parsed_decimal(value: String) -> decimal.Decimal {
  let assert Ok(value) = decimal.parse(value)
  value
}

fn increment(value: Int) -> Int {
  value + 1
}
