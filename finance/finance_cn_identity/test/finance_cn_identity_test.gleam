import finance_cn_identity
import finance_cn_identity/identity as cn
import finance_core/currency
import finance_core/identifier
import finance_core/instrument
import finance_core/time
import finance_listing/alias
import finance_listing/effective
import finance_listing/listing
import finance_listing/relationship
import finance_track
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_cn_identity.status()
  |> should.equal(finance_cn_identity.Experimental)
}

pub fn bare_000001_remains_ambiguous_across_venues_test() {
  let shanghai =
    cn_listing("synthetic-sh", "000001", cn.Sse, cn.SseMainBoard, cn.AShare)
  let shenzhen =
    cn_listing("synthetic-sz", "000001", cn.Szse, cn.SzseMainBoard, cn.AShare)

  cn.resolve_code("000001", within: [shanghai, shenzhen])
  |> should.equal(Ok(identifier.Ambiguous(shanghai, shenzhen, [])))
}

pub fn listing_requires_explicit_compatible_venue_and_board_test() {
  cn.new(
    instrument_id: instrument_id("synthetic"),
    code: "000001",
    venue: cn.Sse,
    board: cn.ChiNext,
    share_class: cn.AShare,
    currency: currency("CNY"),
    status: instrument.Active,
  )
  |> should.equal(Error(cn.BoardVenueMismatch(cn.ChiNext, cn.Sse)))
  cn.resolve_code("1", within: []) |> should.equal(Error(cn.InvalidCode))
}

pub fn historical_aliases_are_selected_by_effective_date_test() {
  let listing =
    cn_listing("synthetic-name", "600001", cn.Sse, cn.SseMainBoard, cn.AShare)
  let assert Ok(old_interval) =
    effective.new(start: date(2020, 1, 1), end: Some(date(2022, 12, 31)))
  let assert Ok(current_interval) =
    effective.new(start: date(2023, 1, 1), end: None)
  let assert Ok(old_name) =
    cn.alias(
      listing: listing,
      name: "合成旧名称",
      language: "zh-CN",
      effective: old_interval,
      evidence_id: None,
    )
  let assert Ok(current_name) =
    cn.alias(
      listing: listing,
      name: "合成新名称",
      language: "zh-CN",
      effective: current_interval,
      evidence_id: None,
    )

  cn.aliases_on(
    listing,
    aliases: [old_name, current_name],
    date: date(2021, 6, 1),
  )
  |> should.equal([old_name])
  alias.name(old_name) |> should.equal("合成旧名称")
}

pub fn ah_relationship_retains_independent_cn_and_hk_keys_test() {
  let mainland =
    cn_listing("synthetic-ah", "600002", cn.Sse, cn.SseMainBoard, cn.AShare)
  let hk = hk_key("synthetic-ah", "00002")
  let assert Ok(interval) = effective.new(start: date(2024, 1, 1), end: None)
  let assert Ok(link) =
    cn.ah_relationship(
      mainland: mainland,
      hong_kong: hk,
      effective: interval,
      evidence_id: None,
    )
  let value = cn.relationship_value(link)

  cn.relationship_kind(link) |> should.equal(cn.AHRelationship)
  relationship.first(value) |> listing.track |> should.equal(finance_track.Cn)
  relationship.second(value) |> listing.track |> should.equal(finance_track.Hk)
}

pub fn ab_relationship_requires_complementary_share_classes_test() {
  let first =
    cn_listing("synthetic-a", "600003", cn.Sse, cn.SseMainBoard, cn.AShare)
  let second =
    cn_listing("synthetic-a2", "600004", cn.Sse, cn.SseMainBoard, cn.AShare)
  let assert Ok(interval) = effective.new(start: date(2024, 1, 1), end: None)

  cn.ab_relationship(
    first: first,
    second: second,
    effective: interval,
    evidence_id: None,
  )
  |> should.equal(Error(cn.InvalidRelationshipEndpoints(cn.ABRelationship)))
}

fn cn_listing(
  id: String,
  code: String,
  venue: cn.Venue,
  board: cn.Board,
  share_class: cn.ShareClass,
) -> cn.Listing {
  let assert Ok(value) =
    cn.new(
      instrument_id: instrument_id(id),
      code: code,
      venue: venue,
      board: board,
      share_class: share_class,
      currency: currency("CNY"),
      status: instrument.Active,
    )
  value
}

fn hk_key(id: String, code: String) -> listing.Key {
  let assert Ok(symbol) = identifier.symbol(code)
  let assert Ok(mic) = identifier.mic("XHKG")
  listing.new(
    track: finance_track.Hk,
    instrument_id: instrument_id(id),
    symbol: symbol,
    mic: mic,
  )
}

fn instrument_id(value: String) -> identifier.InstrumentId {
  let assert Ok(value) = identifier.instrument_id(value)
  value
}

fn currency(value: String) -> currency.Currency {
  let assert Ok(value) = currency.from_code(value)
  value
}

fn date(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
