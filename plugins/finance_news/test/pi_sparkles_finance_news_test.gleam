import finance_core/time
import finance_market_alpaca/news
import finance_provenance/identity
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_finance_news/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn plan_requires_exact_us_scope_utc_range_and_budgets_test() {
  let assert Ok(value) = plan(10)
  value.venue |> should.equal(domain.Xnas)
  value.query.symbol |> should.equal("AAPL")

  domain.plan(
    "hk",
    "XNAS",
    "AAPL",
    "2026-07-01T00:00:00Z",
    "2026-07-02T00:00:00Z",
    5,
    2,
    10,
  )
  |> should.equal(Error(domain.WrongTrack("hk")))
  domain.plan(
    "us",
    "XHKG",
    "AAPL",
    "2026-07-01T00:00:00Z",
    "2026-07-02T00:00:00Z",
    5,
    2,
    10,
  )
  |> should.equal(Error(domain.WrongVenue("XHKG")))
}

pub fn result_preserves_exact_metadata_receipts_rights_and_unknowns_test() {
  let assert Ok(query) = plan(10)
  let first =
    article(
      101,
      "First exact headline",
      "2026-07-01T10:00:00.123456Z",
      "2026-07-01T10:01:00Z",
      ["AAPL", "MSFT"],
      "benzinga",
    )
  let second =
    article(
      101,
      "First exact headline repeated",
      "2026-07-01T10:00:00.123456Z",
      "2026-07-01T10:02:00Z",
      ["AAPL"],
      "benzinga",
    )
  let assert Ok(output) =
    domain.run(
      query,
      [source_page(1, [first, second], None)],
      domain.Complete,
      now(),
    )
  let text = json.to_string(output.details)

  text |> string.contains("\"articleCount\":2") |> should.be_true
  text |> string.contains("First exact headline") |> should.be_true
  text |> string.contains("2026-07-01T10:00:00.123456Z") |> should.be_true
  text |> string.contains("\"summaryReturned\":false") |> should.be_true
  text |> string.contains("\"articleBodiesReturned\":false") |> should.be_true
  text
  |> string.contains("requires_express_prior_written_consent")
  |> should.be_true
  text
  |> string.contains("provider_association_not_issuer_listing_or_venue_proof")
  |> should.be_true
  text |> string.contains("\"catalystClassification\":null") |> should.be_true
  output.summary
  |> string.contains("not verified events or catalyst conclusions")
  |> should.be_true
}

pub fn pagination_evidence_must_match_page_and_article_budgets_test() {
  let assert Ok(query) = plan(1)
  let page =
    source_page(
      1,
      [
        article(
          101,
          "Exact headline",
          "2026-07-01T10:00:00Z",
          "2026-07-01T10:01:00Z",
          ["AAPL"],
          "benzinga",
        ),
      ],
      Some("next"),
    )
  let assert Ok(output) =
    domain.run(query, [page], domain.TruncatedByArticleBudget(1), now())
  output.details
  |> json.to_string
  |> string.contains("\"state\":\"truncated_by_article_budget\"")
  |> should.be_true

  domain.run(query, [page], domain.Complete, now())
  |> should.equal(Error(domain.InvalidPagination))
  domain.run(query, [page], domain.TruncatedByArticleBudget(2), now())
  |> should.equal(Error(domain.InvalidPagination))
  domain.run(
    query,
    [domain.SourcePage(..page, sequence: 2)],
    domain.TruncatedByArticleBudget(1),
    now(),
  )
  |> should.equal(Error(domain.InvalidPageSequence))
}

pub fn source_symbol_and_time_mismatches_fail_closed_test() {
  let assert Ok(query) = plan(10)
  let wrong_source =
    article(
      101,
      "Exact headline",
      "2026-07-01T10:00:00Z",
      "2026-07-01T10:01:00Z",
      ["AAPL"],
      "other",
    )
  domain.run(
    query,
    [source_page(1, [wrong_source], None)],
    domain.Complete,
    now(),
  )
  |> should.equal(Error(domain.SourceMismatch(101, "other")))

  let wrong_symbol =
    news.Article(..wrong_source, source: "benzinga", symbols: ["MSFT"])
  domain.run(
    query,
    [source_page(1, [wrong_symbol], None)],
    domain.Complete,
    now(),
  )
  |> should.equal(Error(domain.SymbolAssociationMismatch(101)))

  let regressed =
    article(
      102,
      "Earlier update",
      "2026-07-01T09:00:00Z",
      "2026-07-01T09:01:00Z",
      ["AAPL"],
      "benzinga",
    )
  let first = news.Article(..wrong_source, source: "benzinga")
  domain.run(
    query,
    [source_page(1, [first], Some("next")), source_page(2, [regressed], None)],
    domain.Complete,
    now(),
  )
  |> should.equal(Error(domain.OutOfOrderPages(102)))
}

fn plan(maximum_articles: Int) -> Result(domain.Plan, domain.Error) {
  domain.plan(
    "us",
    "XNAS",
    "AAPL",
    "2026-07-01T00:00:00Z",
    "2026-07-02T00:00:00Z",
    5,
    2,
    maximum_articles,
  )
}

fn article(
  id: Int,
  headline: String,
  created_at: String,
  updated_at: String,
  symbols: List(String),
  source: String,
) -> news.Article {
  let assert Ok(created) = news.parse_instant(created_at)
  let assert Ok(updated) = news.parse_instant(updated_at)
  news.Article(
    id,
    headline,
    "Benzinga Newsdesk",
    created_at,
    created,
    updated_at,
    updated,
    "https://www.benzinga.com/news/" <> int.to_string(id),
    symbols,
    source,
    True,
    False,
    1,
  )
}

fn source_page(
  sequence: Int,
  articles: List(news.Article),
  next_page_token: Option(String),
) -> domain.SourcePage {
  let assert Ok(digest) = identity.sha256(string.repeat("a", 64))
  domain.SourcePage(
    sequence,
    Some("request-1"),
    1024,
    digest,
    news.Page(articles, next_page_token),
  )
}

fn now() -> time.Instant {
  let assert Ok(value) = time.instant(1_786_000_000_000)
  value
}
