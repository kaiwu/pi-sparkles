import finance_execution/tape_scenario
import finance_execution/tape_scenario_decode.{type Input, EventInput, Input}
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

const hash_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const hash_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const hash_c = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

pub fn external_packet_drives_named_non_executing_possible_fill_model_test() {
  let assert Ok(value) = tape_scenario.run(input("futu", "cn"), "cn", None)
  let text = value |> tape_scenario.details |> json.to_string
  text
  |> string.contains("\"model\":\"transaction_tape_possible_fill_v1\"")
  |> should.be_true
  text
  |> string.contains("\"compatibleFillQuantity\":\"100\"")
  |> should.be_true
  text |> string.contains("\"kind\":\"compatible_non_fill\"") |> should.be_true
  text |> string.contains("\"fillObserved\":false") |> should.be_true
  text |> string.contains("\"networkPerformed\":false") |> should.be_true
}

pub fn provider_track_and_instruction_window_fail_closed_test() {
  tape_scenario.run(input("alpaca", "us"), "us", Some("ibkr"))
  |> should.be_error
  tape_scenario.run(input("futu", "cn"), "hk", None) |> should.be_error
}

fn input(provider: String, track: String) -> Input {
  let #(mic, currency, timezone, listing, venue) = case track {
    "cn" -> #("XSHG", "CNY", "Asia/Shanghai", "CN.600000", "XSHG")
    _ -> #("XNAS", "USD", "America/New_York", "US.AAPL", "XNAS")
  }
  Input(
    "scenario-test",
    provider,
    track,
    listing,
    mic,
    "2026-08-14-regular",
    currency,
    timezone,
    "caller-owned-read-only",
    "fixture-only",
    hash_a,
    "provider_declared_complete",
    None,
    ["regular"],
    hash_b,
    "instruction-1",
    hash_c,
    hash_a,
    "buy",
    "100",
    "10.50",
    None,
    None,
    [hash_b],
    [hash_c],
    [venue],
    ["regular"],
    False,
    100,
    [
      EventInput(
        "e1",
        "t1",
        "10.00",
        "60",
        venue,
        ["regular"],
        Some(1000),
        Some(1001),
        1002,
        "listing",
        "1",
        hash_b,
      ),
      EventInput(
        "e2",
        "t2",
        "10.25",
        "90",
        venue,
        ["regular"],
        Some(1003),
        Some(1004),
        1005,
        "listing",
        "2",
        hash_c,
      ),
    ],
  )
}
