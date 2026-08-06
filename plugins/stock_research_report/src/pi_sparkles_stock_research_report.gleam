import finance_core/time
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pi
import pi/context
import pi/schema
import pi/tool
import pi/ui
import pi_sparkles_stock_research_report/guide
import pi_sparkles_stock_research_report/report

pub type Input {
  Input(
    identity: report.Identity,
    quotes: List(report.QuoteReceipt),
    histories: List(report.HistoryReceipt),
    filings: List(report.FilingReceipt),
    fundamentals: List(report.FundamentalReceipt),
    missing_capabilities: List(String),
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  pi.register_command(
    api,
    "us-research",
    "Queue a source-only US company-brief workflow",
    fn(args, ctx) {
      let request = string.trim(args)
      case request == "" {
        True ->
          notify(
            ctx,
            "Usage: /us-research <company, symbol, CIK, period>",
            ui.Error,
          )
        False -> {
          pi.send_user_message(api, guide.workflow(request), pi.QueueFollowUp)
          notify(ctx, "Queued a bounded US cited-research workflow", ui.Info)
        }
      }
      promise.resolve(Nil)
    },
  )

  tool.register(
    api,
    "us_company_brief",
    "US cited company brief",
    "Validate and deterministically assemble exact receipts from us_stock_quote, us_stock_ohlcv, sec_company_submissions, and uniquely resolved stock_fundamental_period results into a source-linked US brief",
    "Compose existing finance receipts only after gathering them; preserve exact values and state missing or ambiguous capabilities instead of adding model facts",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case
        report.build(
          input.identity,
          input.quotes,
          input.histories,
          input.filings,
          input.fundamentals,
          input.missing_capabilities,
        )
      {
        Error(error) ->
          tool.reject(
            "US company brief rejected an incoherent receipt set: "
            <> string.inspect(error),
          )
        Ok(brief) ->
          tool.text_result(
            report.render(brief),
            json.object(list.append(
              track_json.result_fields(result_context()),
              list.append(report.details(brief), [
                #(
                  "inactiveDependencyTools",
                  json.array(
                    inactive_dependencies(pi.get_active_tools(api)),
                    json.string,
                  ),
                ),
              ]),
            )),
          )
          |> promise.resolve
      }
    },
  )
  promise.resolve(Nil)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("company", bounded_string(1, 200)),
    schema.Required("symbol", bounded_string(1, 20)),
    schema.Required("cik", bounded_string(10, 10)),
    schema.Required("asOfDate", bounded_string(10, 10)),
    schema.Required(
      "quotes",
      schema.array(quote_schema()) |> schema.with_array_length(0, 1),
    ),
    schema.Required(
      "histories",
      schema.array(history_schema()) |> schema.with_array_length(0, 1),
    ),
    schema.Required(
      "filings",
      schema.array(filing_schema()) |> schema.with_array_length(0, 10),
    ),
    schema.Required(
      "fundamentals",
      schema.array(fundamental_schema()) |> schema.with_array_length(0, 20),
    ),
    schema.Required(
      "missingCapabilities",
      schema.array(bounded_string(1, 500)) |> schema.with_array_length(0, 20),
    ),
  ])
}

fn quote_schema() -> schema.Schema {
  schema.object([
    schema.Required("feed", schema.string_enum(["iex", "sip"])),
    schema.Required("providerTimestamp", bounded_string(1, 100)),
    schema.Required("retrievedAtUnixMilliseconds", schema.integer()),
    schema.Required("bidExchange", bounded_string(1, 40)),
    schema.Required("bidPrice", bounded_string(1, 100)),
    schema.Required("bidSize", bounded_string(1, 100)),
    schema.Required("askExchange", bounded_string(1, 40)),
    schema.Required("askPrice", bounded_string(1, 100)),
    schema.Required("askSize", bounded_string(1, 100)),
    schema.Required(
      "conditionCodes",
      schema.array(bounded_string(1, 40)) |> schema.with_array_length(0, 40),
    ),
    schema.Required("tape", bounded_string(1, 40)),
    schema.Optional("requestId", schema.nullable(bounded_string(1, 200))),
    schema.Required("entitlement", bounded_string(1, 200)),
    schema.Required("sourceReference", bounded_string(1, 1000)),
  ])
}

fn history_schema() -> schema.Schema {
  schema.object([
    schema.Required("feed", schema.string_enum(["iex", "sip"])),
    schema.Required("startDate", bounded_string(10, 10)),
    schema.Required("endDate", bounded_string(10, 10)),
    schema.Required(
      "bars",
      schema.integer() |> schema.with_number_range(0.0, 5000.0),
    ),
    schema.Required("pagination", bounded_string(1, 100)),
    schema.Required("calendarCompleteness", bounded_string(1, 200)),
    schema.Required("sourceReference", bounded_string(1, 2000)),
  ])
}

fn filing_schema() -> schema.Schema {
  schema.object([
    schema.Required("accession", bounded_string(1, 40)),
    schema.Required("filingDate", bounded_string(10, 10)),
    schema.Required("reportDate", bounded_string(0, 10)),
    schema.Required("form", bounded_string(1, 20)),
    schema.Required("primaryDocument", bounded_string(1, 200)),
    schema.Required("sourceReference", bounded_string(1, 1000)),
  ])
}

fn fundamental_schema() -> schema.Schema {
  schema.object([
    schema.Required("metric", bounded_string(1, 100)),
    schema.Required("value", bounded_string(1, 200)),
    schema.Required("canonicalDecimal", bounded_string(1, 200)),
    schema.Required("unit", bounded_string(1, 100)),
    schema.Required("periodClass", bounded_string(1, 100)),
    schema.Optional("start", schema.nullable(bounded_string(10, 10))),
    schema.Required("end", bounded_string(10, 10)),
    schema.Required("tag", bounded_string(1, 200)),
    schema.Required("accession", bounded_string(1, 40)),
    schema.Required("form", bounded_string(1, 20)),
    schema.Required("filed", bounded_string(10, 10)),
    schema.Required("sourceReference", bounded_string(1, 1000)),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use company <- decode.field("company", decode.string)
  use symbol <- decode.field("symbol", decode.string)
  use cik <- decode.field("cik", decode.string)
  use as_of_date <- decode.field("asOfDate", decode.string)
  use quotes <- decode.field("quotes", decode.list(of: quote_decoder()))
  use histories <- decode.field("histories", decode.list(of: history_decoder()))
  use filings <- decode.field("filings", decode.list(of: filing_decoder()))
  use fundamentals <- decode.field(
    "fundamentals",
    decode.list(of: fundamental_decoder()),
  )
  use missing_capabilities <- decode.field(
    "missingCapabilities",
    decode.list(of: decode.string),
  )
  decode.success(Input(
    report.Identity(company, symbol, cik, as_of_date),
    quotes,
    histories,
    filings,
    fundamentals,
    missing_capabilities,
  ))
}

fn quote_decoder() -> decode.Decoder(report.QuoteReceipt) {
  use feed <- decode.field("feed", feed_decoder())
  use provider_timestamp <- decode.field("providerTimestamp", decode.string)
  use retrieved <- decode.field("retrievedAtUnixMilliseconds", decode.int)
  use bid_exchange <- decode.field("bidExchange", decode.string)
  use bid_price <- decode.field("bidPrice", decode.string)
  use bid_size <- decode.field("bidSize", decode.string)
  use ask_exchange <- decode.field("askExchange", decode.string)
  use ask_price <- decode.field("askPrice", decode.string)
  use ask_size <- decode.field("askSize", decode.string)
  use conditions <- decode.field(
    "conditionCodes",
    decode.list(of: decode.string),
  )
  use tape <- decode.field("tape", decode.string)
  use request_id <- optional_string("requestId")
  use entitlement <- decode.field("entitlement", decode.string)
  use reference <- decode.field("sourceReference", decode.string)
  decode.success(report.QuoteReceipt(
    feed,
    provider_timestamp,
    retrieved,
    bid_exchange,
    bid_price,
    bid_size,
    ask_exchange,
    ask_price,
    ask_size,
    conditions,
    tape,
    request_id,
    entitlement,
    reference,
  ))
}

fn history_decoder() -> decode.Decoder(report.HistoryReceipt) {
  use feed <- decode.field("feed", feed_decoder())
  use start <- decode.field("startDate", decode.string)
  use end <- decode.field("endDate", decode.string)
  use bars <- decode.field("bars", decode.int)
  use pagination <- decode.field("pagination", decode.string)
  use calendar <- decode.field("calendarCompleteness", decode.string)
  use reference <- decode.field("sourceReference", decode.string)
  decode.success(report.HistoryReceipt(
    feed,
    start,
    end,
    bars,
    pagination,
    calendar,
    reference,
  ))
}

fn filing_decoder() -> decode.Decoder(report.FilingReceipt) {
  use accession <- decode.field("accession", decode.string)
  use filing_date <- decode.field("filingDate", decode.string)
  use report_date <- decode.field("reportDate", decode.string)
  use form <- decode.field("form", decode.string)
  use primary_document <- decode.field("primaryDocument", decode.string)
  use reference <- decode.field("sourceReference", decode.string)
  decode.success(report.FilingReceipt(
    accession,
    filing_date,
    report_date,
    form,
    primary_document,
    reference,
  ))
}

fn fundamental_decoder() -> decode.Decoder(report.FundamentalReceipt) {
  use metric <- decode.field("metric", decode.string)
  use value <- decode.field("value", decode.string)
  use canonical <- decode.field("canonicalDecimal", decode.string)
  use unit <- decode.field("unit", decode.string)
  use period <- decode.field("periodClass", decode.string)
  use start <- optional_string("start")
  use end <- decode.field("end", decode.string)
  use tag <- decode.field("tag", decode.string)
  use accession <- decode.field("accession", decode.string)
  use form <- decode.field("form", decode.string)
  use filed <- decode.field("filed", decode.string)
  use reference <- decode.field("sourceReference", decode.string)
  decode.success(report.FundamentalReceipt(
    metric,
    value,
    canonical,
    unit,
    period,
    start,
    end,
    tag,
    accession,
    form,
    filed,
    reference,
  ))
}

fn feed_decoder() -> decode.Decoder(report.Feed) {
  use value <- decode.then(decode.string)
  case value {
    "iex" -> decode.success(report.Iex)
    "sip" -> decode.success(report.Sip)
    _ -> decode.failure(report.Iex, "explicit iex or sip feed")
  }
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn result_context() -> track_context.Context {
  let assert Ok(zone) = time.timezone("America/New_York")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Us,
      market_scope: "us_company_brief",
      venue_mic: None,
      board: None,
      timezone: Some(zone),
      source_language: "en-US",
      providers: ["composed_receipts"],
      entitlement: "inherits_supplied_receipts",
      limitations: [
        "receipt_integrity_not_cryptographically_verified",
        "no_provider_requests_in_report_compositor",
        "no_ambiguous_fundamental_selection",
        "no_model_generated_facts_or_investment_thesis",
      ],
    )
  value
}

fn inactive_dependencies(active_tools: List(String)) -> List(String) {
  [
    "us_stock_quote",
    "us_stock_ohlcv",
    "sec_company_submissions",
    "stock_fundamental_period",
  ]
  |> list.filter(fn(name) { !list.contains(active_tools, name) })
}

fn notify(
  ctx: pi.CommandContext,
  message: String,
  level: ui.Notification,
) -> Nil {
  case context.has_ui(ctx) {
    True -> ui.notify(context.ui(ctx), message, level)
    False -> Nil
  }
}
