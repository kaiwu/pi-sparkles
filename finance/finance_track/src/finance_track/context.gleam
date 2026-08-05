import finance_core/identifier.{type Mic}
import finance_core/time.{type Timezone}
import finance_track.{type Track}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Common user-visible context for one market-specific result.
///
/// Source observations and evidence retain their richer metadata separately.
/// This context prevents a result from losing which market contract produced
/// it. Cross-track results contain multiple contexts rather than constructing a
/// synthetic fourth track.
pub opaque type Context {
  Context(
    track: Track,
    market_scope: String,
    venue_mic: Option(Mic),
    board: Option(String),
    timezone: Option(Timezone),
    source_language: String,
    providers: List(String),
    entitlement: String,
    limitations: List(String),
  )
}

/// One explicitly labelled input or output in a cross-track composition.
///
/// A cross-market workflow retains a list of these legs; it never invents a
/// synthetic `global` track or strips the individual contexts.
pub type Leg(value) {
  Leg(context: Context, value: value)
}

pub type ContextError {
  InvalidMarketScope
  MarketScopeTrackMismatch(expected_prefix: String)
  InvalidBoard
  BoardRequiresVenue
  InvalidSourceLanguage
  MissingProvider
  InvalidProvider
  DuplicateProvider(provider: String)
  InvalidEntitlement
  InvalidLimitation
  DuplicateLimitation(limitation: String)
}

pub fn new(
  track track: Track,
  market_scope market_scope: String,
  venue_mic venue_mic: Option(Mic),
  board board: Option(String),
  timezone timezone: Option(Timezone),
  source_language source_language: String,
  providers providers: List(String),
  entitlement entitlement: String,
  limitations limitations: List(String),
) -> Result(Context, ContextError) {
  use _ <- result.try(validate_market_scope(track, market_scope))
  use _ <- result.try(validate_board(board, venue_mic))
  use _ <- result.try(validate_source_language(source_language))
  use _ <- result.try(validate_providers(providers, []))
  use _ <- result.try(validate_entitlement(entitlement))
  use _ <- result.try(validate_limitations(limitations, []))
  Ok(Context(
    track,
    market_scope,
    venue_mic,
    board,
    timezone,
    source_language,
    providers,
    entitlement,
    limitations,
  ))
}

pub fn track(context: Context) -> Track {
  context.track
}

pub fn market_scope(context: Context) -> String {
  context.market_scope
}

pub fn venue_mic(context: Context) -> Option(Mic) {
  context.venue_mic
}

pub fn board(context: Context) -> Option(String) {
  context.board
}

pub fn timezone(context: Context) -> Option(Timezone) {
  context.timezone
}

pub fn source_language(context: Context) -> String {
  context.source_language
}

pub fn providers(context: Context) -> List(String) {
  context.providers
}

pub fn entitlement(context: Context) -> String {
  context.entitlement
}

pub fn limitations(context: Context) -> List(String) {
  context.limitations
}

pub fn leg(context: Context, value: value) -> Leg(value) {
  Leg(context, value)
}

pub fn map_leg(
  leg: Leg(value),
  with transform: fn(value) -> mapped,
) -> Leg(mapped) {
  Leg(leg.context, transform(leg.value))
}

fn validate_market_scope(
  track: Track,
  market_scope: String,
) -> Result(Nil, ContextError) {
  case valid_identifier(market_scope) {
    False -> Error(InvalidMarketScope)
    True -> {
      let prefix = finance_track.name(track) <> "_"
      case string.starts_with(market_scope, prefix) {
        True -> Ok(Nil)
        False -> Error(MarketScopeTrackMismatch(prefix))
      }
    }
  }
}

fn validate_board(
  board: Option(String),
  venue_mic: Option(Mic),
) -> Result(Nil, ContextError) {
  case board, venue_mic {
    None, _ -> Ok(Nil)
    Some(_), None -> Error(BoardRequiresVenue)
    Some(value), Some(_) ->
      case valid_text(value) {
        True -> Ok(Nil)
        False -> Error(InvalidBoard)
      }
  }
}

fn validate_source_language(value: String) -> Result(Nil, ContextError) {
  case
    value != ""
    && string.length(value) <= 35
    && {
      value
      |> string.to_graphemes
      |> list.all(fn(character) {
        string.contains(
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-",
          character,
        )
      })
    }
  {
    True -> Ok(Nil)
    False -> Error(InvalidSourceLanguage)
  }
}

fn validate_providers(
  providers: List(String),
  seen: List(String),
) -> Result(Nil, ContextError) {
  case providers, seen {
    [], [] -> Error(MissingProvider)
    [], _ -> Ok(Nil)
    [provider, ..rest], seen ->
      case valid_text(provider), list.contains(seen, provider) {
        False, _ -> Error(InvalidProvider)
        _, True -> Error(DuplicateProvider(provider))
        True, False -> validate_providers(rest, [provider, ..seen])
      }
  }
}

fn validate_entitlement(value: String) -> Result(Nil, ContextError) {
  case valid_identifier(value) {
    True -> Ok(Nil)
    False -> Error(InvalidEntitlement)
  }
}

fn validate_limitations(
  limitations: List(String),
  seen: List(String),
) -> Result(Nil, ContextError) {
  case limitations {
    [] -> Ok(Nil)
    [limitation, ..rest] ->
      case valid_identifier(limitation), list.contains(seen, limitation) {
        False, _ -> Error(InvalidLimitation)
        _, True -> Error(DuplicateLimitation(limitation))
        True, False -> validate_limitations(rest, [limitation, ..seen])
      }
  }
}

fn valid_identifier(value: String) -> Bool {
  value != ""
  && string.length(value) <= 200
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  }
}

fn valid_text(value: String) -> Bool {
  value != ""
  && string.length(value) <= 200
  && string.trim(value) == value
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
  && !string.contains(value, "\t")
}
