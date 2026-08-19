import finance_core/decimal
import finance_core/time
import finance_sse_index/query.{type Query}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub opaque type Sector {
  Sector(
    code: String,
    name: String,
    english_name: String,
    security_count: Int,
    weight_raw: String,
    effective_date: String,
  )
}

pub opaque type Composition {
  Composition(effective_date: String, sectors: List(Sector))
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  EmptyComposition
  InvalidIndexIdentity(String)
  InvalidSector(String)
  DuplicateSector(String)
  InvalidSecurityCount(String)
  MemberCountMismatch(expected: Int, received: Int)
  InvalidWeight(String)
  InvalidEffectiveDate(String)
  ConflictingEffectiveDate(expected: String, received: String)
}

pub fn decode(
  body: String,
  for query: Query,
) -> Result(Composition, DecodeError) {
  use rows <- result.try(
    body
    |> normalize_numbers
    |> json.parse(payload_decoder())
    |> result.map_error(InvalidJson),
  )
  use effective_date <- result.try(validate(rows, query, [], "", 0))
  Ok(Composition(effective_date, rows))
}

pub fn effective_date(value: Composition) -> String {
  value.effective_date
}

pub fn sectors(value: Composition) -> List(Sector) {
  value.sectors
}

pub fn code(value: Sector) -> String {
  value.code
}

pub fn name(value: Sector) -> String {
  value.name
}

pub fn english_name(value: Sector) -> String {
  value.english_name
}

pub fn security_count(value: Sector) -> Int {
  value.security_count
}

pub fn weight_raw(value: Sector) -> String {
  value.weight_raw
}

fn payload_decoder() -> decode.Decoder(List(Sector)) {
  use rows <- decode.field("result", decode.list(of: sector_decoder()))
  decode.success(rows)
}

fn sector_decoder() -> decode.Decoder(Sector) {
  use security_count_raw <- decode.field("securityNum", number_decoder())
  use code <- decode.field("level1Code", decode.string)
  use name <- decode.field("level1Name", decode.string)
  use index_code <- decode.field("indexCode", decode.string)
  use weight_raw <- decode.field("weight", number_decoder())
  use english_name <- decode.field("level1NameEn", decode.string)
  use effective_date <- decode.field("effectiveDate", decode.string)
  case int.parse(security_count_raw) {
    Error(_) ->
      decode.failure(
        Sector(code, name, english_name, 0, weight_raw, effective_date),
        "integer SSE sector security count",
      )
    Ok(security_count) ->
      decode.success(#(
        index_code,
        Sector(
          code,
          name,
          english_name,
          security_count,
          weight_raw,
          effective_date,
        ),
      ))
      |> decode.then(fn(value) {
        let #(decoded_index_code, sector) = value
        case decoded_index_code == "000688" {
          True -> decode.success(sector)
          False -> decode.failure(sector, "reviewed SSE index identity")
        }
      })
  }
}

fn validate(
  values: List(Sector),
  query: Query,
  seen: List(String),
  effective_date: String,
  member_count: Int,
) -> Result(String, DecodeError) {
  case values {
    [] ->
      case seen, member_count == query.expected_members(query) {
        [], _ -> Error(EmptyComposition)
        _, False ->
          Error(MemberCountMismatch(query.expected_members(query), member_count))
        _, True -> Ok(effective_date)
      }
    [sector, ..rest] -> {
      use _ <- result.try(
        case
          string.trim(sector.code) != ""
          && string.trim(sector.name) != ""
          && string.trim(sector.english_name) != ""
        {
          True -> Ok(Nil)
          False -> Error(InvalidSector(sector.code))
        },
      )
      use _ <- result.try(case list.contains(seen, sector.code) {
        True -> Error(DuplicateSector(sector.code))
        False -> Ok(Nil)
      })
      use _ <- result.try(case sector.security_count > 0 {
        True -> Ok(Nil)
        False -> Error(InvalidSecurityCount(sector.code))
      })
      use _ <- result.try(
        decimal.parse(sector.weight_raw)
        |> result.map_error(fn(_) { InvalidWeight(sector.code) }),
      )
      use _ <- result.try(validate_compact_date(sector.effective_date))
      let expected_date = case effective_date {
        "" -> sector.effective_date
        value -> value
      }
      use _ <- result.try(case sector.effective_date == expected_date {
        True -> Ok(Nil)
        False ->
          Error(ConflictingEffectiveDate(expected_date, sector.effective_date))
      })
      validate(
        rest,
        query,
        [sector.code, ..seen],
        expected_date,
        member_count + sector.security_count,
      )
    }
  }
}

fn validate_compact_date(value: String) -> Result(Nil, DecodeError) {
  case
    string.length(value) == 8,
    int.parse(string.slice(value, 0, 4)),
    int.parse(string.slice(value, 4, 2)),
    int.parse(string.slice(value, 6, 2))
  {
    True, Ok(year), Ok(month), Ok(day) ->
      case time.date(year, month, day) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error(InvalidEffectiveDate(value))
      }
    _, _, _, _ -> Error(InvalidEffectiveDate(value))
  }
}

fn number_decoder() -> decode.Decoder(String) {
  decode.at(["__finance_sse_index_number__"], decode.string)
}

@external(javascript, "./composition_ffi.mjs", "normalize_numbers")
fn normalize_numbers(source: String) -> String
