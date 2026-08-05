import finance_core/currency
import finance_core/identifier
import finance_core/instrument
import finance_hk_identity
import finance_hk_identity/identity as hk
import finance_listing/listing
import finance_track
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_hk_identity.status()
  |> should.equal(finance_hk_identity.Experimental)
}

pub fn listing_is_always_hk_scoped_and_retains_leading_zeroes_test() {
  let value = listing("synthetic-hk", "00001")
  hk.code(value) |> should.equal("00001")
  hk.key(value) |> listing.track |> should.equal(finance_track.Hk)
  hk.key(value) |> listing.mic |> identifier.mic_value |> should.equal("XHKG")
}

pub fn bare_unpadded_code_is_rejected_test() {
  hk.new(
    instrument_id: instrument_id("synthetic"),
    code: "1",
    board: hk.MainBoard,
    share_class: hk.OrdinaryShare,
    currency: currency("HKD"),
    status: instrument.Active,
  )
  |> should.equal(Error(hk.InvalidCode))
}

pub fn exact_resolution_never_selects_the_first_duplicate_test() {
  let first = listing("synthetic-hk-a", "00002")
  let second = listing("synthetic-hk-b", "00002")
  hk.resolve_code("00002", within: [first, second])
  |> should.equal(Ok(identifier.Ambiguous(first, second, [])))
}

fn listing(id: String, code: String) -> hk.Listing {
  let assert Ok(value) =
    hk.new(
      instrument_id: instrument_id(id),
      code: code,
      board: hk.MainBoard,
      share_class: hk.OrdinaryShare,
      currency: currency("HKD"),
      status: instrument.Active,
    )
  value
}

fn instrument_id(value: String) -> identifier.InstrumentId {
  let assert Ok(value) = identifier.instrument_id(value)
  value
}

fn currency(value: String) -> currency.Currency {
  let assert Ok(value) = currency.from_code(value)
  value
}
