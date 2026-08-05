import finance_core/currency.{type Currency}
import finance_core/identifier.{type InstrumentId, type Mic, type Resolution}
import finance_core/instrument.{type ListingStatus}
import finance_core/time.{type Date}
import finance_listing/alias.{type Alias}
import finance_listing/effective.{type Interval}
import finance_listing/listing.{type Key}
import finance_listing/relationship
import finance_provenance/identity.{type EvidenceId}
import finance_track
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub type Venue {
  Sse
  Szse
  Bse
}

pub type Board {
  SseMainBoard
  StarMarket
  SzseMainBoard
  ChiNext
  BeijingMarket
}

pub type ShareClass {
  AShare
  BShare
  Cdr
}

pub opaque type Listing {
  Listing(
    key: Key,
    venue: Venue,
    board: Board,
    share_class: ShareClass,
    currency: Currency,
    status: ListingStatus,
  )
}

pub type RelationshipKind {
  ABRelationship
  AHRelationship
  CdrUnderlying
}

pub opaque type Relationship {
  Relationship(kind: RelationshipKind, relationship: relationship.Relationship)
}

pub type IdentityError {
  InvalidCode
  BoardVenueMismatch(board: Board, venue: Venue)
  UnsupportedShareClass(share_class: ShareClass, venue: Venue)
  InvalidAlias(alias.AliasError)
  InvalidRelationship(relationship.RelationshipError)
  InvalidRelationshipEndpoints(kind: RelationshipKind)
}

pub fn new(
  instrument_id instrument_id: InstrumentId,
  code code: String,
  venue venue: Venue,
  board board: Board,
  share_class share_class: ShareClass,
  currency currency: Currency,
  status status: ListingStatus,
) -> Result(Listing, IdentityError) {
  case valid_code(code), venue_for_board(board) == venue, share_class, venue {
    False, _, _, _ -> Error(InvalidCode)
    _, False, _, _ -> Error(BoardVenueMismatch(board, venue))
    _, _, BShare, Bse -> Error(UnsupportedShareClass(BShare, Bse))
    True, True, _, _ -> {
      let assert Ok(symbol) = identifier.symbol(code)
      Ok(Listing(
        key: listing.new(
          track: finance_track.Cn,
          instrument_id: instrument_id,
          symbol: symbol,
          mic: venue_mic(venue),
        ),
        venue: venue,
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

pub fn venue(value: Listing) -> Venue {
  value.venue
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

pub fn venue_mic(venue: Venue) -> Mic {
  let value = case venue {
    Sse -> "XSHG"
    Szse -> "XSHE"
    Bse -> "XBSE"
  }
  let assert Ok(mic) = identifier.mic(value)
  mic
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

pub fn ab_relationship(
  first first: Listing,
  second second: Listing,
  effective effective: Interval,
  evidence_id evidence_id: Option(EvidenceId),
) -> Result(Relationship, IdentityError) {
  case
    { first.share_class == AShare && second.share_class == BShare }
    || { first.share_class == BShare && second.share_class == AShare }
  {
    False -> Error(InvalidRelationshipEndpoints(ABRelationship))
    True ->
      make_relationship(
        ABRelationship,
        first.key,
        second.key,
        effective,
        evidence_id,
      )
  }
}

pub fn ah_relationship(
  mainland mainland: Listing,
  hong_kong hong_kong: Key,
  effective effective: Interval,
  evidence_id evidence_id: Option(EvidenceId),
) -> Result(Relationship, IdentityError) {
  case
    mainland.share_class == AShare
    && listing.track(hong_kong) == finance_track.Hk
  {
    False -> Error(InvalidRelationshipEndpoints(AHRelationship))
    True ->
      make_relationship(
        AHRelationship,
        mainland.key,
        hong_kong,
        effective,
        evidence_id,
      )
  }
}

pub fn cdr_underlying(
  cdr cdr: Listing,
  underlying underlying: Key,
  effective effective: Interval,
  evidence_id evidence_id: Option(EvidenceId),
) -> Result(Relationship, IdentityError) {
  case cdr.share_class == Cdr {
    False -> Error(InvalidRelationshipEndpoints(CdrUnderlying))
    True ->
      make_relationship(
        CdrUnderlying,
        cdr.key,
        underlying,
        effective,
        evidence_id,
      )
  }
}

pub fn relationship_kind(value: Relationship) -> RelationshipKind {
  value.kind
}

pub fn relationship_value(value: Relationship) -> relationship.Relationship {
  value.relationship
}

fn make_relationship(
  kind: RelationshipKind,
  first: Key,
  second: Key,
  effective: Interval,
  evidence_id: Option(EvidenceId),
) -> Result(Relationship, IdentityError) {
  case
    relationship.new(
      kind: relationship_kind_name(kind),
      first: first,
      second: second,
      effective: effective,
      evidence_id: evidence_id,
    )
  {
    Ok(value) -> Ok(Relationship(kind, value))
    Error(error) -> Error(InvalidRelationship(error))
  }
}

fn relationship_kind_name(value: RelationshipKind) -> String {
  case value {
    ABRelationship -> "cn_ab_share"
    AHRelationship -> "cn_hk_ah_share"
    CdrUnderlying -> "cn_cdr_underlying"
  }
}

fn venue_for_board(value: Board) -> Venue {
  case value {
    SseMainBoard | StarMarket -> Sse
    SzseMainBoard | ChiNext -> Szse
    BeijingMarket -> Bse
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
