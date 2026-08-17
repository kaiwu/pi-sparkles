import finance_ohlcv/series_handoff
import finance_provenance/hash
import finance_provenance/identity
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

pub fn exact_session_handoff_round_trips_and_rehashes_test() {
  let assert Ok(value) = fixture()
  let encoded = value |> series_handoff.encode |> json.to_string
  let assert Ok(decoded) = json.parse(encoded, series_handoff.decoder())
  let assert Ok(verified) = series_handoff.verify(decoded)
  series_handoff.receipt(verified)
  |> should.equal(series_handoff.receipt(value))
  series_handoff.bars(verified) |> list.length |> should.equal(2)
  let assert Ok(expected) = hash.text(series_handoff.canonical_text(value))
  series_handoff.receipt(value)
  |> should.equal(identity.sha256_value(expected))
}

pub fn changed_exact_row_fails_the_stored_receipt_test() {
  let assert Ok(value) = fixture()
  let encoded = value |> series_handoff.encode |> json.to_string
  let changed =
    string.replace(encoded, "\"close\":\"10.8\"", "\"close\":\"99\"")
  let assert Ok(decoded) = json.parse(changed, series_handoff.decoder())
  series_handoff.verify(decoded)
  |> should.equal(Error(series_handoff.ReceiptMismatch))
}

fn fixture() {
  series_handoff.new(
    track: "hk",
    instrument_id: "00700",
    mic: "XHKG",
    timezone: "Asia/Hong_Kong",
    source_language: "zh-HK",
    price_unit: "HKD",
    volume_unit: "provider_defined_unknown",
    adjustment: "raw",
    provider: "fixture-provider",
    source_reference: "fixture://hk/00700",
    retrieved_at_unix_milliseconds: 1_770_000_000_000,
    source_cutoff_unix_milliseconds: None,
    entitlement: "fixture_local_analysis",
    limitations: ["fixture_only"],
    bars: [
      series_handoff.Bar(
        date: "2026-02-02",
        open: "10",
        high: "11",
        low: "9",
        close: "10.8",
        volume: "100",
        amount: "1080",
      ),
      series_handoff.Bar(
        date: "2026-02-03",
        open: "10.8",
        high: "12",
        low: "10",
        close: "11.5",
        volume: "120",
        amount: "1380",
      ),
    ],
  )
}
