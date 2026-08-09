import finance_core/time.{type Instant}
import finance_market_alpaca/bars
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Query {
  Query(
    symbol: String,
    start_at: String,
    start_instant: Instant,
    end_at: String,
    end_instant: Instant,
    page_size: Int,
    maximum_pages: Int,
    maximum_articles: Int,
  )
}

pub type Article {
  Article(
    id: Int,
    headline: String,
    author: String,
    created_at: String,
    created_instant: Instant,
    updated_at: String,
    updated_instant: Instant,
    url: String,
    symbols: List(String),
    source: String,
    summary_present: Bool,
    content_present: Bool,
    image_count: Int,
  )
}

pub type Page {
  Page(articles: List(Article), next_page_token: Option(String))
}

pub type QueryError {
  InvalidSymbol
  InvalidStartTimestamp
  InvalidEndTimestamp
  InvalidRange
  RangeTooLarge
  InvalidPageSize
  InvalidMaximumPages
  InvalidMaximumArticles
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  TooManyArticles(maximum: Int, received: Int)
  InvalidPageToken
  UnexpectedSource(id: Int, source: String)
  MissingQuerySymbol(id: Int)
  InvalidArticleTime(id: Int)
  OutOfOrder(id: Int)
}

pub fn query(
  symbol: String,
  start_at: String,
  end_at: String,
  page_size: Int,
  maximum_pages: Int,
  maximum_articles: Int,
) -> Result(Query, QueryError) {
  use start <- result.try(
    parse_instant(start_at) |> result.map_error(fn(_) { InvalidStartTimestamp }),
  )
  use end <- result.try(
    parse_instant(end_at) |> result.map_error(fn(_) { InvalidEndTimestamp }),
  )
  let start_ms = time.unix_milliseconds(start)
  let end_ms = time.unix_milliseconds(end)
  case
    valid_symbol(symbol),
    start_ms <= end_ms,
    end_ms - start_ms <= 31 * 86_400_000,
    page_size >= 1 && page_size <= 50,
    maximum_pages >= 1 && maximum_pages <= 10,
    maximum_articles >= 1 && maximum_articles <= 500
  {
    False, _, _, _, _, _ -> Error(InvalidSymbol)
    _, False, _, _, _, _ -> Error(InvalidRange)
    _, _, False, _, _, _ -> Error(RangeTooLarge)
    _, _, _, False, _, _ -> Error(InvalidPageSize)
    _, _, _, _, False, _ -> Error(InvalidMaximumPages)
    _, _, _, _, _, False -> Error(InvalidMaximumArticles)
    True, True, True, True, True, True ->
      Ok(Query(
        symbol,
        start_at,
        start,
        end_at,
        end,
        page_size,
        maximum_pages,
        maximum_articles,
      ))
  }
}

pub fn decode_page(
  body: String,
  query: Query,
  page_limit: Int,
) -> Result(Page, DecodeError) {
  use page <- result.try(
    body
    |> json.parse(page_decoder())
    |> result.map_error(InvalidJson),
  )
  use Nil <- result.try(case list.length(page.articles) <= page_limit {
    True -> Ok(Nil)
    False -> Error(TooManyArticles(page_limit, list.length(page.articles)))
  })
  use Nil <- result.try(validate_page_token(page.next_page_token))
  use Nil <- result.try(validate_articles(page.articles, query, None))
  Ok(page)
}

pub fn parse_instant(value: String) -> Result(Instant, Nil) {
  use #(instant, _) <- result.try(bars.parse_timestamp(value))
  Ok(instant)
}

fn page_decoder() -> decode.Decoder(Page) {
  use fields <- decode.then(decode.dict(decode.string, any_value_decoder()))
  use articles <- decode.field("news", decode.list(of: article_decoder()))
  use next_page_token <- decode.field(
    "next_page_token",
    decode.optional(decode.string),
  )
  let page = Page(articles, next_page_token)
  case
    fields
    |> dict.keys
    |> list.all(fn(name) { list.contains(["news", "next_page_token"], name) })
  {
    True -> decode.success(page)
    False -> decode.failure(page, "exact Alpaca news response fields")
  }
}

fn article_decoder() -> decode.Decoder(Article) {
  use fields <- decode.then(decode.dict(decode.string, any_value_decoder()))
  use id <- decode.field("id", decode.int)
  use headline <- decode.field("headline", decode.string)
  use author <- decode.field("author", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use updated_at <- decode.field("updated_at", decode.string)
  use url <- decode.field("url", decode.string)
  use symbols <- decode.field("symbols", decode.list(of: decode.string))
  use source <- decode.field("source", decode.string)
  use summary <- decode.optional_field("summary", "", decode.string)
  use content <- decode.optional_field("content", "", decode.string)
  use images <- decode.optional_field(
    "images",
    [],
    decode.list(of: any_value_decoder()),
  )
  let assert Ok(epoch) = time.instant(0)
  let article = case parse_instant(created_at), parse_instant(updated_at) {
    Ok(created), Ok(updated) ->
      Article(
        id,
        headline,
        author,
        created_at,
        created,
        updated_at,
        updated,
        url,
        symbols,
        source,
        summary != "",
        content != "",
        list.length(images),
      )
    _, _ ->
      Article(
        id,
        headline,
        author,
        created_at,
        epoch,
        updated_at,
        epoch,
        url,
        symbols,
        source,
        summary != "",
        content != "",
        list.length(images),
      )
  }
  case
    fields
    |> dict.keys
    |> list.all(fn(name) {
      list.contains(
        [
          "id",
          "headline",
          "author",
          "created_at",
          "updated_at",
          "url",
          "symbols",
          "source",
          "summary",
          "content",
          "images",
        ],
        name,
      )
    }),
    parse_instant(created_at),
    parse_instant(updated_at),
    valid_text(headline, 10_000),
    valid_text(author, 1000),
    valid_url(url),
    symbols != [] && list.all(symbols, valid_symbol),
    source != "" && string.length(source) <= 100
  {
    True, Ok(_), Ok(_), True, True, True, True, True -> decode.success(article)
    _, _, _, _, _, _, _, _ ->
      decode.failure(article, "valid exact Alpaca news article metadata")
  }
}

fn validate_articles(
  values: List(Article),
  query: Query,
  previous: Option(Instant),
) -> Result(Nil, DecodeError) {
  case values {
    [] -> Ok(Nil)
    [article, ..rest] ->
      case article.source {
        "benzinga" ->
          case list.contains(article.symbols, query.symbol) {
            False -> Error(MissingQuerySymbol(article.id))
            True ->
              case
                time.unix_milliseconds(article.updated_instant)
                < time.unix_milliseconds(article.created_instant)
              {
                True -> Error(InvalidArticleTime(article.id))
                False ->
                  case previous {
                    Some(previous) ->
                      case
                        time.unix_milliseconds(article.updated_instant)
                        < time.unix_milliseconds(previous)
                      {
                        True -> Error(OutOfOrder(article.id))
                        False ->
                          validate_articles(
                            rest,
                            query,
                            Some(article.updated_instant),
                          )
                      }
                    None ->
                      validate_articles(
                        rest,
                        query,
                        Some(article.updated_instant),
                      )
                  }
              }
          }
        value -> Error(UnexpectedSource(article.id, value))
      }
  }
}

fn validate_page_token(value: Option(String)) -> Result(Nil, DecodeError) {
  case value {
    None -> Ok(Nil)
    Some(token) ->
      case valid_text(token, 2048) {
        True -> Ok(Nil)
        False -> Error(InvalidPageToken)
      }
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

fn valid_text(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn valid_url(value: String) -> Bool {
  string.starts_with(value, "https://") && valid_text(value, 8192)
}

fn any_value_decoder() -> decode.Decoder(Nil) {
  decode.new_primitive_decoder("JSON value", accept_any_value)
}

fn accept_any_value(_value: Dynamic) -> Result(Nil, Nil) {
  Ok(Nil)
}
