import finance_indicators/chart_handoff
import finance_provenance/hash
import finance_provenance/identity
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

pub fn chart_handoff_round_trips_and_rehashes_test() {
  let assert Ok(value) = fixture()
  let encoded = value |> chart_handoff.encode |> json.to_string
  let assert Ok(decoded) = json.parse(encoded, chart_handoff.decoder())
  let assert Ok(verified) = chart_handoff.verify(decoded)
  chart_handoff.handoff_receipt(verified)
  |> should.equal(chart_handoff.handoff_receipt(value))
  chart_handoff.points(verified) |> list.length |> should.equal(3)
  let assert Ok(expected) = hash.text(chart_handoff.canonical_text(value))
  chart_handoff.handoff_receipt(value)
  |> should.equal(identity.sha256_value(expected))
}

pub fn changed_indicator_point_fails_the_stored_receipt_test() {
  let assert Ok(value) = fixture()
  let encoded = value |> chart_handoff.encode |> json.to_string
  let changed =
    string.replace(encoded, "\"value\":\"11.5\"", "\"value\":\"99\"")
  let assert Ok(decoded) = json.parse(changed, chart_handoff.decoder())
  chart_handoff.verify(decoded)
  |> should.equal(Error(chart_handoff.ReceiptMismatch))
}

fn fixture() {
  chart_handoff.new(
    series_receipt: string.repeat("1", 64),
    calculation_receipt: string.repeat("2", 64),
    indicator_id: "sma_2",
    label: "SMA 2",
    panel: "price_overlay",
    unit: "HKD",
    warmup_sessions: 1,
    points: [
      chart_handoff.Unperformed("2026-02-02", "insufficient_inputs"),
      chart_handoff.Calculated("2026-02-03", "11.0"),
      chart_handoff.Calculated("2026-02-04", "11.5"),
    ],
  )
}
