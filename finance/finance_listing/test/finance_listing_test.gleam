import finance_core/identifier
import finance_core/time
import finance_listing
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
  finance_listing.status() |> should.equal(finance_listing.Experimental)
}

pub fn listing_key_never_loses_track_or_venue_test() {
  let key = key(finance_track.Cn, "issuer-a", "000001", "XSHG")
  listing.track(key) |> should.equal(finance_track.Cn)
  listing.mic(key) |> identifier.mic_value |> should.equal("XSHG")
}

pub fn effective_intervals_are_inclusive_and_validated_test() {
  let assert Ok(interval) =
    effective.new(start: date(2020, 1, 1), end: Some(date(2020, 12, 31)))
  effective.contains(interval, date(2020, 1, 1)) |> should.be_true
  effective.contains(interval, date(2020, 12, 31)) |> should.be_true
  effective.contains(interval, date(2021, 1, 1)) |> should.be_false
  effective.new(start: date(2021, 1, 1), end: Some(date(2020, 1, 1)))
  |> should.equal(Error(effective.EndBeforeStart))
}

pub fn aliases_and_relationships_retain_scope_test() {
  let cn = key(finance_track.Cn, "issuer-a", "000001", "XSHG")
  let hk = key(finance_track.Hk, "issuer-a", "00001", "XHKG")
  let assert Ok(interval) = effective.new(start: date(2020, 1, 1), end: None)
  let assert Ok(old_name) =
    alias.new(
      listing: cn,
      name: "合成旧名",
      language: "zh-CN",
      effective: interval,
      evidence_id: None,
    )
  alias.name(old_name) |> should.equal("合成旧名")

  let assert Ok(link) =
    relationship.new(
      kind: "synthetic_cross_listing",
      first: cn,
      second: hk,
      effective: interval,
      evidence_id: None,
    )
  relationship.first(link) |> should.equal(cn)
  relationship.second(link) |> should.equal(hk)
  relationship.new(
    kind: "synthetic_cross_listing",
    first: cn,
    second: cn,
    effective: interval,
    evidence_id: None,
  )
  |> should.equal(Error(relationship.SameListing))
}

fn key(
  track: finance_track.Track,
  id: String,
  symbol: String,
  mic: String,
) -> listing.Key {
  let assert Ok(id) = identifier.instrument_id(id)
  let assert Ok(symbol) = identifier.symbol(symbol)
  let assert Ok(mic) = identifier.mic(mic)
  listing.new(track: track, instrument_id: id, symbol: symbol, mic: mic)
}

fn date(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
