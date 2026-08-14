import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_tape/decode
import pi_sparkles_stock_tape/domain

const hash_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const hash_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

pub fn main() {
  gleeunit.main()
}

pub fn exact_three_track_scope_and_external_provider_boundary_test() {
  let assert Ok(cn) = domain.run(input("cn", "XSHG", [trade("e1", "10", 100)]))
  let assert Ok(hk) = domain.run(input("hk", "XHKG", [trade("e1", "10", 100)]))
  let assert Ok(us) = domain.run(input("us", "XNAS", [trade("e1", "10", 100)]))

  contains(details(cn), "\"track\":\"cn\"")
  contains(details(hk), "\"track\":\"hk\"")
  contains(details(us), "\"track\":\"us\"")
  contains(details(us), "\"dependencyMode\":\"explicit_external_capability\"")
  contains(details(us), "\"openDRequiredByPackage\":false")
  contains(details(us), "\"adapterBundled\":false")
  contains(details(us), "\"networkPerformed\":false")
}

pub fn sequence_gap_correction_and_clock_facts_are_projected_test() {
  let correction =
    decode.EventInput(
      ..trade("e2", "12", 110),
      trade_id: "t2",
      kind: decode.EventKindInput("correction", Some("e1"), Some("t1")),
    )
  let assert Ok(response) =
    domain.run(input("hk", "XHKG", [trade("e1", "10", 100), correction]))
  let text = details(response)

  contains(text, "\"kind\":\"gap\"")
  contains(text, "\"expected\":\"11\"")
  contains(text, "\"state\":\"correction\"")
  contains(text, "\"exchangeToProviderMilliseconds\":1")
  contains(text, "\"providerToRetrievalMilliseconds\":1")
  contains(text, "\"latencyClaimed\":false")
}

pub fn later_lineage_references_remain_review_facts_test() {
  let missing =
    decode.EventInput(
      ..trade("e1", "1", 100),
      kind: decode.EventKindInput("cancel", Some("later"), None),
    )
  let later = trade("later", "2", 110)
  let assert Ok(response) = domain.run(input("us", "XNYS", [missing, later]))
  let text = details(response)

  contains(text, "\"kind\":\"reference_occurs_later\"")
  contains(text, "mechanical_tape_review_only_no_trading_judgment")
  contains(text, "\"executable\":false")
}

pub fn wrong_track_mic_and_invalid_provider_receipt_fail_closed_test() {
  case domain.run(input("cn", "XNAS", [trade("e1", "1", 100)])) {
    Error(domain.InvalidField("mic", _)) -> Nil
    _ -> should.fail()
  }

  let base = input("hk", "XHKG", [trade("e1", "1", 100)])
  case domain.run(decode.Input(..base, provider_receipt_hash: "bad")) {
    Error(domain.InvalidField("providerReceiptHash", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn stable_paging_and_receipt_test() {
  let base =
    input("us", "XNAS", [
      trade("e1", "1", 100),
      trade("e2", "2", 110),
    ])
  let assert Ok(response) =
    domain.run(decode.Input(..base, page: decode.PageInput(1, 1)))
  let text = details(response)

  contains(text, "\"returned\":1")
  contains(text, "\"total\":2")
  contains(text, "\"nextOffset\":null")
  contains(text, "\"eventId\":\"e2\"")
  contains(text, "\"tapeReceiptHash\":\"")
}

fn input(
  track: String,
  mic: String,
  events: List(decode.EventInput),
) -> decode.Input {
  decode.Input(
    track,
    "listing:fixture",
    mic,
    "session:2026-08-14",
    "fixture-provider",
    "fixture-transaction-ticker",
    "caller_owned_read_only",
    "internal_test_only",
    hash_a,
    decode.CoverageInput(
      "bounded_partial",
      None,
      Some("bounded fixture window"),
    ),
    decode.ConditionCoverageInput("documented", ["regular"], Some(hash_b), None),
    100,
    events,
    decode.PageInput(0, 100),
  )
}

fn trade(
  event_id: String,
  sequence: String,
  retrieved: Int,
) -> decode.EventInput {
  decode.EventInput(
    event_id,
    "t1",
    decode.EventKindInput("original", None, None),
    decode.LexemeInput("known", Some("10.5000"), [], None),
    decode.LexemeInput("known", Some("100"), [], None),
    ["regular"],
    "fixture-venue",
    decode.ClocksInput(Some(retrieved - 2), Some(retrieved - 1), retrieved),
    decode.SequenceInput(
      "sequenced",
      Some("listing"),
      Some(sequence),
      [],
      None,
      None,
    ),
    hash_b,
  )
}

fn details(response: domain.Response) -> String {
  response |> domain.details |> json.to_string
}

fn contains(value: String, expected: String) {
  value |> string.contains(expected) |> should.be_true
}
