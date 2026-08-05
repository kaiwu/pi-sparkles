import finance_cn_rules/official
import finance_core/time.{type Date}
import gleam/result

pub type QueryError {
  InvalidVenue
  InvalidBoard
  InvalidRegime
  InvalidProfile(official.ProfileError)
}

pub fn venue_from_name(value: String) -> Result(official.Venue, QueryError) {
  case value {
    "sse" -> Ok(official.Sse)
    "szse" -> Ok(official.Szse)
    "bse" -> Ok(official.Bse)
    _ -> Error(InvalidVenue)
  }
}

pub fn board_from_name(value: String) -> Result(official.Board, QueryError) {
  case value {
    "main" -> Ok(official.MainBoard)
    "star" -> Ok(official.StarMarket)
    "chinext" -> Ok(official.ChiNext)
    "beijing" -> Ok(official.BeijingMarket)
    _ -> Error(InvalidBoard)
  }
}

pub fn run(
  venue venue_value: official.Venue,
  board board_value: official.Board,
  regime regime_value: String,
  on date: Date,
) -> Result(official.Profile, QueryError) {
  case regime_value {
    "established_normal_equity" ->
      official.established_equity(venue_value, board_value, on: date)
      |> result.map_error(InvalidProfile)
    _ -> Error(InvalidRegime)
  }
}
