import finance_sec.{type Cik}
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/order
import gleam/result
import gleam/string

pub type Company {
  Company(cik: Cik, ticker: String, title: String)
}

pub type Filing {
  Filing(
    accession: String,
    filing_date: String,
    report_date: String,
    form: String,
    primary_document: String,
  )
}

pub type Submissions {
  Submissions(
    cik: Cik,
    name: String,
    tickers: List(String),
    exchanges: List(String),
    recent: List(Filing),
  )
}

pub type ResponseError {
  InvalidColumns
}

type RecentColumns {
  RecentColumns(
    accessions: List(String),
    filing_dates: List(String),
    report_dates: List(String),
    forms: List(String),
    documents: List(String),
  )
}

pub fn decode_companies(
  body: String,
) -> Result(List(Company), json.DecodeError) {
  use values <- result.try(json.parse(
    body,
    decode.dict(decode.string, company_decoder()),
  ))
  Ok(
    values
    |> dict.values
    |> list.sort(by: compare_company),
  )
}

pub fn decode_submissions(
  body: String,
) -> Result(Submissions, json.DecodeError) {
  json.parse(body, submissions_decoder())
}

fn company_decoder() -> decode.Decoder(Company) {
  use cik <- decode.field("cik_str", cik_decoder())
  use ticker <- decode.field("ticker", decode.string)
  use title <- decode.field("title", decode.string)
  decode.success(Company(cik:, ticker:, title:))
}

fn submissions_decoder() -> decode.Decoder(Submissions) {
  use cik <- decode.field("cik", cik_decoder())
  use name <- decode.field("name", decode.string)
  use tickers <- decode.field("tickers", decode.list(of: decode.string))
  use exchanges <- decode.field("exchanges", decode.list(of: decode.string))
  use columns <- decode.field("filings", filings_decoder())
  case
    zip_filings(
      columns.accessions,
      columns.filing_dates,
      columns.report_dates,
      columns.forms,
      columns.documents,
      [],
    )
  {
    Error(_) ->
      decode.failure(
        Submissions(cik, name, tickers, exchanges, []),
        "equal SEC recent filing columns",
      )
    Ok(recent) ->
      decode.success(Submissions(cik:, name:, tickers:, exchanges:, recent:))
  }
}

fn filings_decoder() -> decode.Decoder(RecentColumns) {
  decode.at(["recent"], recent_columns_decoder())
}

fn recent_columns_decoder() -> decode.Decoder(RecentColumns) {
  use accessions <- decode.field(
    "accessionNumber",
    decode.list(of: decode.string),
  )
  use filing_dates <- decode.field("filingDate", decode.list(of: decode.string))
  use report_dates <- decode.field("reportDate", decode.list(of: decode.string))
  use forms <- decode.field("form", decode.list(of: decode.string))
  use documents <- decode.field(
    "primaryDocument",
    decode.list(of: decode.string),
  )
  decode.success(RecentColumns(
    accessions,
    filing_dates,
    report_dates,
    forms,
    documents,
  ))
}

fn cik_decoder() -> decode.Decoder(Cik) {
  decode.int
  |> decode.then(fn(value) {
    case finance_sec.cik_from_int(value) {
      Ok(cik) -> decode.success(cik)
      Error(_) -> {
        let assert Ok(placeholder) = finance_sec.cik_from_int(0)
        decode.failure(placeholder, "valid SEC CIK")
      }
    }
  })
}

fn compare_company(left: Company, right: Company) -> order.Order {
  string.compare(left.ticker, right.ticker)
}

fn zip_filings(
  a: List(String),
  d: List(String),
  r: List(String),
  f: List(String),
  p: List(String),
  out: List(Filing),
) -> Result(List(Filing), ResponseError) {
  case a, d, r, f, p {
    [], [], [], [], [] -> Ok(list.reverse(out))
    [a, ..as_], [d, ..ds], [r, ..rs], [f, ..fs], [p, ..ps] ->
      zip_filings(as_, ds, rs, fs, ps, [Filing(a, d, r, f, p), ..out])
    _, _, _, _, _ -> Error(InvalidColumns)
  }
}
