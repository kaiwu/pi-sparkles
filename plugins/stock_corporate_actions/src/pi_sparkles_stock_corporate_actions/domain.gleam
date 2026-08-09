import finance_core/time.{type Date, type Instant}
import finance_market_alpaca/corporate_actions
import finance_provenance/identity.{type Sha256}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Lt}
import gleam/result
import gleam/string

pub type Venue {
  Xnys
  Xnas
}

pub type Plan {
  Plan(venue: Venue, query: corporate_actions.Query)
}

pub type Pagination {
  Complete
  TruncatedByPageBudget(maximum_pages: Int)
  TruncatedByActionBudget(maximum_actions: Int)
}

pub type SourcePage {
  SourcePage(
    sequence: Int,
    request_id: Option(String),
    response_byte_length: Int,
    content_sha256: Sha256,
    actions: corporate_actions.Page,
  )
}

pub type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  WrongTrack(received: String)
  WrongVenue(received: String)
  InvalidStartDate
  InvalidEndDate
  InvalidActionType(received: String)
  InvalidDataQuality(received: String)
  InvalidQuery(corporate_actions.QueryError)
  NoSourcePages
  InvalidPageSequence
  InvalidPagination
  OutOfOrderPages
  TooManyActions(maximum: Int, received: Int)
  UnexpectedActionType(corporate_actions.ActionType)
  IdentityMismatch(action_type: String, id: String)
}

pub fn plan(
  track: String,
  venue: String,
  symbol: String,
  cusip: String,
  start_date: String,
  end_date: String,
  types: List(String),
  data_quality: String,
  page_size: Int,
  maximum_pages: Int,
  maximum_actions: Int,
) -> Result(Plan, Error) {
  use Nil <- result.try(case track {
    "us" -> Ok(Nil)
    value -> Error(WrongTrack(value))
  })
  use venue_value <- result.try(case venue {
    "XNYS" -> Ok(Xnys)
    "XNAS" -> Ok(Xnas)
    value -> Error(WrongVenue(value))
  })
  use start <- result.try(
    parse_date(start_date) |> result.map_error(fn(_) { InvalidStartDate }),
  )
  use end <- result.try(
    parse_date(end_date) |> result.map_error(fn(_) { InvalidEndDate }),
  )
  use action_types <- result.try(parse_action_types(types, []))
  use quality <- result.try(case data_quality {
    "complete" -> Ok(corporate_actions.Complete)
    "all" -> Ok(corporate_actions.All)
    value -> Error(InvalidDataQuality(value))
  })
  corporate_actions.query(
    symbol,
    cusip,
    start,
    end,
    action_types,
    quality,
    page_size,
    maximum_pages,
    maximum_actions,
  )
  |> result.map(fn(query) { Plan(venue_value, query) })
  |> result.map_error(InvalidQuery)
}

pub fn run(
  plan: Plan,
  pages: List(SourcePage),
  pagination: Pagination,
  retrieved_at: Instant,
) -> Result(Output, Error) {
  use Nil <- result.try(validate_page_sequence(pages, 1))
  let total =
    pages
    |> list.fold(from: 0, with: fn(total, page) {
      total
      + list.length(page.actions.cash_dividends)
      + list.length(page.actions.stock_dividends)
      + list.length(page.actions.forward_splits)
      + list.length(page.actions.reverse_splits)
      + list.length(page.actions.name_changes)
    })
  use Nil <- result.try(case total <= plan.query.maximum_actions {
    True -> Ok(Nil)
    False -> Error(TooManyActions(plan.query.maximum_actions, total))
  })
  use Nil <- result.try(validate_pages(pages, plan))
  use Nil <- result.try(validate_page_order(pages, None))
  use Nil <- result.try(validate_pagination(
    pages,
    pagination,
    total,
    plan.query,
  ))
  let status = pagination_name(pagination)
  Ok(Output(
    "Alpaca US corporate actions for "
      <> plan.query.symbol
      <> " / "
      <> plan.query.cusip
      <> " at caller-declared "
      <> venue_name(plan.venue)
      <> ": "
      <> int.to_string(total)
      <> " exact source rows across "
      <> int.to_string(list.length(pages))
      <> " page(s), pagination "
      <> status
      <> ". No venue authentication, price adjustment, or economic-impact conclusion is inferred.",
    json.object([
      #("schema", json.string("pi-sparkles/stock-corporate-actions-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("corporate_actions")),
      #("track", json.string("us")),
      #("venue", json.string(venue_name(plan.venue))),
      #("venueEvidence", json.string("caller_declared_not_provider_verified")),
      #(
        "query",
        json.object([
          #("symbol", json.string(plan.query.symbol)),
          #("cusip", json.string(plan.query.cusip)),
          #("startDate", json.string(date_text(plan.query.start_date))),
          #("endDate", json.string(date_text(plan.query.end_date))),
          #("dateAxis", json.string("alpaca_process_date_inclusive")),
          #(
            "types",
            json.array(plan.query.types, fn(value) {
              value |> corporate_actions.action_type_name |> json.string
            }),
          ),
          #(
            "dataQuality",
            plan.query.data_quality
              |> corporate_actions.data_quality_name
              |> json.string,
          ),
          #("region", json.string("us")),
          #("sort", json.string("asc")),
          #("pageSize", json.int(plan.query.page_size)),
          #("maximumPages", json.int(plan.query.maximum_pages)),
          #("maximumActions", json.int(plan.query.maximum_actions)),
        ]),
      ),
      #("actionCount", json.int(total)),
      #("pageCount", json.int(list.length(pages))),
      #("pagination", pagination_json(pages, pagination)),
      #("pages", json.array(pages, fn(page) { page_json(page, plan) })),
      #(
        "source",
        json.object([
          #("provider", json.string("Alpaca Market Data")),
          #("kind", json.string("provider")),
          #(
            "reference",
            json.string("https://data.alpaca.markets/v1/corporate-actions"),
          ),
          #(
            "retrievedAtUnixMs",
            retrieved_at
              |> time.unix_milliseconds
              |> int.to_string
              |> json.string,
          ),
          #("authentication", json.string("alpaca_api_credentials")),
          #(
            "receiptState",
            json.string(
              "sha256_page_content_bound_not_provider_signature_or_origin_authentication",
            ),
          ),
        ]),
      ),
      #(
        "scope",
        json.object([
          #("processDateMeaning", json.string("date_processed_by_alpaca")),
          #("announcementTimestamp", json.null()),
          #("publicationTimestamp", json.null()),
          #("effectiveDateInference", json.null()),
          #("priceAdjustment", json.null()),
          #("economicImpact", json.null()),
          #("correctionLineage", json.null()),
          #("absenceClaim", json.bool(False)),
          #("missingOrNullFields", json.string("preserved_as_unknown")),
          #("emptyCurrency", json.string("preserved_without_usd_assumption")),
          #(
            "completeDataQuality",
            json.string(
              "excludes_unprocessed_incomplete_rows_but_can_include_already_processed_incomplete_rows",
            ),
          ),
          #(
            "availability",
            json.string("provider_and_processing_delays_possible"),
          ),
        ]),
      ),
      #(
        "limitations",
        json.array(
          [
            "The query range is Alpaca process_date, not announcement, ex, record, payable, or effective date.",
            "Alpaca warns that provider and processing delays can postpone availability.",
            "dataQuality=complete is not a completeness guarantee and can include processed records with missing fields.",
            "An empty currency is retained and is not interpreted as USD.",
            "XNYS or XNAS is caller-declared scope; this endpoint does not verify the venue.",
            "Rows and duplicates are preserved without price adjustment or economic-impact calculation.",
          ],
          json.string,
        ),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ]),
  ))
}

pub fn error_message(value: Error) -> String {
  case value {
    WrongTrack(received) ->
      "corporate_actions supports exact track us, received " <> received
    WrongVenue(received) ->
      "corporate_actions venue must be XNYS or XNAS, received " <> received
    InvalidStartDate ->
      "corporate_actions startDate must be canonical YYYY-MM-DD"
    InvalidEndDate -> "corporate_actions endDate must be canonical YYYY-MM-DD"
    InvalidActionType(received) ->
      "corporate_actions does not support requested type " <> received
    InvalidDataQuality(received) ->
      "corporate_actions dataQuality must be complete or all, received "
      <> received
    InvalidQuery(error) -> query_error_message(error)
    NoSourcePages -> "corporate_actions requires at least one source page"
    InvalidPageSequence -> "corporate_actions source page sequence was invalid"
    InvalidPagination ->
      "corporate_actions pagination evidence was inconsistent"
    OutOfOrderPages ->
      "corporate_actions process_date order regressed across pages"
    TooManyActions(maximum, received) ->
      "corporate_actions received "
      <> int.to_string(received)
      <> " rows, exceeding maximumActions "
      <> int.to_string(maximum)
    UnexpectedActionType(value) ->
      "corporate_actions provider returned unrequested type "
      <> corporate_actions.action_type_name(value)
    IdentityMismatch(action_type, id) ->
      "corporate_actions source identity did not correlate with the exact query for "
      <> action_type
      <> " "
      <> id
  }
}

fn parse_action_types(
  remaining: List(String),
  parsed: List(corporate_actions.ActionType),
) -> Result(List(corporate_actions.ActionType), Error) {
  case remaining {
    [] -> Ok(list.reverse(parsed))
    [value, ..rest] -> {
      use action_type <- result.try(case value {
        "cash_dividend" -> Ok(corporate_actions.CashDividendType)
        "stock_dividend" -> Ok(corporate_actions.StockDividendType)
        "forward_split" -> Ok(corporate_actions.ForwardSplitType)
        "reverse_split" -> Ok(corporate_actions.ReverseSplitType)
        "name_change" -> Ok(corporate_actions.NameChangeType)
        value -> Error(InvalidActionType(value))
      })
      parse_action_types(rest, [action_type, ..parsed])
    }
  }
}

fn validate_page_sequence(
  pages: List(SourcePage),
  expected: Int,
) -> Result(Nil, Error) {
  case pages {
    [] if expected == 1 -> Error(NoSourcePages)
    [] -> Ok(Nil)
    [page, ..rest] ->
      case
        page.sequence == expected,
        page.response_byte_length >= 0,
        valid_request_id(page.request_id)
      {
        True, True, True -> validate_page_sequence(rest, expected + 1)
        _, _, _ -> Error(InvalidPageSequence)
      }
  }
}

fn validate_pages(pages: List(SourcePage), plan: Plan) -> Result(Nil, Error) {
  case pages {
    [] -> Ok(Nil)
    [page, ..rest] -> {
      use Nil <- result.try(validate_requested_types(page.actions, plan.query))
      use Nil <- result.try(validate_cash(page.actions.cash_dividends, plan))
      use Nil <- result.try(validate_stock(page.actions.stock_dividends, plan))
      use Nil <- result.try(validate_forward(page.actions.forward_splits, plan))
      use Nil <- result.try(validate_reverse(page.actions.reverse_splits, plan))
      use Nil <- result.try(validate_names(page.actions.name_changes, plan))
      validate_pages(rest, plan)
    }
  }
}

fn validate_requested_types(
  page: corporate_actions.Page,
  query: corporate_actions.Query,
) -> Result(Nil, Error) {
  case
    page.cash_dividends != []
    && !list.contains(query.types, corporate_actions.CashDividendType),
    page.stock_dividends != []
    && !list.contains(query.types, corporate_actions.StockDividendType),
    page.forward_splits != []
    && !list.contains(query.types, corporate_actions.ForwardSplitType),
    page.reverse_splits != []
    && !list.contains(query.types, corporate_actions.ReverseSplitType),
    page.name_changes != []
    && !list.contains(query.types, corporate_actions.NameChangeType)
  {
    True, _, _, _, _ ->
      Error(UnexpectedActionType(corporate_actions.CashDividendType))
    _, True, _, _, _ ->
      Error(UnexpectedActionType(corporate_actions.StockDividendType))
    _, _, True, _, _ ->
      Error(UnexpectedActionType(corporate_actions.ForwardSplitType))
    _, _, _, True, _ ->
      Error(UnexpectedActionType(corporate_actions.ReverseSplitType))
    _, _, _, _, True ->
      Error(UnexpectedActionType(corporate_actions.NameChangeType))
    False, False, False, False, False -> Ok(Nil)
  }
}

fn validate_cash(
  values: List(corporate_actions.CashDividend),
  plan: Plan,
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case
        single_identity_matches(value.symbol, plan.query.symbol),
        single_identity_matches(value.cusip, plan.query.cusip)
      {
        True, True -> validate_cash(rest, plan)
        _, _ -> Error(IdentityMismatch("cash_dividend", value.id))
      }
  }
}

fn validate_stock(
  values: List(corporate_actions.StockDividend),
  plan: Plan,
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case
        single_identity_matches(value.symbol, plan.query.symbol),
        single_identity_matches(value.cusip, plan.query.cusip)
      {
        True, True -> validate_stock(rest, plan)
        _, _ -> Error(IdentityMismatch("stock_dividend", value.id))
      }
  }
}

fn validate_forward(
  values: List(corporate_actions.ForwardSplit),
  plan: Plan,
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case
        single_identity_matches(value.symbol, plan.query.symbol),
        single_identity_matches(value.cusip, plan.query.cusip)
      {
        True, True -> validate_forward(rest, plan)
        _, _ -> Error(IdentityMismatch("forward_split", value.id))
      }
  }
}

fn validate_reverse(
  values: List(corporate_actions.ReverseSplit),
  plan: Plan,
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case
        transition_identity_matches(
          value.symbol,
          value.new_symbol,
          plan.query.symbol,
        ),
        transition_identity_matches(
          value.old_cusip,
          value.new_cusip,
          plan.query.cusip,
        )
      {
        True, True -> validate_reverse(rest, plan)
        _, _ -> Error(IdentityMismatch("reverse_split", value.id))
      }
  }
}

fn validate_names(
  values: List(corporate_actions.NameChange),
  plan: Plan,
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case
        transition_identity_matches(
          value.old_symbol,
          value.new_symbol,
          plan.query.symbol,
        ),
        transition_identity_matches(
          value.old_cusip,
          value.new_cusip,
          plan.query.cusip,
        )
      {
        True, True -> validate_names(rest, plan)
        _, _ -> Error(IdentityMismatch("name_change", value.id))
      }
  }
}

fn single_identity_matches(value: Option(String), expected: String) -> Bool {
  case value {
    None -> True
    Some(value) -> value == expected
  }
}

fn transition_identity_matches(
  before: Option(String),
  after: Option(String),
  expected: String,
) -> Bool {
  case before, after {
    None, None -> True
    Some(value), _ if value == expected -> True
    _, Some(value) if value == expected -> True
    _, _ -> False
  }
}

fn validate_pagination(
  pages: List(SourcePage),
  pagination: Pagination,
  total: Int,
  query: corporate_actions.Query,
) -> Result(Nil, Error) {
  let assert Some(last) = last_page(pages)
  case
    pagination,
    last.actions.next_page_token,
    list.length(pages) == query.maximum_pages,
    total == query.maximum_actions
  {
    Complete, None, _, _ -> Ok(Nil)
    TruncatedByPageBudget(maximum), Some(_), True, _
      if maximum == query.maximum_pages
    -> Ok(Nil)
    TruncatedByActionBudget(maximum), Some(_), _, True
      if maximum == query.maximum_actions
    -> Ok(Nil)
    _, _, _, _ -> Error(InvalidPagination)
  }
}

fn validate_page_order(
  pages: List(SourcePage),
  previous_maximum: Option(String),
) -> Result(Nil, Error) {
  case pages {
    [] -> Ok(Nil)
    [page, ..rest] ->
      case process_date_range(page.actions) {
        None -> validate_page_order(rest, previous_maximum)
        Some(#(minimum, maximum)) ->
          case previous_maximum {
            Some(previous) ->
              case string.compare(minimum, previous) {
                Lt -> Error(OutOfOrderPages)
                _ -> validate_page_order(rest, Some(maximum))
              }
            None -> validate_page_order(rest, Some(maximum))
          }
      }
  }
}

fn process_date_range(
  page: corporate_actions.Page,
) -> Option(#(String, String)) {
  let dates =
    list.flatten([
      list.map(page.cash_dividends, fn(value) { value.process_date }),
      list.map(page.stock_dividends, fn(value) { value.process_date }),
      list.map(page.forward_splits, fn(value) { value.process_date }),
      list.map(page.reverse_splits, fn(value) { value.process_date }),
      list.map(page.name_changes, fn(value) { value.process_date }),
    ])
    |> option.values
  case dates {
    [] -> None
    [first, ..rest] ->
      rest
      |> list.fold(from: #(first, first), with: fn(range, value) {
        let minimum = case string.compare(value, range.0) {
          Lt -> value
          _ -> range.0
        }
        let maximum = case string.compare(value, range.1) {
          Lt -> range.1
          _ -> value
        }
        #(minimum, maximum)
      })
      |> Some
  }
}

fn last_page(pages: List(SourcePage)) -> Option(SourcePage) {
  case pages {
    [] -> None
    [page] -> Some(page)
    [_, ..rest] -> last_page(rest)
  }
}

fn valid_request_id(value: Option(String)) -> Bool {
  case value {
    None -> True
    Some(value) ->
      value != ""
      && string.trim(value) == value
      && string.length(value) <= 1024
      && !string.contains(value, "\r")
      && !string.contains(value, "\n")
  }
}

fn page_json(page: SourcePage, plan: Plan) -> json.Json {
  json.object([
    #("sequence", json.int(page.sequence)),
    #("requestId", option_json(page.request_id)),
    #("responseByteLength", json.int(page.response_byte_length)),
    #(
      "contentSha256",
      page.content_sha256 |> identity.sha256_value |> json.string,
    ),
    #(
      "contentDigestMeaning",
      json.string(
        "page_content_binding_not_provider_signature_or_origin_authentication",
      ),
    ),
    #(
      "counts",
      json.object([
        #("cashDividend", json.int(list.length(page.actions.cash_dividends))),
        #("stockDividend", json.int(list.length(page.actions.stock_dividends))),
        #("forwardSplit", json.int(list.length(page.actions.forward_splits))),
        #("reverseSplit", json.int(list.length(page.actions.reverse_splits))),
        #("nameChange", json.int(list.length(page.actions.name_changes))),
      ]),
    ),
    #(
      "actions",
      json.object([
        #(
          "cashDividends",
          json.array(page.actions.cash_dividends, fn(value) {
            cash_json(value, plan)
          }),
        ),
        #(
          "stockDividends",
          json.array(page.actions.stock_dividends, fn(value) {
            stock_json(value, plan)
          }),
        ),
        #(
          "forwardSplits",
          json.array(page.actions.forward_splits, fn(value) {
            forward_json(value, plan)
          }),
        ),
        #(
          "reverseSplits",
          json.array(page.actions.reverse_splits, fn(value) {
            reverse_json(value, plan)
          }),
        ),
        #(
          "nameChanges",
          json.array(page.actions.name_changes, fn(value) {
            name_json(value, plan)
          }),
        ),
      ]),
    ),
    #("nextPageToken", option_json(page.actions.next_page_token)),
  ])
}

fn cash_json(value: corporate_actions.CashDividend, plan: Plan) -> json.Json {
  json.object([
    #("type", json.string("cash_dividend")),
    #("id", json.string(value.id)),
    #("symbol", option_json(value.symbol)),
    #("cusip", option_json(value.cusip)),
    #("isin", option_json(value.isin)),
    #("rate", option_json(value.rate)),
    #("special", option_bool_json(value.special)),
    #("foreign", option_bool_json(value.foreign)),
    #("processDate", option_json(value.process_date)),
    #("exDate", option_json(value.ex_date)),
    #("recordDate", option_json(value.record_date)),
    #("payableDate", option_json(value.payable_date)),
    #("dueBillOnDate", option_json(value.due_bill_on_date)),
    #("dueBillOffDate", option_json(value.due_bill_off_date)),
    #("currency", option_json(value.currency)),
    #("subType", option_json(value.sub_type)),
    #(
      "symbolCorrelation",
      json.string(single_correlation(value.symbol, plan.query.symbol)),
    ),
    #(
      "cusipCorrelation",
      json.string(single_correlation(value.cusip, plan.query.cusip)),
    ),
  ])
}

fn stock_json(value: corporate_actions.StockDividend, plan: Plan) -> json.Json {
  json.object([
    #("type", json.string("stock_dividend")),
    #("id", json.string(value.id)),
    #("symbol", option_json(value.symbol)),
    #("cusip", option_json(value.cusip)),
    #("isin", option_json(value.isin)),
    #("rate", option_json(value.rate)),
    #("processDate", option_json(value.process_date)),
    #("exDate", option_json(value.ex_date)),
    #("recordDate", option_json(value.record_date)),
    #("payableDate", option_json(value.payable_date)),
    #("currency", option_json(value.currency)),
    #(
      "symbolCorrelation",
      json.string(single_correlation(value.symbol, plan.query.symbol)),
    ),
    #(
      "cusipCorrelation",
      json.string(single_correlation(value.cusip, plan.query.cusip)),
    ),
  ])
}

fn forward_json(
  value: corporate_actions.ForwardSplit,
  plan: Plan,
) -> json.Json {
  json.object([
    #("type", json.string("forward_split")),
    #("id", json.string(value.id)),
    #("symbol", option_json(value.symbol)),
    #("cusip", option_json(value.cusip)),
    #("isin", option_json(value.isin)),
    #("oldRate", option_json(value.old_rate)),
    #("newRate", option_json(value.new_rate)),
    #("processDate", option_json(value.process_date)),
    #("exDate", option_json(value.ex_date)),
    #("recordDate", option_json(value.record_date)),
    #("payableDate", option_json(value.payable_date)),
    #("dueBillRedemptionDate", option_json(value.due_bill_redemption_date)),
    #("currency", option_json(value.currency)),
    #(
      "symbolCorrelation",
      json.string(single_correlation(value.symbol, plan.query.symbol)),
    ),
    #(
      "cusipCorrelation",
      json.string(single_correlation(value.cusip, plan.query.cusip)),
    ),
  ])
}

fn reverse_json(
  value: corporate_actions.ReverseSplit,
  plan: Plan,
) -> json.Json {
  json.object([
    #("type", json.string("reverse_split")),
    #("id", json.string(value.id)),
    #("symbol", option_json(value.symbol)),
    #("newSymbol", option_json(value.new_symbol)),
    #("oldCusip", option_json(value.old_cusip)),
    #("newCusip", option_json(value.new_cusip)),
    #("oldIsin", option_json(value.old_isin)),
    #("newIsin", option_json(value.new_isin)),
    #("oldRate", option_json(value.old_rate)),
    #("newRate", option_json(value.new_rate)),
    #("processDate", option_json(value.process_date)),
    #("exDate", option_json(value.ex_date)),
    #("recordDate", option_json(value.record_date)),
    #("payableDate", option_json(value.payable_date)),
    #("currency", option_json(value.currency)),
    #(
      "symbolCorrelation",
      json.string(transition_correlation(
        value.symbol,
        value.new_symbol,
        plan.query.symbol,
      )),
    ),
    #(
      "cusipCorrelation",
      json.string(transition_correlation(
        value.old_cusip,
        value.new_cusip,
        plan.query.cusip,
      )),
    ),
  ])
}

fn name_json(value: corporate_actions.NameChange, plan: Plan) -> json.Json {
  json.object([
    #("type", json.string("name_change")),
    #("id", json.string(value.id)),
    #("oldSymbol", option_json(value.old_symbol)),
    #("newSymbol", option_json(value.new_symbol)),
    #("oldCusip", option_json(value.old_cusip)),
    #("newCusip", option_json(value.new_cusip)),
    #("oldIsin", option_json(value.old_isin)),
    #("newIsin", option_json(value.new_isin)),
    #("processDate", option_json(value.process_date)),
    #("currency", option_json(value.currency)),
    #(
      "symbolCorrelation",
      json.string(transition_correlation(
        value.old_symbol,
        value.new_symbol,
        plan.query.symbol,
      )),
    ),
    #(
      "cusipCorrelation",
      json.string(transition_correlation(
        value.old_cusip,
        value.new_cusip,
        plan.query.cusip,
      )),
    ),
  ])
}

fn single_correlation(value: Option(String), expected: String) -> String {
  case value {
    None -> "source_identity_missing"
    Some(value) if value == expected -> "exact_source_match"
    Some(_) -> "mismatch"
  }
}

fn transition_correlation(
  before: Option(String),
  after: Option(String),
  expected: String,
) -> String {
  case before, after {
    None, None -> "source_identity_missing"
    Some(value), _ if value == expected -> "exact_source_match"
    _, Some(value) if value == expected -> "exact_source_match"
    _, _ -> "mismatch"
  }
}

fn pagination_json(
  pages: List(SourcePage),
  pagination: Pagination,
) -> json.Json {
  let assert Some(last) = last_page(pages)
  let budget = case pagination {
    Complete -> json.null()
    TruncatedByPageBudget(maximum) | TruncatedByActionBudget(maximum) ->
      json.int(maximum)
  }
  json.object([
    #("state", json.string(pagination_name(pagination))),
    #("budget", budget),
    #("nextPageToken", option_json(last.actions.next_page_token)),
  ])
}

fn pagination_name(value: Pagination) -> String {
  case value {
    Complete -> "complete"
    TruncatedByPageBudget(_) -> "truncated_by_page_budget"
    TruncatedByActionBudget(_) -> "truncated_by_action_budget"
  }
}

fn option_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn option_bool_json(value: Option(Bool)) -> json.Json {
  case value {
    Some(value) -> json.bool(value)
    None -> json.null()
  }
}

fn query_error_message(value: corporate_actions.QueryError) -> String {
  case value {
    corporate_actions.InvalidSymbol ->
      "corporate_actions symbol must be exact uppercase provider syntax"
    corporate_actions.InvalidCusip ->
      "corporate_actions cusip must be an exact nine-character CUSIP"
    corporate_actions.InvalidDateRange ->
      "corporate_actions startDate must not follow endDate"
    corporate_actions.EmptyTypes ->
      "corporate_actions requires at least one action type"
    corporate_actions.DuplicateType(value) ->
      "corporate_actions contains duplicate type "
      <> corporate_actions.action_type_name(value)
    corporate_actions.InvalidPageSize ->
      "corporate_actions pageSize must be between 1 and 1000"
    corporate_actions.InvalidMaximumPages ->
      "corporate_actions maximumPages must be between 1 and 10"
    corporate_actions.InvalidMaximumActions ->
      "corporate_actions maximumActions must be between 1 and 5000"
  }
}

fn parse_date(value: String) -> Result(Date, Nil) {
  case string.split(value, "-") {
    [year_text, month_text, day_text] ->
      case
        int.parse(year_text),
        int.parse(month_text),
        int.parse(day_text),
        string.length(year_text),
        string.length(month_text),
        string.length(day_text)
      {
        Ok(year), Ok(month), Ok(day), 4, 2, 2 ->
          time.date(year, month, day) |> result.map_error(fn(_) { Nil })
        _, _, _, _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> pad(month) <> "-" <> pad(day)
}

fn pad(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn venue_name(value: Venue) -> String {
  case value {
    Xnys -> "XNYS"
    Xnas -> "XNAS"
  }
}
