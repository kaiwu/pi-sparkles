import finance_core/time
import finance_sse_index/query.{type Query}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub opaque type Member {
  Member(
    code: String,
    name: String,
    english_name: String,
    publication_date: String,
  )
}

pub opaque type Constituents {
  Constituents(publication_date: String, members: List(Member))
}

type Page {
  Page(page_count: Int, total: Int, page_number: Int, page_size: Int)
}

type Payload {
  Payload(page: Page, members: List(Member))
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  InvalidPagination
  CountMismatch(expected: Int, received: Int)
  UnexpectedMemberCount(expected: Int, received: Int)
  InvalidMemberIdentity(code: String)
  DuplicateMemberIdentity(code: String)
  InvalidMarketSource(code: String)
  InvalidPublicationDate(value: String)
  ConflictingPublicationDate(expected: String, received: String)
  EmptyName(code: String)
}

pub fn decode(
  body: String,
  for query: Query,
) -> Result(Constituents, DecodeError) {
  use payload <- result.try(
    json.parse(body, payload_decoder())
    |> result.map_error(InvalidJson),
  )
  let Page(page_count, total, page_number, page_size) = payload.page
  use _ <- result.try(
    case page_count == 1 && page_number == 1 && page_size == 60 {
      True -> Ok(Nil)
      False -> Error(InvalidPagination)
    },
  )
  use _ <- result.try(case list.length(payload.members) == total {
    True -> Ok(Nil)
    False -> Error(CountMismatch(total, list.length(payload.members)))
  })
  use _ <- result.try(case total == query.expected_members(query) {
    True -> Ok(Nil)
    False -> Error(UnexpectedMemberCount(query.expected_members(query), total))
  })
  use publication_date <- result.try(validate_members(payload.members, [], ""))
  Ok(Constituents(publication_date, payload.members))
}

pub fn publication_date(value: Constituents) -> String {
  value.publication_date
}

pub fn members(value: Constituents) -> List(Member) {
  value.members
}

pub fn code(value: Member) -> String {
  value.code
}

pub fn name(value: Member) -> String {
  value.name
}

pub fn english_name(value: Member) -> String {
  value.english_name
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use page <- decode.field("pageHelp", page_decoder())
  use members <- decode.field("result", decode.list(of: member_decoder()))
  decode.success(Payload(page, members))
}

fn page_decoder() -> decode.Decoder(Page) {
  use page_count <- decode.field("pageCount", decode.int)
  use total <- decode.field("total", decode.int)
  use page_number <- decode.field("pageNo", decode.int)
  use page_size <- decode.field("pageSize", decode.int)
  decode.success(Page(page_count, total, page_number, page_size))
}

fn member_decoder() -> decode.Decoder(Member) {
  use english_name <- decode.field("securityAbbrEn", decode.string)
  use name <- decode.field("securityAbbr", decode.string)
  use publication_date <- decode.field("inDate", decode.string)
  use code <- decode.field("securityCode", decode.string)
  use market_source <- decode.field("marketSource", decode.string)
  case market_source == "1" {
    True -> decode.success(Member(code, name, english_name, publication_date))
    False ->
      decode.failure(
        Member(code, name, english_name, publication_date),
        "SSE marketSource 1 constituent",
      )
  }
}

fn validate_members(
  values: List(Member),
  seen: List(String),
  publication_date: String,
) -> Result(String, DecodeError) {
  case values {
    [] ->
      case publication_date == "" {
        True -> Error(InvalidPublicationDate(publication_date))
        False -> Ok(publication_date)
      }
    [member, ..rest] -> {
      use _ <- result.try(case valid_code(member.code) {
        True -> Ok(Nil)
        False -> Error(InvalidMemberIdentity(member.code))
      })
      use _ <- result.try(case list.contains(seen, member.code) {
        True -> Error(DuplicateMemberIdentity(member.code))
        False -> Ok(Nil)
      })
      use _ <- result.try(case string.trim(member.name) == "" {
        True -> Error(EmptyName(member.code))
        False -> Ok(Nil)
      })
      use _ <- result.try(validate_date(member.publication_date))
      let expected_date = case publication_date {
        "" -> member.publication_date
        value -> value
      }
      use _ <- result.try(case member.publication_date == expected_date {
        True -> Ok(Nil)
        False ->
          Error(ConflictingPublicationDate(
            expected_date,
            member.publication_date,
          ))
      })
      validate_members(rest, [member.code, ..seen], expected_date)
    }
  }
}

fn validate_date(value: String) -> Result(Nil, DecodeError) {
  case string.split(value, "-") {
    [year, month, day] ->
      case int.parse(year), int.parse(month), int.parse(day) {
        Ok(year), Ok(month), Ok(day) ->
          case time.date(year, month, day) {
            Ok(_) -> Ok(Nil)
            Error(_) -> Error(InvalidPublicationDate(value))
          }
        _, _, _ -> Error(InvalidPublicationDate(value))
      }
    _ -> Error(InvalidPublicationDate(value))
  }
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 6
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) { string.contains("0123456789", character) })
  }
}
