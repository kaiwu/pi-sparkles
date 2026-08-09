import finance_core/time
import finance_market_alpaca/corporate_actions
import finance_provenance/identity
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_corporate_actions/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn plan_requires_exact_us_scope_identity_types_and_budgets_test() {
  let assert Ok(value) = plan(20)
  value.venue |> should.equal(domain.Xnas)
  value.query.symbol |> should.equal("AAPL")
  value.query.cusip |> should.equal("037833100")

  domain.plan(
    "hk",
    "XNAS",
    "AAPL",
    "037833100",
    "2024-08-01",
    "2024-08-31",
    ["cash_dividend"],
    "complete",
    100,
    2,
    20,
  )
  |> should.equal(Error(domain.WrongTrack("hk")))
  domain.plan(
    "us",
    "XHKG",
    "AAPL",
    "037833100",
    "2024-08-01",
    "2024-08-31",
    ["cash_dividend"],
    "complete",
    100,
    2,
    20,
  )
  |> should.equal(Error(domain.WrongVenue("XHKG")))
  domain.plan(
    "us",
    "XNAS",
    "AAPL",
    "037833100",
    "2024-08-01",
    "2024-08-31",
    ["cash_dividend", "cash_dividend"],
    "complete",
    100,
    2,
    20,
  )
  |> should.equal(
    Error(
      domain.InvalidQuery(corporate_actions.DuplicateType(
        corporate_actions.CashDividendType,
      )),
    ),
  )
}

pub fn result_preserves_every_selected_source_shape_duplicate_and_limitation_test() {
  let assert Ok(query) = plan(20)
  let assert Ok(output) =
    domain.run(query, [source_page(1, full_page(None))], domain.Complete, now())
  let text = json.to_string(output.details)

  text |> string.contains("\"actionCount\":6") |> should.be_true
  text |> string.contains("\"cashDividend\":2") |> should.be_true
  text |> string.contains("\"rate\":\"0.2400\"") |> should.be_true
  text |> string.contains("\"newRate\":\"4.000\"") |> should.be_true
  text |> string.contains("\"newSymbol\":\"APPL\"") |> should.be_true
  text |> string.contains("\"currency\":\"\"") |> should.be_true
  text
  |> string.contains(
    "\"venueEvidence\":\"caller_declared_not_provider_verified\"",
  )
  |> should.be_true
  text
  |> string.contains("\"processDateMeaning\":\"date_processed_by_alpaca\"")
  |> should.be_true
  text |> string.contains("\"absenceClaim\":false") |> should.be_true
  text
  |> string.contains("not_provider_signature_or_origin_authentication")
  |> should.be_true
  output.summary
  |> string.contains("No venue authentication, price adjustment")
  |> should.be_true
}

pub fn identity_mismatch_fails_closed_but_missing_source_identity_stays_unknown_test() {
  let assert Ok(query) = plan(20)
  let mismatch =
    corporate_actions.Page(
      [cash("MSFT", Some("594918104"))],
      [],
      [],
      [],
      [],
      None,
    )
  domain.run(query, [source_page(1, mismatch)], domain.Complete, now())
  |> should.equal(Error(domain.IdentityMismatch("cash_dividend", "cash-1")))

  let unknown =
    corporate_actions.Page(
      [
        corporate_actions.CashDividend(
          "cash-unknown",
          None,
          None,
          None,
          Some("0.100"),
          None,
          None,
          Some("2024-08-10"),
          None,
          None,
          None,
          None,
          None,
          None,
          None,
        ),
      ],
      [],
      [],
      [],
      [],
      None,
    )
  let assert Ok(output) =
    domain.run(query, [source_page(1, unknown)], domain.Complete, now())
  output.details
  |> json.to_string
  |> string.contains("\"symbolCorrelation\":\"source_identity_missing\"")
  |> should.be_true
}

pub fn pagination_evidence_must_match_page_and_action_budgets_test() {
  let assert Ok(query) = plan(6)
  let page = source_page(1, full_page(Some("next")))
  let assert Ok(output) =
    domain.run(query, [page], domain.TruncatedByActionBudget(6), now())
  output.details
  |> json.to_string
  |> string.contains("\"state\":\"truncated_by_action_budget\"")
  |> should.be_true

  domain.run(query, [page], domain.Complete, now())
  |> should.equal(Error(domain.InvalidPagination))
  domain.run(
    query,
    [domain.SourcePage(..page, sequence: 2)],
    domain.TruncatedByActionBudget(6),
    now(),
  )
  |> should.equal(Error(domain.InvalidPageSequence))
}

pub fn unrequested_provider_action_type_is_rejected_test() {
  let assert Ok(query) =
    domain.plan(
      "us",
      "XNYS",
      "AAPL",
      "037833100",
      "2024-08-01",
      "2024-08-31",
      ["cash_dividend"],
      "all",
      100,
      1,
      20,
    )
  domain.run(query, [source_page(1, full_page(None))], domain.Complete, now())
  |> should.equal(
    Error(domain.UnexpectedActionType(corporate_actions.StockDividendType)),
  )
}

pub fn process_date_order_cannot_regress_between_provider_pages_test() {
  let assert Ok(query) = plan(20)
  let first_cash = cash("AAPL", Some("037833100"))
  let first =
    corporate_actions.Page(
      [
        corporate_actions.CashDividend(
          ..first_cash,
          process_date: Some("2024-08-20"),
        ),
      ],
      [],
      [],
      [],
      [],
      Some("page-two"),
    )
  let second =
    corporate_actions.Page(
      [cash("AAPL", Some("037833100"))],
      [],
      [],
      [],
      [],
      None,
    )

  domain.run(
    query,
    [source_page(1, first), source_page(2, second)],
    domain.Complete,
    now(),
  )
  |> should.equal(Error(domain.OutOfOrderPages))
}

fn plan(maximum_actions: Int) -> Result(domain.Plan, domain.Error) {
  domain.plan(
    "us",
    "XNAS",
    "AAPL",
    "037833100",
    "2024-08-01",
    "2024-08-31",
    [
      "cash_dividend",
      "stock_dividend",
      "forward_split",
      "reverse_split",
      "name_change",
    ],
    "all",
    100,
    2,
    maximum_actions,
  )
}

fn source_page(
  sequence: Int,
  page: corporate_actions.Page,
) -> domain.SourcePage {
  let assert Ok(digest) = identity.sha256(string.repeat("a", 64))
  domain.SourcePage(sequence, Some("request-1"), 1024, digest, page)
}

fn full_page(next_page_token: Option(String)) -> corporate_actions.Page {
  corporate_actions.Page(
    [cash("AAPL", Some("037833100")), cash("AAPL", Some("037833100"))],
    [
      corporate_actions.StockDividend(
        "stock-1",
        Some("AAPL"),
        Some("037833100"),
        Some("US0378331005"),
        Some("0.050"),
        Some("2024-08-11"),
        Some("2024-08-12"),
        None,
        None,
        None,
      ),
    ],
    [
      corporate_actions.ForwardSplit(
        "forward-1",
        Some("AAPL"),
        Some("037833100"),
        Some("US0378331005"),
        Some("1"),
        Some("4.000"),
        Some("2024-08-12"),
        Some("2024-08-13"),
        None,
        None,
        None,
        None,
      ),
    ],
    [
      corporate_actions.ReverseSplit(
        "reverse-1",
        Some("AAPL"),
        Some("APLC"),
        Some("037833100"),
        Some("037833209"),
        Some("US0378331005"),
        Some("US0378332094"),
        Some("10"),
        Some("1"),
        Some("2024-08-13"),
        Some("2024-08-14"),
        None,
        None,
        None,
      ),
    ],
    [
      corporate_actions.NameChange(
        "name-1",
        Some("AAPL"),
        Some("APPL"),
        Some("037833100"),
        Some("037833308"),
        Some("US0378331005"),
        Some("US0378333084"),
        Some("2024-08-14"),
        Some(""),
      ),
    ],
    next_page_token,
  )
}

fn cash(
  symbol: String,
  cusip: Option(String),
) -> corporate_actions.CashDividend {
  corporate_actions.CashDividend(
    "cash-1",
    Some(symbol),
    cusip,
    Some("US0378331005"),
    Some("0.2400"),
    Some(False),
    Some(False),
    Some("2024-08-10"),
    Some("2024-08-11"),
    Some("2024-08-12"),
    Some("2024-08-20"),
    None,
    None,
    Some("USD"),
    None,
  )
}

fn now() -> time.Instant {
  let assert Ok(value) = time.instant(1_723_075_200_000)
  value
}
