import finance_core/currency
import finance_core/decimal
import finance_core/time
import finance_ohlcv
import finance_ohlcv/acquisition_attempt
import finance_ohlcv/acquisition_receipt
import finance_ohlcv/evidence_packet
import finance_ohlcv/fact
import finance_ohlcv/quantity
import finance_ohlcv/reported_row
import finance_ohlcv/rights
import finance_ohlcv/timing
import finance_provenance/identity
import finance_track
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

pub fn fact_states_map_without_becoming_verdicts_test() {
  fact.Known(2)
  |> fact.map(fn(value) { value * 3 })
  |> should.equal(fact.Known(6))
  fact.Unknown("provider_did_not_report")
  |> fact.map(fn(value: Int) { value * 3 })
  |> should.equal(fact.Unknown("provider_did_not_report"))
  fact.Conflicting([1, 2])
  |> fact.values
  |> should.equal([1, 2])
}

pub fn reported_rows_preserve_parseable_values_and_mechanical_facts_test() {
  let row =
    reported_row.inspect(
      open: "10",
      high: "9",
      low: "8",
      close: "10",
      volume: "-5",
    )
  let checks = reported_row.checks(row)
  reported_row.high_ge_max(checks) |> should.equal(fact.Known(False))
  reported_row.volume_non_negative(checks)
  |> should.equal(fact.Known(False))
  let assert fact.Known(volume) =
    row |> reported_row.volume |> reported_row.parsed
  decimal.to_string(volume) |> should.equal("-5")
  row |> reported_row.volume |> reported_row.raw |> should.equal("-5")
}

pub fn decode_failures_preserve_raw_lexemes_and_unperformed_checks_test() {
  let row =
    reported_row.inspect(
      open: "not-a-decimal",
      high: "11",
      low: "9",
      close: "10",
      volume: "100",
    )
  row
  |> reported_row.open
  |> reported_row.parsed
  |> should.equal(fact.DecodeFailure("not-a-decimal", "invalid_decimal"))
  row
  |> reported_row.checks
  |> reported_row.high_ge_max
  |> should.equal(fact.NotObtained("price_field_not_decoded"))
}

pub fn timing_comparison_records_the_instruction_and_inputs_test() {
  let value = timing_facts(fact.Known(instant(300)))
  let assert fact.Known(receipt) =
    timing.retrieval_before_next_open(value, "llm-turn-42")
  timing.comparison_name(receipt)
  |> should.equal("retrieval_before_next_open")
  timing.comparison_instruction_reference(receipt)
  |> should.equal("llm-turn-42")
  timing.comparison_result(receipt) |> should.be_true

  timing_facts(fact.Unknown("calendar_not_obtained"))
  |> timing.retrieval_before_next_open("llm-turn-43")
  |> should.equal(fact.NotObtained(
    "next_session_open_unknown:calendar_not_obtained",
  ))
}

pub fn rights_keep_unknown_predicates_unknown_test() {
  let value = unknown_rights()
  rights.attribution_required(value)
  |> should.equal(rights.UnknownPredicate("terms_not_obtained"))
  rights.redistribution(value)
  |> should.equal(rights.UnknownPredicate("terms_not_obtained"))
  rights.provider(value) |> should.equal(fact.Known("fixture-provider"))
}

pub fn acquisition_attempt_canonical_text_binds_outcome_and_budgets_test() {
  let receipt = acquisition()
  let complete =
    acquisition_attempt.new(
      receipt: fact.Known(receipt),
      outcome: acquisition_attempt.TransportComplete,
      budgets: [acquisition_attempt.PageBudget(5)],
      partial_bar_dates: [civil(2026, 6, 18)],
    )
  let cancelled =
    acquisition_attempt.new(
      receipt: fact.Known(receipt),
      outcome: acquisition_attempt.CancelledByCaller(instant(400)),
      budgets: [acquisition_attempt.PageBudget(2)],
      partial_bar_dates: [civil(2026, 6, 18)],
    )
  let complete_text = acquisition_attempt.canonical_text(complete)
  let cancelled_text = acquisition_attempt.canonical_text(cancelled)
  complete_text |> string.contains("transport_complete") |> should.be_true
  cancelled_text |> string.contains("cancelled_by_caller") |> should.be_true
  complete_text |> should.not_equal(cancelled_text)
}

pub fn evidence_packet_retains_unknowns_and_available_operations_test() {
  let assert Ok(usd) = currency.from_code("USD")
  let row = reported_row.inspect("10", "11", "9", "10.5", "unknown-volume")
  let quantity =
    quantity.inspect(
      "unknown-volume",
      fact.Unknown("provider_unit_not_documented"),
      [],
    )
  let identity =
    evidence_packet.identity(
      finance_track.Us,
      instrument_id: fact.Unknown("resolver_not_called"),
      symbol: fact.Known("TEST"),
      mic: fact.Known("XNAS"),
      currency: fact.Known(usd),
      evidence_root: fact.NotObtained("listing_receipt_not_obtained"),
    )
  let session =
    evidence_packet.session(
      civil(2026, 6, 18),
      venue_state: fact.Known(evidence_packet.Open),
      listing_effective: fact.Unknown("listing_receipt_not_obtained"),
      security_status: fact.Unknown("status_receipt_not_obtained"),
      descriptive_classification: fact.NotObtained(
        "classification_inputs_missing",
      ),
      classification_rule: fact.Known("finance_ohlcv/session-facts-v1"),
    )
  let packet =
    evidence_packet.new(
      identity,
      session,
      provider_row: fact.Known(row),
      acquisition: fact.NotObtained("receipt_not_obtained"),
      timing: timing_facts(fact.Unknown("calendar_not_obtained")),
      adjustment: fact.Unknown("provider_did_not_declare"),
      quantity: quantity,
      rights: unknown_rights(),
      quality: fact.Known(evidence_packet.Reported),
      evidence_roots: [
        evidence_packet.evidence_root("provider", "fixture://response/1"),
      ],
      available_operations: [
        evidence_packet.DrillProvenance,
        evidence_packet.RequestCalculation,
      ],
    )
  packet
  |> evidence_packet.packet_identity
  |> evidence_packet.instrument_id
  |> should.equal(fact.Unknown("resolver_not_called"))
  packet
  |> evidence_packet.provider_row
  |> fact.is_known
  |> should.be_true
  packet
  |> evidence_packet.available_operations
  |> list.length
  |> should.equal(2)
  packet
  |> evidence_packet.adjustment
  |> should.equal(fact.Unknown("provider_did_not_declare"))
}

fn timing_facts(next_open) -> timing.TimingFacts {
  let assert Ok(zone) = time.timezone("America/New_York")
  timing.new(
    source_timestamp: fact.Known("2026-06-18"),
    provider_publication_time: fact.Unknown("provider_date_only"),
    retrieved_at: instant(200),
    timezone: fact.Known(zone),
    session_close: fact.Known(instant(100)),
    next_session_open: next_open,
    time_basis: fact.Known(finance_ohlcv.SessionDateAnchor),
    calendar_version: fact.Known("fixture-calendar-v1"),
  )
}

fn unknown_rights() -> rights.RightsFacts {
  rights.new(
    provider: fact.Known("fixture-provider"),
    source_kind: fact.Known(rights.PublicWeb),
    licence_label: fact.Unknown("terms_not_obtained"),
    licence_source: fact.Unknown("terms_not_obtained"),
    attribution_required: rights.UnknownPredicate("terms_not_obtained"),
    attribution_text: fact.Unknown("terms_not_obtained"),
    redistribution: rights.UnknownPredicate("terms_not_obtained"),
    entitlement: fact.Unknown("entitlement_not_obtained"),
    cache: rights.UnknownPredicate("terms_not_obtained"),
    retention_limit_days: fact.Unknown("terms_not_obtained"),
    source_limitations: fact.Unknown("terms_not_obtained"),
  )
}

fn acquisition() -> acquisition_receipt.Receipt {
  let assert Ok(code) = acquisition_receipt.identity_field("code", "TEST")
  let assert Ok(content_hash) = identity.sha256(string.repeat("a", 64))
  let assert Ok(page) = acquisition_receipt.page(1, None, 100, content_hash)
  let assert Ok(value) =
    acquisition_receipt.new(
      schema: "pi-sparkles/test-information-contract",
      schema_version: 1,
      track: finance_track.Us,
      provider: "fixture-provider",
      identity: [code],
      source_reference: "fixture://response/1",
      retrieved_at: instant(200),
      pagination: acquisition_receipt.Complete,
      pages: [page],
      range_start: civil(2026, 6, 18),
      range_end: civil(2026, 6, 18),
      bar_dates: [civil(2026, 6, 18)],
    )
  value
}

fn instant(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
