import finance_core/decimal
import finance_core/source
import finance_core/time
import finance_quote
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt}
import gleam/result
import gleam/string

pub type Feed {
  Iex
  Sip
}

pub type Identity {
  Identity(company: String, symbol: String, cik: String, as_of_date: String)
}

pub type QuoteReceipt {
  QuoteReceipt(
    feed: Feed,
    provider_timestamp: String,
    retrieved_at_milliseconds: Int,
    bid_exchange: String,
    bid_price: String,
    bid_size: String,
    ask_exchange: String,
    ask_price: String,
    ask_size: String,
    condition_codes: List(String),
    tape: String,
    request_id: Option(String),
    entitlement: String,
    source_reference: String,
  )
}

pub type HistoryReceipt {
  HistoryReceipt(
    feed: Feed,
    start_date: String,
    end_date: String,
    bars: Int,
    pagination: String,
    calendar_completeness: String,
    source_reference: String,
  )
}

pub type FilingReceipt {
  FilingReceipt(
    accession: String,
    filing_date: String,
    report_date: String,
    form: String,
    primary_document: String,
    source_reference: String,
  )
}

pub type FundamentalReceipt {
  FundamentalReceipt(
    metric: String,
    value: String,
    canonical_decimal: String,
    unit: String,
    period_class: String,
    start_date: Option(String),
    end_date: String,
    tag: String,
    accession: String,
    form: String,
    filed_date: String,
    source_reference: String,
  )
}

pub type Citation {
  Citation(id: String, provider: String, reference: String, locator: String)
}

pub opaque type Brief {
  Brief(
    identity: Identity,
    quote: Option(QuoteReceipt),
    history: Option(HistoryReceipt),
    filings: List(FilingReceipt),
    fundamentals: List(FundamentalReceipt),
    missing_capabilities: List(String),
    citations: List(Citation),
  )
}

pub type ReportError {
  InvalidIdentity
  TooManyQuoteReceipts
  TooManyHistoryReceipts
  TooManyFilings
  TooManyFundamentals
  InvalidQuote
  InvalidQuoteSource
  InvalidHistory
  InvalidHistorySource
  InvalidFiling(index: Int)
  InvalidFilingSource(index: Int)
  InvalidFundamental(index: Int)
  InvalidFundamentalSource(index: Int)
  DuplicateFundamental(metric: String)
  InvalidMissingCapability
}

pub fn build(
  identity identity: Identity,
  quotes quotes: List(QuoteReceipt),
  histories histories: List(HistoryReceipt),
  filings filings: List(FilingReceipt),
  fundamentals fundamentals: List(FundamentalReceipt),
  missing_capabilities missing_capabilities: List(String),
) -> Result(Brief, ReportError) {
  use _ <- result.try(validate_identity(identity))
  use quote <- result.try(single_quote(quotes))
  use history <- result.try(single_history(histories))
  use _ <- result.try(case list.length(filings) <= 10 {
    True -> Ok(Nil)
    False -> Error(TooManyFilings)
  })
  use _ <- result.try(case list.length(fundamentals) <= 20 {
    True -> Ok(Nil)
    False -> Error(TooManyFundamentals)
  })
  use _ <- result.try(validate_quote(identity, quote))
  use _ <- result.try(validate_history(identity, history))
  use _ <- result.try(validate_filings(identity, filings, 0))
  use _ <- result.try(validate_fundamentals(identity, fundamentals, [], 0))
  use _ <- result.try(case list.all(missing_capabilities, valid_text) {
    True -> Ok(Nil)
    False -> Error(InvalidMissingCapability)
  })
  let citations =
    make_citations(identity, quote, history, filings, fundamentals)
  Ok(Brief(
    identity,
    quote,
    history,
    filings,
    fundamentals,
    missing_capabilities,
    citations,
  ))
}

pub fn render(value: Brief) -> String {
  let lines = [
    "# US company brief — "
      <> value.identity.company
      <> " ("
      <> value.identity.symbol
      <> ")",
    "",
    "Track: US | CIK: "
      <> value.identity.cik
      <> " | report as-of: "
      <> value.identity.as_of_date,
    "",
    "## Latest quote",
    render_quote(value.quote),
    "",
    "## Bounded price history",
    render_history(value.history),
    "",
    "## Selected SEC fundamentals",
    render_fundamentals(value.fundamentals),
    "",
    "## Recent SEC filings",
    render_filings(value.identity, value.filings),
    "",
    "## Missing capabilities and limitations",
    render_missing(value.missing_capabilities),
    "- Input receipts are caller-supplied and are not cryptographically authenticated by this compositor.",
    "- This is a deterministic source-fact brief, not investment advice or a model-generated thesis.",
    "",
    "## Evidence roots",
    value.citations |> list.map(render_citation) |> string.join("\n"),
  ]
  lines |> string.join("\n")
}

pub fn details(value: Brief) -> List(#(String, json.Json)) {
  [
    #("status", json.string("assembled")),
    #("reportType", json.string("us_company_source_fact_brief")),
    #("identity", identity_json(value.identity)),
    #("quote", optional_quote_json(value.quote)),
    #("history", optional_history_json(value.history)),
    #("fundamentals", json.array(value.fundamentals, fundamental_json)),
    #("filings", json.array(value.filings, filing_json)),
    #(
      "missingCapabilities",
      json.array(value.missing_capabilities, json.string),
    ),
    #("evidenceRoots", json.array(value.citations, citation_json)),
    #(
      "receiptIntegrity",
      json.string("caller_supplied_not_cryptographically_verified"),
    ),
    #("interpretation", json.string("not_generated")),
  ]
}

pub fn citations(value: Brief) -> List(Citation) {
  value.citations
}

fn validate_identity(value: Identity) -> Result(Nil, ReportError) {
  case
    valid_text(value.company),
    valid_symbol(value.symbol),
    valid_cik(value.cik),
    valid_date(value.as_of_date)
  {
    True, True, True, True -> Ok(Nil)
    _, _, _, _ -> Error(InvalidIdentity)
  }
}

fn single_quote(
  values: List(QuoteReceipt),
) -> Result(Option(QuoteReceipt), ReportError) {
  case values {
    [] -> Ok(None)
    [value] -> Ok(Some(value))
    _ -> Error(TooManyQuoteReceipts)
  }
}

fn single_history(
  values: List(HistoryReceipt),
) -> Result(Option(HistoryReceipt), ReportError) {
  case values {
    [] -> Ok(None)
    [value] -> Ok(Some(value))
    _ -> Error(TooManyHistoryReceipts)
  }
}

fn validate_quote(
  identity: Identity,
  value: Option(QuoteReceipt),
) -> Result(Nil, ReportError) {
  case value {
    None -> Ok(Nil)
    Some(value) -> {
      use bid_price <- result.try(
        finance_quote.exact(value.bid_price)
        |> result.map_error(fn(_) { InvalidQuote }),
      )
      use bid_size <- result.try(
        finance_quote.exact(value.bid_size)
        |> result.map_error(fn(_) { InvalidQuote }),
      )
      use ask_price <- result.try(
        finance_quote.exact(value.ask_price)
        |> result.map_error(fn(_) { InvalidQuote }),
      )
      use ask_size <- result.try(
        finance_quote.exact(value.ask_size)
        |> result.map_error(fn(_) { InvalidQuote }),
      )
      use _ <- result.try(
        finance_quote.side(value.bid_exchange, bid_price, bid_size)
        |> result.map_error(fn(_) { InvalidQuote }),
      )
      use _ <- result.try(
        finance_quote.side(value.ask_exchange, ask_price, ask_size)
        |> result.map_error(fn(_) { InvalidQuote }),
      )
      use _ <- result.try(
        case
          valid_text(value.provider_timestamp),
          value.retrieved_at_milliseconds >= 0,
          list.all(value.condition_codes, valid_code),
          valid_code(value.tape),
          optional_text(value.request_id),
          valid_text(value.entitlement)
        {
          True, True, True, True, True, True -> Ok(Nil)
          _, _, _, _, _, _ -> Error(InvalidQuote)
        },
      )
      case value.source_reference == quote_source(identity.symbol, value.feed) {
        True -> Ok(Nil)
        False -> Error(InvalidQuoteSource)
      }
    }
  }
}

fn validate_history(
  identity: Identity,
  value: Option(HistoryReceipt),
) -> Result(Nil, ReportError) {
  case value {
    None -> Ok(Nil)
    Some(value) -> {
      use _ <- result.try(
        case
          date_on_or_before(value.start_date, value.end_date),
          date_on_or_before(value.end_date, identity.as_of_date),
          value.bars >= 0 && value.bars <= 5000,
          valid_code(value.pagination),
          valid_code(value.calendar_completeness)
        {
          True, True, True, True, True -> Ok(Nil)
          _, _, _, _, _ -> Error(InvalidHistory)
        },
      )
      let feed_marker = "&feed=" <> feed_name(value.feed) <> "&"
      case
        string.starts_with(
          value.source_reference,
          "https://data.alpaca.markets/v2/stocks/bars?symbols="
            <> identity.symbol
            <> "&",
        ),
        string.contains(value.source_reference, feed_marker),
        string.contains(value.source_reference, "&adjustment=raw&"),
        safe_source(value.source_reference)
      {
        True, True, True, True -> Ok(Nil)
        _, _, _, _ -> Error(InvalidHistorySource)
      }
    }
  }
}

fn validate_filings(
  identity: Identity,
  values: List(FilingReceipt),
  index: Int,
) -> Result(Nil, ReportError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(
        case
          valid_accession(value.accession),
          date_on_or_before(value.filing_date, identity.as_of_date),
          value.report_date == ""
          || date_on_or_before(value.report_date, value.filing_date),
          valid_code(value.form),
          valid_document(value.primary_document)
        {
          True, True, True, True, True -> Ok(Nil)
          _, _, _, _, _ -> Error(InvalidFiling(index))
        },
      )
      use _ <- result.try(
        case value.source_reference == sec_submissions_source(identity.cik) {
          True -> Ok(Nil)
          False -> Error(InvalidFilingSource(index))
        },
      )
      validate_filings(identity, rest, index + 1)
    }
  }
}

fn validate_fundamentals(
  identity: Identity,
  values: List(FundamentalReceipt),
  seen_metrics: List(String),
  index: Int,
) -> Result(Nil, ReportError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(case list.contains(seen_metrics, value.metric) {
        True -> Error(DuplicateFundamental(value.metric))
        False -> Ok(Nil)
      })
      use _ <- result.try(
        case
          valid_code(value.metric),
          same_decimal(value.value, value.canonical_decimal),
          valid_code(value.unit),
          valid_code(value.period_class),
          optional_date_on_or_before(value.start_date, value.end_date),
          date_on_or_before(value.end_date, value.filed_date),
          valid_code(value.tag),
          valid_accession(value.accession),
          valid_code(value.form),
          date_on_or_before(value.filed_date, identity.as_of_date)
        {
          True, True, True, True, True, True, True, True, True, True -> Ok(Nil)
          _, _, _, _, _, _, _, _, _, _ -> Error(InvalidFundamental(index))
        },
      )
      use _ <- result.try(
        case value.source_reference == sec_facts_source(identity.cik) {
          True -> Ok(Nil)
          False -> Error(InvalidFundamentalSource(index))
        },
      )
      validate_fundamentals(
        identity,
        rest,
        [value.metric, ..seen_metrics],
        index + 1,
      )
    }
  }
}

fn make_citations(
  identity: Identity,
  quote: Option(QuoteReceipt),
  history: Option(HistoryReceipt),
  filings: List(FilingReceipt),
  fundamentals: List(FundamentalReceipt),
) -> List(Citation) {
  let quote_citations = case quote {
    Some(value) -> [
      Citation(
        "Q1",
        "Alpaca Market Data",
        value.source_reference,
        "latest " <> feed_name(value.feed) <> " best bid/ask",
      ),
    ]
    None -> []
  }
  let history_citations = case history {
    Some(value) -> [
      Citation(
        "H1",
        "Alpaca Market Data",
        value.source_reference,
        value.start_date <> " through " <> value.end_date,
      ),
    ]
    None -> []
  }
  let filing_citations =
    filings
    |> list.index_map(fn(value, index) {
      Citation(
        "S" <> int.to_string(index + 1),
        "SEC EDGAR",
        filing_document_source(identity.cik, value),
        value.form <> " accession " <> value.accession,
      )
    })
  let fundamental_citations =
    fundamentals
    |> list.index_map(fn(value, index) {
      Citation(
        "F" <> int.to_string(index + 1),
        "SEC EDGAR XBRL",
        value.source_reference,
        "us-gaap:" <> value.tag <> " accession " <> value.accession,
      )
    })
  [quote_citations, history_citations, filing_citations, fundamental_citations]
  |> list.flatten
}

fn render_quote(value: Option(QuoteReceipt)) -> String {
  case value {
    None -> "Unavailable — see missing capabilities."
    Some(value) ->
      "- "
      <> string.uppercase(feed_name(value.feed))
      <> " bid "
      <> value.bid_price
      <> " × "
      <> value.bid_size
      <> " ("
      <> value.bid_exchange
      <> "), ask "
      <> value.ask_price
      <> " × "
      <> value.ask_size
      <> " ("
      <> value.ask_exchange
      <> ") [Q1]\n- Provider time: "
      <> value.provider_timestamp
      <> "; entitlement: "
      <> value.entitlement
      <> "; freshness/session/size semantics remain as stated by the source receipt."
  }
}

fn render_history(value: Option(HistoryReceipt)) -> String {
  case value {
    None -> "Unavailable — see missing capabilities."
    Some(value) ->
      "- "
      <> int.to_string(value.bars)
      <> " raw daily bars from "
      <> value.start_date
      <> " through "
      <> value.end_date
      <> "; feed "
      <> feed_name(value.feed)
      <> "; pagination "
      <> value.pagination
      <> "; calendar assessment "
      <> value.calendar_completeness
      <> " [H1]"
  }
}

fn render_fundamentals(values: List(FundamentalReceipt)) -> String {
  case values {
    [] -> "Unavailable — no uniquely resolved SEC facts were supplied."
    _ ->
      [
        "| Metric | Exact value | Period | Filing | Source |",
        "| --- | ---: | --- | --- | --- |",
        ..values
        |> list.index_map(fn(value, index) {
          "| "
          <> value.metric
          <> " | "
          <> value.value
          <> " "
          <> value.unit
          <> " | "
          <> optional_start(value.start_date)
          <> value.end_date
          <> " ("
          <> value.period_class
          <> ") | "
          <> value.form
          <> " filed "
          <> value.filed_date
          <> " | [F"
          <> int.to_string(index + 1)
          <> "] |"
        })
      ]
      |> string.join("\n")
  }
}

fn render_filings(_identity: Identity, values: List(FilingReceipt)) -> String {
  case values {
    [] -> "Unavailable — no recent filing receipts were supplied."
    _ ->
      values
      |> list.index_map(fn(value, index) {
        "- "
        <> value.form
        <> " filed "
        <> value.filing_date
        <> "; report date "
        <> unknown_if_empty(value.report_date)
        <> "; accession "
        <> value.accession
        <> " [S"
        <> int.to_string(index + 1)
        <> "]"
      })
      |> string.join("\n")
  }
}

fn render_missing(values: List(String)) -> String {
  case values {
    [] -> "- No caller-declared capability gaps."
    _ -> values |> list.map(fn(value) { "- " <> value }) |> string.join("\n")
  }
}

fn render_citation(value: Citation) -> String {
  "- ["
  <> value.id
  <> "] "
  <> value.provider
  <> " — ["
  <> value.locator
  <> "]("
  <> value.reference
  <> ")"
}

fn identity_json(value: Identity) -> json.Json {
  json.object([
    #("company", json.string(value.company)),
    #("symbol", json.string(value.symbol)),
    #("cik", json.string(value.cik)),
    #("asOfDate", json.string(value.as_of_date)),
  ])
}

fn optional_quote_json(value: Option(QuoteReceipt)) -> json.Json {
  case value {
    None -> json.null()
    Some(value) -> quote_json(value)
  }
}

fn quote_json(value: QuoteReceipt) -> json.Json {
  json.object([
    #("feed", json.string(feed_name(value.feed))),
    #("providerTimestamp", json.string(value.provider_timestamp)),
    #("retrievedAtUnixMilliseconds", json.int(value.retrieved_at_milliseconds)),
    #(
      "bid",
      json.object([
        #("exchange", json.string(value.bid_exchange)),
        #("rawPrice", json.string(value.bid_price)),
        #("rawSize", json.string(value.bid_size)),
      ]),
    ),
    #(
      "ask",
      json.object([
        #("exchange", json.string(value.ask_exchange)),
        #("rawPrice", json.string(value.ask_price)),
        #("rawSize", json.string(value.ask_size)),
      ]),
    ),
    #("conditionCodes", json.array(value.condition_codes, json.string)),
    #("tape", json.string(value.tape)),
    #("requestId", json.nullable(value.request_id, json.string)),
    #("currency", json.string("USD")),
    #("sizeUnit", json.string("provider_reported_unverified")),
    #("freshness", json.string("unknown")),
    #("session", json.string("unknown")),
    #("entitlement", json.string(value.entitlement)),
    #("sourceReference", json.string(value.source_reference)),
  ])
}

fn optional_history_json(value: Option(HistoryReceipt)) -> json.Json {
  case value {
    None -> json.null()
    Some(value) -> history_json(value)
  }
}

fn history_json(value: HistoryReceipt) -> json.Json {
  json.object([
    #("feed", json.string(feed_name(value.feed))),
    #("startDate", json.string(value.start_date)),
    #("endDate", json.string(value.end_date)),
    #("bars", json.int(value.bars)),
    #("pagination", json.string(value.pagination)),
    #("calendarCompleteness", json.string(value.calendar_completeness)),
    #("sourceReference", json.string(value.source_reference)),
  ])
}

fn filing_json(value: FilingReceipt) -> json.Json {
  json.object([
    #("accession", json.string(value.accession)),
    #("filingDate", json.string(value.filing_date)),
    #("reportDate", json.string(value.report_date)),
    #("form", json.string(value.form)),
    #("primaryDocument", json.string(value.primary_document)),
    #("sourceReference", json.string(value.source_reference)),
  ])
}

fn fundamental_json(value: FundamentalReceipt) -> json.Json {
  json.object([
    #("metric", json.string(value.metric)),
    #("value", json.string(value.value)),
    #("canonicalDecimal", json.string(value.canonical_decimal)),
    #("unit", json.string(value.unit)),
    #("periodClass", json.string(value.period_class)),
    #("start", json.nullable(value.start_date, json.string)),
    #("end", json.string(value.end_date)),
    #("tag", json.string(value.tag)),
    #("accession", json.string(value.accession)),
    #("form", json.string(value.form)),
    #("filed", json.string(value.filed_date)),
    #("sourceReference", json.string(value.source_reference)),
  ])
}

fn citation_json(value: Citation) -> json.Json {
  json.object([
    #("id", json.string(value.id)),
    #("provider", json.string(value.provider)),
    #("reference", json.string(value.reference)),
    #("locator", json.string(value.locator)),
  ])
}

fn feed_name(value: Feed) -> String {
  case value {
    Iex -> "iex"
    Sip -> "sip"
  }
}

fn quote_source(symbol: String, feed: Feed) -> String {
  "https://data.alpaca.markets/v2/stocks/quotes/latest?symbols="
  <> symbol
  <> "&feed="
  <> feed_name(feed)
  <> "&currency=USD"
}

fn sec_submissions_source(cik: String) -> String {
  "https://data.sec.gov/submissions/CIK" <> cik <> ".json"
}

fn sec_facts_source(cik: String) -> String {
  "https://data.sec.gov/api/xbrl/companyfacts/CIK" <> cik <> ".json"
}

fn filing_document_source(cik: String, value: FilingReceipt) -> String {
  let assert Ok(cik_number) = int.parse(cik)
  "https://www.sec.gov/Archives/edgar/data/"
  <> int.to_string(cik_number)
  <> "/"
  <> string.replace(value.accession, "-", "")
  <> "/"
  <> value.primary_document
}

fn safe_source(value: String) -> Bool {
  case source.new("report-receipt", value, source.LicensedVendor) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn valid_symbol(value: String) -> Bool {
  value != ""
  && value == string.uppercase(value)
  && string.length(value) <= 20
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-", character)
  })
}

fn valid_cik(value: String) -> Bool {
  string.length(value) == 10
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
  && case int.parse(value) {
    Ok(number) -> number > 0
    Error(_) -> False
  }
}

fn valid_accession(value: String) -> Bool {
  value != ""
  && string.length(value) <= 40
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789-", character) })
}

fn valid_document(value: String) -> Bool {
  value != ""
  && string.length(value) <= 200
  && !string.contains(value, "/")
  && !string.contains(value, "\\")
  && !string.contains(value, "..")
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-",
      character,
    )
  })
}

fn valid_date(value: String) -> Bool {
  case string.split(value, "-") {
    [year, month, day] ->
      case
        string.length(year) == 4
        && string.length(month) == 2
        && string.length(day) == 2
      {
        False -> False
        True ->
          case int.parse(year), int.parse(month), int.parse(day) {
            Ok(year), Ok(month), Ok(day) ->
              time.date(year, month, day) |> result.is_ok
            _, _, _ -> False
          }
      }
    _ -> False
  }
}

fn date_on_or_before(value: String, upper: String) -> Bool {
  valid_date(value)
  && valid_date(upper)
  && case string.compare(value, upper) {
    Gt -> False
    _ -> True
  }
}

fn optional_date_on_or_before(value: Option(String), upper: String) -> Bool {
  case value {
    None -> valid_date(upper)
    Some(value) -> date_on_or_before(value, upper)
  }
}

fn same_decimal(left: String, right: String) -> Bool {
  case decimal.parse(left), decimal.parse(right) {
    Ok(left), Ok(right) -> decimal.compare(left, right) == Eq
    _, _ -> False
  }
}

fn optional_text(value: Option(String)) -> Bool {
  case value {
    None -> True
    Some(value) -> valid_text(value)
  }
}

fn valid_code(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn valid_text(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 500
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn optional_start(value: Option(String)) -> String {
  case value {
    None -> "instant at "
    Some(value) -> value <> " to "
  }
}

fn unknown_if_empty(value: String) -> String {
  case value {
    "" -> "unknown"
    value -> value
  }
}
