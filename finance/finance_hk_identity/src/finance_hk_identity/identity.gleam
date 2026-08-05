import finance_core/currency.{type Currency}
import finance_core/identifier.{type InstrumentId, type Mic, type Resolution}
import finance_core/instrument.{type ListingStatus}
import finance_core/time.{type Date}
import finance_listing/alias.{type Alias}
import finance_listing/effective.{type Interval}
import finance_listing/listing.{type Key}
import finance_provenance/identity.{type EvidenceId}
import finance_track
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub type Board {
  MainBoard
  Gem
}

pub type ShareClass {
  OrdinaryShare
  DepositaryReceipt
}

pub opaque type Listing {
  Listing(
    key: Key,
    board: Board,
    share_class: ShareClass,
    currency: Currency,
    status: ListingStatus,
  )
}

pub type IdentityError {
  InvalidCode
  InvalidAlias(alias.AliasError)
}

pub fn new(
  instrument_id instrument_id: InstrumentId,
  code code: String,
  board board: Board,
  share_class share_class: ShareClass,
  currency currency: Currency,
  status status: ListingStatus,
) -> Result(Listing, IdentityError) {
  case valid_code(code) {
    False -> Error(InvalidCode)
    True -> {
      let assert Ok(symbol) = identifier.symbol(code)
      Ok(Listing(
        key: listing.new(
          track: finance_track.Hk,
          instrument_id: instrument_id,
          symbol: symbol,
          mic: venue_mic(),
        ),
        board: board,
        share_class: share_class,
        currency: currency,
        status: status,
      ))
    }
  }
}

pub fn key(value: Listing) -> Key {
  value.key
}

pub fn code(value: Listing) -> String {
  value.key
  |> listing.symbol
  |> identifier.symbol_value
}

pub fn board(value: Listing) -> Board {
  value.board
}

pub fn share_class(value: Listing) -> ShareClass {
  value.share_class
}

pub fn currency(value: Listing) -> Currency {
  value.currency
}

pub fn status(value: Listing) -> ListingStatus {
  value.status
}

pub fn venue_mic() -> Mic {
  let assert Ok(value) = identifier.mic("XHKG")
  value
}

pub fn resolve_code(
  code code: String,
  within listings: List(Listing),
) -> Result(Resolution(Listing), IdentityError) {
  case valid_code(code) {
    False -> Error(InvalidCode)
    True ->
      listings
      |> list.filter(fn(item) {
        item.key |> listing.symbol |> identifier.symbol_value == code
      })
      |> identifier.resolve
      |> Ok
  }
}

pub fn alias(
  listing listing: Listing,
  name name: String,
  language language: String,
  effective effective: Interval,
  evidence_id evidence_id: Option(EvidenceId),
) -> Result(Alias, IdentityError) {
  case
    alias.new(
      listing: listing.key,
      name: name,
      language: language,
      effective: effective,
      evidence_id: evidence_id,
    )
  {
    Ok(value) -> Ok(value)
    Error(error) -> Error(InvalidAlias(error))
  }
}

pub fn aliases_on(
  listing listing: Listing,
  aliases aliases: List(Alias),
  date date: Date,
) -> List(Alias) {
  aliases
  |> alias.active_on(date)
  |> list.filter(fn(value) { alias.listing(value) == listing.key })
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 5
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) { string.contains("0123456789", character) })
  }
}
