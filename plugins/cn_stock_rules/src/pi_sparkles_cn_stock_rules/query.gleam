import finance_cn_rules/official
import finance_core/time.{type Date}
import gleam/list
import gleam/result
import gleam/string

pub opaque type Plan {
  Plan(
    code: String,
    venue: official.Venue,
    board: official.Board,
    identity_evidence_id: String,
    on: Date,
  )
}

pub type QueryError {
  WrongTrack
  InvalidCode
  InvalidVenue
  InvalidBoard
  UnsupportedShareClass
  UnsupportedSecurityType
  UnsupportedStatus
  UnsupportedRegime
  InvalidIdentityEvidenceId
  InvalidProfile(official.ProfileError)
}

pub fn plan(
  track: String,
  code: String,
  venue: String,
  board: String,
  share_class: String,
  security_type: String,
  status: String,
  regime: String,
  identity_evidence_id: String,
  on: Date,
) -> Result(Plan, QueryError) {
  use _ <- result.try(case track {
    "cn" -> Ok(Nil)
    _ -> Error(WrongTrack)
  })
  use _ <- result.try(case valid_code(code) {
    True -> Ok(Nil)
    False -> Error(InvalidCode)
  })
  use venue <- result.try(venue_from_name(venue))
  use board <- result.try(board_from_name(board))
  use _ <- result.try(case share_class {
    "a_share" -> Ok(Nil)
    _ -> Error(UnsupportedShareClass)
  })
  use _ <- result.try(case security_type {
    "common_stock" -> Ok(Nil)
    _ -> Error(UnsupportedSecurityType)
  })
  use _ <- result.try(case status {
    "listed_normal" -> Ok(Nil)
    _ -> Error(UnsupportedStatus)
  })
  use _ <- result.try(case regime {
    "established_normal_equity" -> Ok(Nil)
    _ -> Error(UnsupportedRegime)
  })
  use _ <- result.try(case valid_evidence_id(identity_evidence_id) {
    True -> Ok(Nil)
    False -> Error(InvalidIdentityEvidenceId)
  })
  use _ <- result.try(
    official.established_equity(venue, board, on: on)
    |> result.map_error(InvalidProfile),
  )
  Ok(Plan(code, venue, board, identity_evidence_id, on))
}

pub fn run(value: Plan) -> Result(official.Profile, QueryError) {
  official.established_equity(value.venue, value.board, on: value.on)
  |> result.map_error(InvalidProfile)
}

pub fn code(value: Plan) -> String {
  value.code
}

pub fn venue(value: Plan) -> official.Venue {
  value.venue
}

pub fn board(value: Plan) -> official.Board {
  value.board
}

pub fn identity_evidence_id(value: Plan) -> String {
  value.identity_evidence_id
}

pub fn on(value: Plan) -> Date {
  value.on
}

fn venue_from_name(value: String) -> Result(official.Venue, QueryError) {
  case value {
    "sse" -> Ok(official.Sse)
    "szse" -> Ok(official.Szse)
    "bse" -> Ok(official.Bse)
    _ -> Error(InvalidVenue)
  }
}

fn board_from_name(value: String) -> Result(official.Board, QueryError) {
  case value {
    "main" -> Ok(official.MainBoard)
    "star" -> Ok(official.StarMarket)
    "chinext" -> Ok(official.ChiNext)
    "beijing" -> Ok(official.BeijingMarket)
    _ -> Error(InvalidBoard)
  }
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 6
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn valid_evidence_id(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 256
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
